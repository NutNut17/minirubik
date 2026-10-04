/* ida.c - optimal 2x2x2 solver by IDA* with pattern-database heuristics.
 *
 * Host program: builds the heuristic tables from the exact BFS distances,
 * checks gates H1-H4 against that oracle, and emits the tables as a header
 * for the freestanding RV32I build (rv/ida_rv.c). The search itself is in
 * ida_core.h and is shared by both builds.
 *
 *   ./ida 21345671111111          solve one state
 *   ./ida --tables                table sizes, static-data budget, gate H2
 *   ./ida --check                 gates H1, H2, H4 (about 1 s)
 *   ./ida --h3 [stride]           gate H3 + path replay (T5) and node counts
 *   ./ida --emit rv/tables.h      write the read-only tables for the C target build
 *   ./ida --emit-asm asm/tables.s write the same tables as .data for hand-written RV32I
 *
 * Cube model, ranking and the BFS oracle follow solver.c. build_tables(),
 * the table selection and the search were written with AI assistance
 * (disclose under Section 4.1 of the AI guidelines).                       */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "records.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    UNSET = 0xFF
};

/* ---- the two pattern tables: what each one remembers -------------------- */
/* A table remembers where a few cubies are (mask over cubies 0..6) and the
 * twist at a few positions (mask over positions 0..5), and stores the
 * smallest true distance of any state that agrees with the key.            */
#define A_CUBIES 0x49u /* cubies 0, 3, 6          -> 7*6*5     = 210 */
#define A_TWISTS 0x3Du /* positions 0, 2, 3, 4, 5 -> 3^5       = 243 */
#define B_CUBIES 0x2Fu /* cubies 0, 1, 2, 3, 5    -> 7*6*5*4*3 = 2520 */
#define B_TWISTS 0x07u /* positions 0, 1, 2       -> 3^3       = 27  */
enum {
    NP_A = 210, NQ_A = 243, KEYS_A = NP_A * NQ_A,
    NP_B = 2520, NQ_B = 27, KEYS_B = NP_B * NQ_B
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/* ---- cube model: copied from solver.c (do not change) ------------------- */
static const char *const move_names[9] = {"R",  "R2", "R'", "B", "B2",
                                          "B'", "D",  "D2", "D'"};
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static state_t quarter_turn(state_t s, uint8_t face)
{
    state_t r;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        r.p[i] = s.p[source[face][i]];
        r.o[i] = (uint8_t) ((s.o[source[face][i]] + twist[face][i]) % 3U);
    }
    return r;
}

static uint32_t rank_state(const state_t *s)
{
    uint32_t p = 0, o = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j)
            smaller += s->p[j] < s->p[i];
        p = p * (CUBIES - i) + smaller;
    }
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + s->o[i];
    return p * ORIENTATIONS + o;
}

static void unrank_state(uint32_t rank, state_t *s)
{
    uint8_t avail[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / ORIENTATIONS, o = rank % ORIENTATIONS, f = 720;
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t q = (uint8_t) (p / f);
        p %= f;
        s->p[i] = avail[q];
        for (uint8_t j = q; j + 1U < CUBIES - i; ++j)
            avail[j] = avail[j + 1U];
        if (i < 5)
            f /= 6U - i;
    }
    for (uint8_t i = 6; i-- > 0;) {
        s->o[i] = (uint8_t) (o % 3U);
        sum = (uint8_t) (sum + s->o[i]);
        o /= 3U;
    }
    s->o[6] = (uint8_t) ((3U - sum % 3U) % 3U);
}

/* ---- tables read by the search (same names as in the RV32I build) ------- */
static uint16_t perm_next_[3][PERMUTATIONS];  /* 30,240 B */
static uint16_t orient_next_[3][ORIENTATIONS]; /*  4,374 B */
static uint16_t *const perm_next[3] = {perm_next_[0], perm_next_[1], perm_next_[2]};
static uint16_t *const orient_next[3] = {orient_next_[0], orient_next_[1], orient_next_[2]};
static uint8_t hp[PERMUTATIONS];              /*  5,040 B  positions only */
static uint8_t ho[ORIENTATIONS];              /*    729 B  twists only */
static uint16_t pkA[PERMUTATIONS], pkB[PERMUTATIONS];
static uint16_t qkA[ORIENTATIONS], qkB[ORIENTATIONS];
static uint16_t qkAS[ORIENTATIONS], qkBS[ORIENTATIONS]; /* qk * NP: index = pk + qkS */
static uint8_t tabA[(KEYS_A + 1) / 2];        /* 25,515 B  nibble-packed */
static uint8_t tabB[(KEYS_B + 1) / 2];        /* 34,020 B  nibble-packed */
static uint8_t *raw_A, *raw_B;                /* host only: one byte per key */
static prec_t PREC[PERMUTATIONS];             /* OPT 4: one record per state, see records.h */
static orec_t OREC[ORIENTATIONS];

