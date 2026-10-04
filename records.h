/* records.h - OPT 4 data layout shared by the host program and the RV32I build.
 *
 * Everything the search needs about one permutation rank p sits in one 10-byte
 * record, and everything about one twist rank o in one 12-byte record, so
 * the search can carry BYTE OFFSETS (10 * p and 12 * o) instead of ranks:
 * every lookup is then one load with a constant offset from a single base
 * register, with no index scaling. next[f] holds the offset of the state after
 * one quarter turn of face f.                                              */
#include <stdint.h>

typedef struct {
    uint16_t next[3]; /* offset of the record after a quarter turn of face f */
    uint8_t h;        /* hp[p]: lower bound from the positions alone          */
    uint8_t pkA;      /* position key of table A                              */
    uint16_t pkB;     /* position key of table B                              */
} prec_t;             /* 10 bytes */

typedef struct {
    uint16_t next[3];
    uint8_t h;        /* ho[o]: lower bound from the twists alone             */
    uint8_t pad;
    uint16_t qkA;     /* twist key of table A, already times NP_A             */
    uint16_t qkB;     /* twist key of table B, already times NP_B             */
} orec_t;             /* 12 bytes */

enum { P_STRIDE = 10, O_STRIDE = 12, P_H = 6, P_PKA = 7, P_PKB = 8, O_H = 6, O_QKA = 8, O_QKB = 10 };
