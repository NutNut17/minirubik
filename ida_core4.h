/* ida_core4.h - the OPT 4 search: same algorithm and same pruning decisions as
 * ida_core.h (so the node counts are identical), over the record layout of
 * records.h. The includer provides PREC[], OREC[], tabA, tabB and NP_A/NP_B. */

enum { MAX_DEPTH = 11, MOVES = 9, NO_FACE = 6 };

/* move m = face * 3 + turns - 1, with the face as a byte offset 2 * face. */
static const uint8_t move_f2[MOVES] = {0, 0, 0, 2, 2, 2, 4, 4, 4};
static const uint8_t move_turns[MOVES] = {1, 2, 3, 1, 2, 3, 1, 2, 3};
static const uint8_t move_end[MOVES] = {3, 3, 3, 6, 6, 6, 9, 9, 9}; /* first move of the next face */
static const uint8_t move_face[MOVES] = {0, 0, 0, 1, 1, 1, 2, 2, 2}; /* path replay and gates */

static inline unsigned nib(const uint8_t *t, unsigned i)
{
    return (t[i >> 1] >> ((i & 1U) << 2)) & 15U;
}

#define PB ((const uint8_t *) PREC)
#define OB ((const uint8_t *) OREC)
#define U16(base, off) (*(const uint16_t *) ((base) + (off)))

/* The four lower bounds (see ida_core.h) read from the two records. */
static inline unsigned key_a(unsigned po, unsigned oo) { return PB[po + P_PKA] + U16(OB, oo + O_QKA); }
static inline unsigned key_b(unsigned po, unsigned oo) { return U16(PB, po + P_PKB) + U16(OB, oo + O_QKB); }

static inline uint8_t heuristic_off(unsigned po, unsigned oo)
{
    uint8_t h = PB[po + P_H], x = OB[oo + O_H];
    if (x > h) h = x;
    x = (uint8_t) nib(tabA, key_a(po, oo));
    if (x > h) h = x;
    x = (uint8_t) nib(tabB, key_b(po, oo));
    if (x > h) h = x;
    return h;
}

/* h <= budget, cheapest bound first. */
static inline int within(unsigned po, unsigned oo, unsigned budget)
{
    if (PB[po + P_H] > budget || OB[oo + O_H] > budget)
        return 0;
    if (nib(tabA, key_a(po, oo)) > budget)
        return 0;
    return nib(tabB, key_b(po, oo)) <= budget;
}

/* host gates ask for the bound of a rank pair */
static inline uint8_t heuristic(uint16_t p, uint16_t o)
{
    return heuristic_off((unsigned) p * P_STRIDE, (unsigned) o * O_STRIDE);
}

#if OPT >= 5
/* One frame per level, walked with a pointer: every per-level access is a load
 * or store with a constant offset, and depth++ / depth-- is one add. */
typedef struct {
    uint16_t lp, lo; /* state after `depth` moves */
    uint16_t cp, co; /* last child generated at this level */
    uint8_t next;    /* next move to try */
    uint8_t last;    /* face offset just moved */
    uint8_t move;    /* move taken from this level (the path) */
    uint8_t pad;
} frame_t;

