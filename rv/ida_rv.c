/* ida_rv.c - freestanding RV32I build of the solver (the C reference that the
 * hand-written assembly has to beat).  No libc, no heap, no recursion, and no
 * multiply or divide at run time: build with
 *   riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib
 *
 * The state is the 14-character string STATE (default: the sample vector) or,
 * with -DFROM_REGS, the two ranks p and o passed in a0/a1 (used to measure the
 * search alone on many states with Ripes' --reginit).
 * Exit status: 0 = solved and the path replays to the solved state,
 *              1 = replay failed, 2 = length differs from EXPECT_LEN.        */
#include <stdint.h>
#include "../records.h"
#include "tables.h"
#include "../ida_core.h"

#ifndef STATE
#define STATE "21345671111111"
#endif
#ifndef EXPECT_LEN
#define EXPECT_LEN 11
#endif

/* Rank of the input: Lehmer code of the seven cubies and base-3 value of the
 * first six twists.  The unrolled loop gives constant radices, so the
 * compiler turns every multiply into shifts and adds.                      */
static void rank_input(const char *s, uint16_t *p_out, uint16_t *o_out)
{
    uint32_t p = 0, o = 0;
#pragma GCC unroll 7
    for (unsigned i = 0; i < 7; ++i) {
        unsigned smaller = 0;
        for (unsigned j = i + 1U; j < 7; ++j)
            smaller += s[j] < s[i];
        p = p * (7U - i) + smaller;
    }
#pragma GCC unroll 6
    for (unsigned i = 0; i < 6; ++i)
        o = o * 3U + (unsigned) (s[7 + i] - '1');
    *p_out = (uint16_t) p;
    *o_out = (uint16_t) o;
}

static uint8_t g_path[MAX_DEPTH];
static uint32_t g_nodes;

#ifdef FROM_REGS
int main(void)
{
    register uint32_t a0_ asm("a0"), a1_ asm("a1");
    uint16_t p = (uint16_t) a0_, o = (uint16_t) a1_;
#else
int main(void)
{
    uint16_t p, o;
    rank_input(STATE, &p, &o);
#endif
    int len = solve(p, o, g_path, &g_nodes);
#if OPT >= 4
    unsigned po = (unsigned) p * P_STRIDE, oo = (unsigned) o * O_STRIDE;
    for (int i = 0; i < len; ++i)
        for (uint8_t t = 0; t < move_turns[g_path[i]]; ++t) {
            po = U16(PB, po + move_f2[g_path[i]]);
            oo = U16(OB, oo + move_f2[g_path[i]]);
        }
    if (po != 0 || oo != 0)
        return 1;
#else
    for (int i = 0; i < len; ++i)
        for (uint8_t t = 0; t < move_turns[g_path[i]]; ++t) {
            p = perm_next[move_face[g_path[i]]][p];
            o = orient_next[move_face[g_path[i]]][o];
        }
    if (p != 0 || o != 0)
        return 1;
#endif
    return len == EXPECT_LEN ? 0 : 2;
}