#include "ida_core.h"

static void build_transitions(void)
{
    state_t s;
    for (uint32_t p = 0; p < PERMUTATIONS; ++p) {
        unrank_state(p * ORIENTATIONS, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            perm_next[f][p] = (uint16_t) (rank_state(&n) / ORIENTATIONS);
        }
    }
    for (uint32_t o = 0; o < ORIENTATIONS; ++o) {
        unrank_state(o, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            orient_next[f][o] = (uint16_t) (rank_state(&n) % ORIENTATIONS);
        }
    }
}

/* Exact distance of every state, by BFS from solved: the oracle of gates
 * H1/H3 and the source of every table. Host only. Cached. */
static const uint8_t *exact_distances(void)
{
    static uint8_t *cache;
    if (cache)
        return cache;
    uint8_t *d = malloc(STATES);
    uint32_t *q = malloc((size_t) STATES * sizeof *q);
    uint32_t head = 0, tail = 1;
    if (!d || !q) { fputs("out of memory\n", stderr); exit(1); }
    memset(d, UNSET, STATES);
    d[0] = 0; q[0] = 0;
    while (head < tail) {
        uint32_t here = q[head++];
        for (uint8_t f = 0; f < 3; ++f) {
            uint16_t np = (uint16_t) (here / ORIENTATIONS);
            uint16_t no = (uint16_t) (here % ORIENTATIONS);
            for (uint8_t t = 0; t < 3; ++t) {
                np = perm_next[f][np]; no = orient_next[f][no];
                uint32_t there = (uint32_t) np * ORIENTATIONS + no;
                if (d[there] == UNSET) { d[there] = (uint8_t) (d[here] + 1); q[tail++] = there; }
            }
        }
    }
    free(q);
    cache = d;
    return d;
}

/* Rank of where the tracked cubies sit: for each tracked cubie in increasing
 * order, its position among the positions the earlier ones left free, in
 * mixed radix 7, 6, 5, ... */
static uint16_t position_key(const state_t *s, unsigned cubies)
{
    uint8_t where[CUBIES];
    unsigned key = 0, used = 0, radix = CUBIES;
    for (uint8_t i = 0; i < CUBIES; ++i)
        where[s->p[i]] = i;
    for (uint8_t c = 0; c < CUBIES; ++c) {
        if (!(cubies >> c & 1U))
            continue;
        unsigned below = 0;
        for (uint8_t i = 0; i < where[c]; ++i)
            below += used >> i & 1U;
        key = key * radix + (where[c] - below);
        used |= 1U << where[c];
        --radix;
    }
    return (uint16_t) key;
}

/* Base-3 number of the twists at the tracked positions. */
static uint16_t twist_key(const state_t *s, unsigned positions)
{
    unsigned key = 0;
    for (uint8_t i = 0; i < 6; ++i)
        if (positions >> i & 1U)
            key = key * 3U + s->o[i];
    return (uint16_t) key;
}

/* One pattern table = minimum of the true distance over all states sharing
 * the key. A minimum over a set of states cannot exceed the distance of any
 * member, so the table is admissible (gate H1 checks it exhaustively). */
static void fill_pattern(uint8_t *raw, uint16_t *pk, uint16_t *qk, unsigned np,
                         unsigned keys, unsigned cubies, unsigned twists,
                         const uint8_t *d)
{
    state_t s;
    memset(raw, UNSET, keys);
    for (uint32_t p = 0; p < PERMUTATIONS; ++p) {
        unrank_state(p * ORIENTATIONS, &s);
        pk[p] = position_key(&s, cubies);
    }
    for (uint32_t o = 0; o < ORIENTATIONS; ++o) {
        unrank_state(o, &s);
        qk[o] = twist_key(&s, twists);
    }
    for (uint32_t r = 0; r < STATES; ++r) {
        uint32_t k = pk[r / ORIENTATIONS] + (uint32_t) qk[r % ORIENTATIONS] * np;
        if (d[r] < raw[k])
            raw[k] = d[r];
    }
}