static int solve(uint16_t p, uint16_t o, uint8_t path[MAX_DEPTH], uint32_t *nodes_out)
{
    frame_t stack[MAX_DEPTH + 1];
    uint32_t nodes = 0;
    unsigned po = (unsigned) p * P_STRIDE, oo = (unsigned) o * O_STRIDE;

    *nodes_out = 0;
    if (po == 0 && oo == 0)
        return 0;
    for (uint8_t bound = heuristic_off(po, oo); bound <= MAX_DEPTH; ++bound) {
        frame_t *f = stack;
        unsigned budget = (unsigned) bound - 1U; /* bound - depth - 1 */
        f->lp = (uint16_t) po;
        f->lo = (uint16_t) oo;
        f->next = 0;
        f->last = NO_FACE;
        for (;;) {
            if (f->next == MOVES) {          /* every move tried: back up */
                if (f == stack)
                    break;
                --f;
                ++budget;
                continue;
            }
            uint8_t move = f->next++;
            uint8_t f2 = move_f2[move];
            if (f2 == f->last) {             /* same face as before: skip all 3 */
                f->next = move_end[move];
                continue;
            }
            unsigned npo, noo;
            if (move_turns[move] == 1) {     /* from the parent */
                npo = U16(PB, f->lp + f2);
                noo = U16(OB, f->lo + f2);
            } else {                         /* one more turn on the last child */
                npo = U16(PB, f->cp + f2);
                noo = U16(OB, f->co + f2);
            }
            f->cp = (uint16_t) npo;
            f->co = (uint16_t) noo;
            ++nodes;
            if (!within(npo, noo, budget))
                continue;                    /* cannot finish within bound */
            f->move = move;
            if (npo == 0 && noo == 0) {
                unsigned len = 0;            /* walk the frames: f - stack would divide by 12 */
                for (const frame_t *q = stack; q <= f; ++q)
                    path[len++] = q->move;
                *nodes_out = nodes;
                return (int) len;
            }
            ++f;
            --budget;
            f->lp = (uint16_t) npo;
            f->lo = (uint16_t) noo;
            f->next = 0;
            f->last = f2;
        }
    }
    *nodes_out = nodes;
    return -1;                               /* unreachable for valid states */
}
#else
static int solve(uint16_t p, uint16_t o, uint8_t path[MAX_DEPTH], uint32_t *nodes_out)
{
    uint16_t lp[MAX_DEPTH + 1], lo[MAX_DEPTH + 1]; /* state offsets per level */
    uint16_t cp[MAX_DEPTH + 1], co[MAX_DEPTH + 1]; /* last child generated at each level */
    uint8_t next[MAX_DEPTH + 1], last[MAX_DEPTH + 1];
    uint32_t nodes = 0;
    unsigned po = (unsigned) p * P_STRIDE, oo = (unsigned) o * O_STRIDE;

    *nodes_out = 0;
    if (po == 0 && oo == 0)
        return 0;
    for (uint8_t bound = heuristic_off(po, oo); bound <= MAX_DEPTH; ++bound) {
        int depth = 0;
        lp[0] = (uint16_t) po;
        lo[0] = (uint16_t) oo;
        next[0] = 0;
        last[0] = NO_FACE;
        while (depth >= 0) {
            if (next[depth] == MOVES) {      /* every move tried: back up */
                --depth;
                continue;
            }
            uint8_t move = next[depth]++;
            uint8_t f2 = move_f2[move];
            if (f2 == last[depth]) {         /* same face as before: skip all 3 */
                next[depth] = move_end[move];
                continue;
            }
            unsigned npo, noo;
            if (move_turns[move] == 1) {     /* from the parent */
                npo = U16(PB, lp[depth] + f2);
                noo = U16(OB, lo[depth] + f2);
            } else {                         /* one more turn on the last child */
                npo = U16(PB, cp[depth] + f2);
                noo = U16(OB, co[depth] + f2);
            }
            cp[depth] = (uint16_t) npo;
            co[depth] = (uint16_t) noo;
            ++nodes;
            if (!within(npo, noo, (unsigned) (bound - depth - 1)))
                continue;                    /* cannot finish within bound */
            path[depth] = move;
            if (npo == 0 && noo == 0) {
                *nodes_out = nodes;
                return depth + 1;
            }
            ++depth;
            lp[depth] = (uint16_t) npo;
            lo[depth] = (uint16_t) noo;
            next[depth] = 0;
            last[depth] = f2;
        }
    }
    *nodes_out = nodes;
    return -1;                               /* unreachable for valid states */
}
#endif /* OPT < 5 */
