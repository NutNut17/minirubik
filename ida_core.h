/* ida_core.h - the search, shared by the host program (ida.c) and the
 * freestanding RV32I build (rv/ida_rv.c).  The including file provides
 *   perm_next[3][5040], orient_next[3][729]   uint16_t   quarter-turn tables
 *   hp[5040], ho[729]                         uint8_t    projection tables
 *   pkA/pkB[5040], qkA/qkB[729]               key tables of the two pattern tables
 *   tabA, tabB                                uint8_t    nibble-packed tables
 * and the sizes NQ_A, NQ_B (twist-key range of each pattern table).
 * No multiply, divide, modulo or recursion is used at run time.            */

/* Optimisation level, one step per level so each can be measured alone:
 *   0  every child is rebuilt from the parent (R2 = 2 lookups, R' = 3)
 *   1  R2 and R' continue from the previous child of the same face
 *   2  + prune with the cheapest bound first (hp, ho, then the big tables)
 *   3  + twist keys pre-scaled, so a table index is one add, no multiply
 *   4  one record per state, the search carries byte offsets (ida_core4.h)
 *   5  per-level data in one frame struct walked by a pointer               */
#ifndef OPT
#define OPT 5
#endif

#if OPT >= 4
#include "ida_core4.h"
#else

enum { MAX_DEPTH = 11, MOVES = 9, NO_FACE = 3 };

/* move m = face * 3 + turns - 1; tables replace the divide and modulo by 3. */
static const uint8_t move_face[MOVES] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t move_turns[MOVES] = {1, 2, 3, 1, 2, 3, 1, 2, 3};
static const uint8_t face_end[3] = {3, 6, 9}; /* first move after the face */

/* Packed accessor, two 4-bit entries per byte, even index in the low nibble. */
static inline unsigned nib(const uint8_t *t, unsigned i)
{
    return (t[i >> 1] >> ((i & 1U) << 2)) & 15U;
}

/* h = max of four admissible lower bounds, each a minimum of true distance
 * over every state that shares its key (see build_tables in ida.c):
 *   hp[p]                    positions only
 *   ho[o]                    twists only
 *   tabA[pkA[p]+qkA[o]*NP_A] positions of a few cubies + most twists
 *   tabB[pkB[p]+qkB[o]*NP_B] positions of other cubies + a few twists       */
#if OPT >= 3
#define KEY_A(p, o) ((unsigned) pkA[p] + qkAS[o])
#define KEY_B(p, o) ((unsigned) pkB[p] + qkBS[o])
#else
#define KEY_A(p, o) ((unsigned) pkA[p] + (unsigned) qkA[o] * NP_A)
#define KEY_B(p, o) ((unsigned) pkB[p] + (unsigned) qkB[o] * NP_B)
#endif

static inline uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t h = hp[p], x = ho[o];
    if (x > h) h = x;
    x = (uint8_t) nib(tabA, KEY_A(p, o));
    if (x > h) h = x;
    x = (uint8_t) nib(tabB, KEY_B(p, o));
    if (x > h) h = x;
    return h;
}

/* h(p, o) <= budget, testing the cheapest bound first: most children are
 * rejected by hp or ho and never touch the two big tables. */
static inline int within(uint16_t p, uint16_t o, unsigned budget)
{
    if (hp[p] > budget || ho[o] > budget)
        return 0;
    if (nib(tabA, KEY_A(p, o)) > budget)
        return 0;
    return nib(tabB, KEY_B(p, o)) <= budget;
}

/* Iterative-deepening A*, explicit stack.
 *
 * Outer loop: bound = h(start), h(start)+1, ... MAX_DEPTH.
 * Inner loop: depth-first walk. Level d holds the state after d moves
 * (lp/lo), the next move to try there (next) and the face just moved (last);
 * depth++ extends the path, depth-- backs up when every move has been tried.
 *
 * A child is kept only if g + h <= bound with g = depth + 1. h never exceeds
 * the true distance (gate H1), so no node on an optimal path is pruned, the
 * first bound that succeeds is the exact distance, and the result is optimal.
 * h == 0 only for the solved state, so at g == bound an unsolved child is
 * pruned and depth stays <= bound - 1 <= 10: eleven slots suffice.
 *
 * A move costs 1 whatever its number of quarter turns (half-turn metric);
 * R2 and R' are 2 and 3 table lookups. After a move on face f, all three
 * moves on f are skipped (R R', R R, R R2 are nothing, R2, R').
 *
 * Returns the length; path[] holds face * 3 + turns - 1; *nodes counts the
 * children generated (one heuristic evaluation each).                     */
static int solve(uint16_t p, uint16_t o, uint8_t path[MAX_DEPTH], uint32_t *nodes)
{
    uint16_t lp[MAX_DEPTH + 1], lo[MAX_DEPTH + 1];
#if OPT >= 1
    uint16_t cp[MAX_DEPTH + 1], co[MAX_DEPTH + 1]; /* last child generated at each level */
#endif
    uint8_t next[MAX_DEPTH + 1], last[MAX_DEPTH + 1];

    *nodes = 0;
    if (p == 0 && o == 0)
        return 0;
    for (uint8_t bound = heuristic(p, o); bound <= MAX_DEPTH; ++bound) {
        int depth = 0;
        lp[0] = p;
        lo[0] = o;
        next[0] = 0;
        last[0] = NO_FACE;
        while (depth >= 0) {
            if (next[depth] == MOVES) {      /* every move tried: back up */
                --depth;
                continue;
            }
            uint8_t move = next[depth]++;
            uint8_t face = move_face[move], turns = move_turns[move];
            if (face == last[depth]) {       /* same face as before: skip all 3 */
                next[depth] = face_end[face];
                continue;
            }
#if OPT >= 1
            uint16_t np, no;
            if (turns == 1) {                /* from the parent */
                np = perm_next[face][lp[depth]];
                no = orient_next[face][lo[depth]];
            } else {                         /* one more turn on the last child */
                np = perm_next[face][cp[depth]];
                no = orient_next[face][co[depth]];
            }
            cp[depth] = np;
            co[depth] = no;
#else
            uint16_t np = lp[depth], no = lo[depth];
            for (uint8_t t = 0; t < turns; ++t) {
                np = perm_next[face][np];
                no = orient_next[face][no];
            }
#endif
            ++*nodes;
#if OPT >= 2
            if (!within(np, no, (unsigned) (bound - depth - 1)))
                continue;                    /* cannot finish within bound */
#else
            if (depth + 1 + heuristic(np, no) > bound)
                continue;                    /* cannot finish within bound */
#endif
            path[depth] = move;
            if (np == 0 && no == 0)
                return depth + 1;
            ++depth;
            lp[depth] = np;
            lo[depth] = no;
            next[depth] = 0;
            last[depth] = face;
        }
    }
    return -1;                               /* unreachable for valid states */
}

#endif /* OPT < 4 */