static void pack(uint8_t *packed, const uint8_t *raw, unsigned keys)
{
    memset(packed, 0, (keys + 1U) / 2U);
    for (unsigned i = 0; i < keys; ++i)
        packed[i >> 1] |= (uint8_t) (raw[i] << ((i & 1U) << 2));
}

static void build_tables(void)
{
    const uint8_t *d = exact_distances();
    raw_A = malloc(KEYS_A);
    raw_B = malloc(KEYS_B);
    memset(hp, UNSET, sizeof hp);
    memset(ho, UNSET, sizeof ho);
    for (uint32_t r = 0; r < STATES; ++r) {
        uint16_t p = (uint16_t) (r / ORIENTATIONS), o = (uint16_t) (r % ORIENTATIONS);
        if (d[r] < hp[p]) hp[p] = d[r];
        if (d[r] < ho[o]) ho[o] = d[r];
    }
    fill_pattern(raw_A, pkA, qkA, NP_A, KEYS_A, A_CUBIES, A_TWISTS, d);
    fill_pattern(raw_B, pkB, qkB, NP_B, KEYS_B, B_CUBIES, B_TWISTS, d);
    /* Index is pk + qk * NP (not pk * NQ + qk), so that the multiply moves into
     * the table: the largest scaled value is 26 * 2520 = 65520 < 65536. */
    for (unsigned o = 0; o < ORIENTATIONS; ++o) {
        qkAS[o] = (uint16_t) (qkA[o] * NP_A);
        qkBS[o] = (uint16_t) (qkB[o] * NP_B);
    }
    pack(tabA, raw_A, KEYS_A);
    pack(tabB, raw_B, KEYS_B);
    for (unsigned p = 0; p < PERMUTATIONS; ++p) {
        for (unsigned f = 0; f < 3; ++f)
            PREC[p].next[f] = (uint16_t) (perm_next[f][p] * P_STRIDE);
        PREC[p].h = hp[p];
        PREC[p].pkA = (uint8_t) pkA[p];
        PREC[p].pkB = pkB[p];
    }
    for (unsigned o = 0; o < ORIENTATIONS; ++o) {
        for (unsigned f = 0; f < 3; ++f)
            OREC[o].next[f] = (uint16_t) (orient_next[f][o] * O_STRIDE);
        OREC[o].h = ho[o];
        OREC[o].qkA = qkAS[o];
        OREC[o].qkB = qkBS[o];
    }
}

/* ---- gates (host only; they use the exact table) ------------------------ */
static int check_table(const char *name, const uint8_t *raw, unsigned keys, unsigned solved_key)
{
    unsigned max = 0, bad = 0;
    for (unsigned i = 0; i < keys; ++i) {
        if (raw[i] == UNSET) ++bad;
        else if (raw[i] > max) max = raw[i];
    }
    printf("H2 %-4s %6u entries, unfilled %u, max %u, solved entry %u\n",
           name, keys, bad, max, raw[solved_key]);
    return bad == 0 && raw[solved_key] == 0 && max <= 15;
}

static int gate_h2(void)
{
    unsigned mp = 0, mo = 0;
    int ok = 1;
    for (unsigned i = 0; i < PERMUTATIONS; ++i) { ok &= hp[i] != UNSET; if (hp[i] != UNSET && hp[i] > mp) mp = hp[i]; }
    for (unsigned i = 0; i < ORIENTATIONS; ++i) { ok &= ho[i] != UNSET; if (ho[i] != UNSET && ho[i] > mo) mo = ho[i]; }
    printf("H2 hp   %6d entries, max %u, solved entry %u\n", PERMUTATIONS, mp, hp[0]);
    printf("H2 ho   %6d entries, max %u, solved entry %u\n", ORIENTATIONS, mo, ho[0]);
    ok &= hp[0] == 0 && ho[0] == 0;
    /* the solved state has p = o = 0, so its key is pk[0] + qk[0] * np */
    ok &= check_table("tabA", raw_A, KEYS_A, (unsigned) pkA[0] + qkA[0] * NP_A);
    ok &= check_table("tabB", raw_B, KEYS_B, (unsigned) pkB[0] + qkB[0] * NP_B);
    return ok;
}

static int gate_h1(const uint8_t *exact)
{
    uint32_t bad = 0; uint64_t sum_h = 0, sum_d = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
        uint8_t h = heuristic((uint16_t) (r / ORIENTATIONS), (uint16_t) (r % ORIENTATIONS));
        sum_h += h; sum_d += exact[r];
        if (h > exact[r]) ++bad;
    }
    printf("H1 inadmissible states: %u of %d   mean h %.3f vs mean true distance %.3f\n",
           bad, STATES, (double) sum_h / STATES, (double) sum_d / STATES);
    return bad == 0;
}

static int gate_h4(void)
{
    unsigned bad = 0;
    for (unsigned i = 0; i < KEYS_A; ++i) bad += nib(tabA, i) != raw_A[i];
    for (unsigned i = 0; i < KEYS_B; ++i) bad += nib(tabB, i) != raw_B[i];
    printf("H4 packed vs unpacked mismatches (even and odd indices): %u of %d\n",
           bad, KEYS_A + KEYS_B);
    return bad == 0;
}

/* Gate H3 (+ T5 on the host): solve every STRIDE-th state; the length must
 * equal the exact distance and replaying the path must reach the solved
 * state. Prints node counts per true distance. */
static int gate_h3(const uint8_t *exact, uint32_t stride)
{
    static uint64_t cnt[12], sum[12], max[12];
    uint32_t wrong = 0, unsolved = 0;
    for (uint32_t r = 0; r < STATES; r += stride) {
        uint8_t path[MAX_DEPTH];
        uint32_t nodes;
        uint16_t p = (uint16_t) (r / ORIENTATIONS), o = (uint16_t) (r % ORIENTATIONS);
        int len = solve(p, o, path, &nodes);
        uint8_t d = exact[r];
        if (len != d) ++wrong;
        uint16_t cp = p, co = o;
        for (int i = 0; i < len; ++i)
            for (uint8_t t = 0; t < move_turns[path[i]]; ++t) {
                cp = perm_next[move_face[path[i]]][cp];
                co = orient_next[move_face[path[i]]][co];
            }
        if (cp != 0 || co != 0) ++unsolved;
        ++cnt[d]; sum[d] += nodes; if (nodes > max[d]) max[d] = nodes;
    }
    puts("dist  states   mean nodes     max nodes");
    for (int d = 0; d <= 11; ++d)
        if (cnt[d])
            printf("%4d %8llu %12.1f %13llu\n", d, (unsigned long long) cnt[d],
                   (double) sum[d] / cnt[d], (unsigned long long) max[d]);
    printf("H3 wrong length: %u   paths that do not reach solved: %u   (stride %u)\n",
           wrong, unsolved, stride);
    return wrong == 0 && unsolved == 0;
}

/* ---- static data of the target build ------------------------------------ */
enum {
    BYTES_PREC = PERMUTATIONS * P_STRIDE,  /* next[3], hp, pkA, pkB per permutation rank */
    BYTES_OREC = ORIENTATIONS * O_STRIDE,  /* next[3], ho, qkA, qkB per twist rank */
    BYTES_PATTERNS = (KEYS_A + 1) / 2 + (KEYS_B + 1) / 2,
    BYTES_MOVES = 3 * 9 + 11,              /* move tables and the .bss of the target build */
    BYTES_TOTAL = BYTES_PREC + BYTES_OREC + BYTES_PATTERNS + BYTES_MOVES
};

static void print_budget(void)
{
    printf("static data of the target build (the 128 KiB budget is 131072 B):\n");
    printf("  permutation records  %6d B  (%d x %d: next[3], hp, pkA, pkB)\n", BYTES_PREC, PERMUTATIONS, P_STRIDE);
    printf("  twist records        %6d B  (%d x %d: next[3], ho, qkA, qkB)\n", BYTES_OREC, ORIENTATIONS, O_STRIDE);
    printf("  tabA + tabB          %6d B  (%d + %d keys, 4 bits each)\n", BYTES_PATTERNS, KEYS_A, KEYS_B);
    printf("  move tables + .bss   %6d B\n", BYTES_MOVES);
    printf("  total                %6d B = %.1f KiB, %d B spare\n", BYTES_TOTAL,
           BYTES_TOTAL / 1024.0, 131072 - BYTES_TOTAL);
    puts("  (compare: riscv64-elf-size -A rv/ida_rv.elf, .rodata + .data + .bss)");
}

/* ---- emit the tables for the RV32I build -------------------------------- */
static void emit_array(FILE *f, const char *type, const char *name, const void *data,
                       size_t n, size_t width, int per_line)
{
    fprintf(f, "static const %s %s[%zu] = {", type, name, n);
    for (size_t i = 0; i < n; ++i) {
        unsigned v = width == 1 ? ((const uint8_t *) data)[i] : ((const uint16_t *) data)[i];
        fprintf(f, "%s%u,", i % (size_t) per_line ? "" : "\n    ", v);
    }
    fprintf(f, "\n};\n");
}

static int emit(const char *path)
{
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); return 0; }
    fprintf(f, "/* generated by ida --emit: read-only tables for rv/ida_rv.c */\n");
    fprintf(f, "enum { NP_A = %d, NP_B = %d, NQ_A = %d, NQ_B = %d };\n", NP_A, NP_B, NQ_A, NQ_B);
    for (int face = 0; face < 3; ++face) {
        char name[32];
        snprintf(name, sizeof name, "perm_next_%d", face);
        emit_array(f, "uint16_t", name, perm_next[face], PERMUTATIONS, 2, 16);
    }
    for (int face = 0; face < 3; ++face) {
        char name[32];
        snprintf(name, sizeof name, "orient_next_%d", face);
        emit_array(f, "uint16_t", name, orient_next[face], ORIENTATIONS, 2, 16);
    }
    fprintf(f, "static const uint16_t *const perm_next[3] = {perm_next_0, perm_next_1, perm_next_2};\n");
    fprintf(f, "static const uint16_t *const orient_next[3] = {orient_next_0, orient_next_1, orient_next_2};\n");
    emit_array(f, "uint8_t", "hp", hp, PERMUTATIONS, 1, 32);
    emit_array(f, "uint8_t", "ho", ho, ORIENTATIONS, 1, 32);
    uint8_t *tmp = malloc(PERMUTATIONS);
    for (int i = 0; i < PERMUTATIONS; ++i) tmp[i] = (uint8_t) pkA[i];
    emit_array(f, "uint8_t", "pkA", tmp, PERMUTATIONS, 1, 32);
    free(tmp);
    emit_array(f, "uint16_t", "pkB", pkB, PERMUTATIONS, 2, 16);
    tmp = malloc(ORIENTATIONS);
    for (int i = 0; i < ORIENTATIONS; ++i) tmp[i] = (uint8_t) qkA[i];
    emit_array(f, "uint8_t", "qkA", tmp, ORIENTATIONS, 1, 32);
    for (int i = 0; i < ORIENTATIONS; ++i) tmp[i] = (uint8_t) qkB[i];
    emit_array(f, "uint8_t", "qkB", tmp, ORIENTATIONS, 1, 32);
    free(tmp);
    emit_array(f, "uint16_t", "qkAS", qkAS, ORIENTATIONS, 2, 16);
    emit_array(f, "uint16_t", "qkBS", qkBS, ORIENTATIONS, 2, 16);
    fprintf(f, "static const prec_t PREC[%d] = {\n", PERMUTATIONS);
    for (unsigned p = 0; p < PERMUTATIONS; ++p)
        fprintf(f, "    {{%u,%u,%u},%u,%u,%u},\n", PREC[p].next[0], PREC[p].next[1], PREC[p].next[2], PREC[p].h, PREC[p].pkA, PREC[p].pkB);
    fprintf(f, "};\nstatic const orec_t OREC[%d] = {\n", ORIENTATIONS);
    for (unsigned o = 0; o < ORIENTATIONS; ++o)
        fprintf(f, "    {{%u,%u,%u},%u,0,%u,%u},\n", OREC[o].next[0], OREC[o].next[1], OREC[o].next[2], OREC[o].h, OREC[o].qkA, OREC[o].qkB);
    fprintf(f, "};\n");
    emit_array(f, "uint8_t", "tabA", tabA, sizeof tabA, 1, 32);
    emit_array(f, "uint8_t", "tabB", tabB, sizeof tabB, 1, 32);
    fclose(f);
    printf("wrote %s\n", path);
    return 1;
}

/* Same tables as assembly data for a hand-written RV32I program. Ripes'
 * assembler has only .data and .text, so everything goes to .data; the byte
 * layout of each record is the one in records.h. */
static void asm_bytes(FILE *f, const uint8_t *data, size_t n)
{
    for (size_t i = 0; i < n; ++i)
        fprintf(f, "%s%u%s", i % 32 ? "," : "    .byte ", data[i], i % 32 == 31 || i + 1 == n ? "\n" : "");
}

static int emit_asm(const char *path)
{
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); return 0; }
    fprintf(f, "# generated by: ida --emit-asm (do not edit)\n");
    fprintf(f, "# PREC: %d records x %d B = next[3] (.half, byte offsets), hp, pkA (.byte), pkB (.half)\n", PERMUTATIONS, P_STRIDE);
    fprintf(f, "# OREC: %d records x %d B = next[3] (.half), ho, pad (.byte), qkA, qkB (.half, pre-scaled)\n", ORIENTATIONS, O_STRIDE);
    fprintf(f, "# TABA: %d nibbles, TABB: %d nibbles, two entries per byte, even index in the low nibble\n", KEYS_A, KEYS_B);
    fprintf(f, "    .data\nPREC:\n");
    for (unsigned p = 0; p < PERMUTATIONS; ++p)
        fprintf(f, "    .half %u,%u,%u\n    .byte %u,%u\n    .half %u\n", PREC[p].next[0], PREC[p].next[1], PREC[p].next[2], PREC[p].h, PREC[p].pkA, PREC[p].pkB);
    fprintf(f, "OREC:\n");
    for (unsigned o = 0; o < ORIENTATIONS; ++o)
        fprintf(f, "    .half %u,%u,%u\n    .byte %u,0\n    .half %u,%u\n", OREC[o].next[0], OREC[o].next[1], OREC[o].next[2], OREC[o].h, OREC[o].qkA, OREC[o].qkB);
    fprintf(f, "TABA:\n");
    asm_bytes(f, tabA, sizeof tabA);
    fprintf(f, "TABB:\n");
    asm_bytes(f, tabB, sizeof tabB);
    fclose(f);
    printf("wrote %s\n", path);
    return 1;
}

static int parse(const char *in, state_t *s)
{
    if (strlen(in) != 14) return 0;
    for (int i = 0; i < 14; ++i) {
        int lim = i < 7 ? 7 : 3;
        if (in[i] < '1' || in[i] > '0' + lim) return 0;
        (i < 7 ? s->p : s->o)[i % 7] = (uint8_t) (in[i] - '1');
    }
    uint8_t seen = 0, sum = 0;
    for (int i = 0; i < CUBIES; ++i) { seen |= (uint8_t) (1U << s->p[i]); sum += s->o[i]; }
    return seen == 0x7F && sum % 3 == 0;
}

int main(int argc, char **argv)
{
    build_transitions();
    build_tables();
    if (argc == 2 && !strcmp(argv[1], "--tables")) {
        print_budget();
        return gate_h2() ? 0 : 1;
    }
    if (argc == 2 && !strcmp(argv[1], "--check")) {
        int ok = gate_h2();
        ok &= gate_h4();
        ok &= gate_h1(exact_distances());
        return ok ? 0 : 1;
    }
    if (argc >= 2 && !strcmp(argv[1], "--h3"))
        return gate_h3(exact_distances(), argc > 2 ? (uint32_t) atoi(argv[2]) : 1U) ? 0 : 1;
    if (argc == 3 && !strcmp(argv[1], "--emit"))
        return emit(argv[2]) ? 0 : 1;
    if (argc == 3 && !strcmp(argv[1], "--emit-asm"))
        return emit_asm(argv[2]) ? 0 : 1;
    state_t s; uint8_t path[MAX_DEPTH]; uint32_t nodes;
    if (argc != 2 || !parse(argv[1], &s)) {
        fputs("usage: ida <14 digits> | --tables | --check | --h3 [stride] | --emit file | --emit-asm file\n", stderr);
        return 2;
    }
    uint32_t r = rank_state(&s);
    int len = solve((uint16_t) (r / ORIENTATIONS), (uint16_t) (r % ORIENTATIONS), path, &nodes);
    if (len < 0) { fputs("no solution found (invalid state?)\n", stderr); return 1; }
    for (int i = 0; i < len; ++i) printf(i ? " %s" : "%s", move_names[path[i]]);
    printf("\n%d moves, %u nodes\n", len, nodes);
    return 0;
}
