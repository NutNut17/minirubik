// =====================================================================================
// solver.s - optimal 2x2x2 solver in RV32I: IDA* with pattern-table pruning.
//
//   in   a0 = address of the 14-character state string
//   out  a0 = number of moves (-1 if none found); path[0..a0-1] = moves, face * 3 + turns - 1
//   uses PREC, OREC, TABA, TABB (tables.s), path (main.s); no mul/div, no recursion, no heap.
//   main.s keeps nothing live in s0..s11 across the call, so they are used without saving.
//
// C reference: rank_input() in rv/ida_rv.c and solve() in ida_core4.h (OPT 5); data layouts: SPEC.md.
//
// REGISTERS during the search
//   s0 f       frame pointer (12-byte frames:  +0 lp, +2 lo, +4 cp, +6 co (halves), +8 next, +9 last, +10 move)
//   s1 budget  = bound - depth - 1
//   s2 bound   iterative-deepening limit
//   s3 PREC    s4 OREC    s5 TABA    s6 TABB    s7 FRAMES (root frame)    s8 MV (move tables)
//   s9 po      s10 oo     the start state as byte offsets (10 * p, 12 * o)
//   a5 move    a6 f2      the move being tried and its face offset (0 R, 2 B, 4 D)
//   a1 npo     a2 noo     the child state
// =====================================================================================
    .data
// MV: byte tables indexed by move 0..8 (R R2 R' B B2 B' D D2 D')
//   MV[0..8]   f2 = 2 * face, selects next[R|B|D] in a record
//   MV[9..17]  quarter turns of the move
//   MV[18..26] first move of the NEXT face (to skip all three moves of a face)
MV:     .byte 0,0,0,2,2,2,4,4,4,  1,2,3,1,2,3,1,2,3,  3,3,3,6,6,6,9,9,9
    .align 2
FRAMES: .zero 144                 // 12 frames x 12 bytes

    .text
    .globl solve
solve:
// ---- PART 1: rank the string ---------------------------------------------------------
// C:  for i in 0..6:  smaller = number of later digits < digit i ;  p = p * (7 - i) + smaller
//     for i in 0..5:  o = o * 3 + (s[7 + i] - '1')
// The seven cubie digits go to t0..t6; p is built by Horner's rule with constant factors 6,5,4,3,2.
    lbu  t0, 0(a0)
    lbu  t1, 1(a0)
    lbu  t2, 2(a0)
    lbu  t3, 3(a0)
    lbu  t4, 4(a0)
    lbu  t5, 5(a0)
    lbu  t6, 6(a0)
    sltu a1, t1, t0               // c0 = number of later digits smaller than digit 0; p = c0
    sltu a2, t2, t0
    add  a1, a1, a2
    sltu a2, t3, t0
    add  a1, a1, a2
    sltu a2, t4, t0
    add  a1, a1, a2
    sltu a2, t5, t0
    add  a1, a1, a2
    sltu a2, t6, t0
    add  a1, a1, a2
    sltu a2, t2, t1               // c1
    sltu a3, t3, t1
    add  a2, a2, a3
    sltu a3, t4, t1
    add  a2, a2, a3
    sltu a3, t5, t1
    add  a2, a2, a3
    sltu a3, t6, t1
    add  a2, a2, a3
    slli a3, a1, 2                // p = p * 6 + c1
    slli a1, a1, 1
    add  a1, a1, a3
    add  a1, a1, a2
    sltu a2, t3, t2               // c2
    sltu a3, t4, t2
    add  a2, a2, a3
    sltu a3, t5, t2
    add  a2, a2, a3
    sltu a3, t6, t2
    add  a2, a2, a3
    slli a3, a1, 2                // p = p * 5 + c2
    add  a1, a1, a3
    add  a1, a1, a2
    sltu a2, t4, t3               // c3
    sltu a3, t5, t3
    add  a2, a2, a3
    sltu a3, t6, t3
    add  a2, a2, a3
    slli a1, a1, 2                // p = p * 4 + c3
    add  a1, a1, a2
    sltu a2, t5, t4               // c4
    sltu a3, t6, t4
    add  a2, a2, a3
    slli a3, a1, 1                // p = p * 3 + c4
    add  a1, a1, a3
    add  a1, a1, a2
    sltu a2, t6, t5               // c5
    slli a1, a1, 1                // p = p * 2 + c5   (c6 is 0, p * 1 is p)
    add  a1, a1, a2               // a1 = p, 0..5039
    lbu  a2, 7(a0)                // o in Horner form over the raw characters, corrected once at the end
    lbu  a3, 8(a0)
    slli a4, a2, 1
    add  a2, a2, a4
    add  a2, a2, a3               // o = o * 3 + c
    lbu  a3, 9(a0)
    slli a4, a2, 1
    add  a2, a2, a4
    add  a2, a2, a3
    lbu  a3, 10(a0)
    slli a4, a2, 1
    add  a2, a2, a4
    add  a2, a2, a3
    lbu  a3, 11(a0)
    slli a4, a2, 1
    add  a2, a2, a4
    add  a2, a2, a3
    lbu  a3, 12(a0)
    slli a4, a2, 1
    add  a2, a2, a4
    add  a2, a2, a3
    li   a3, 17836                // '1' * (243 + 81 + 27 + 9 + 3 + 1) = 49 * 364
    sub  a2, a2, a3               // a2 = o, 0..728
    slli a3, a1, 3                // po = 10 * p
    slli a4, a1, 1
    add  s9, a3, a4
    slli a3, a2, 3                // oo = 12 * o
    slli a4, a2, 2
    add  s10, a3, a4
    or   t0, s9, s10
    bnez t0, sv_start
    li   a0, 0                    // solved: p = o = 0
    ret

// ---- PART 2: iterative deepening search ----------------------------------------------
sv_start:
    la   s3, PREC
    la   s4, OREC
    la   s5, TABA
    la   s6, TABB
    la   s7, FRAMES
    la   s8, MV
    li   s2, 1                    // bound = 1, 2, ... 11 (the start is not solved)
sv_bound:                         // C: frame_t *f = stack; budget = bound - 1; root frame
    mv   s0, s7
    addi s1, s2, -1
    sh   s9, 0(s0)                // lp = po
    sh   s10, 2(s0)               // lo = oo
    sb   zero, 8(s0)              // next = 0
    li   t0, 6
    sb   t0, 9(s0)                // last = 6 (no face)

sv_loop:                          // C: for (;;) {
    lbu  a5, 8(s0)                //        move = f->next
    li   t0, 9
    beq  a5, t0, sv_pop           //        if (move == 9) back up
    addi t0, a5, 1
    sb   t0, 8(s0)                //        f->next++
    add  t2, s8, a5               //        t2 = &MV[move]
    lbu  a6, 0(t2)                //        f2 = move_f2[move]
    lbu  t0, 9(s0)                //        f->last
    beq  a6, t0, sv_skip          //        same face as before: skip its three moves
    lbu  t0, 9(t2)                //        move_turns[move]
    li   t1, 1
    bne  t0, t1, sv_again
    lhu  a1, 0(s0)                //        first turn of a face: from the parent (lp, lo)
    lhu  a2, 2(s0)
    j    sv_child
sv_again:
    lhu  a1, 4(s0)                //        R2 / R': one more turn on the last child (cp, co)
    lhu  a2, 6(s0)
sv_child:
    add  a1, a1, s3               //        npo = half[PREC + lp + f2]
    add  a1, a1, a6
    lhu  a1, 0(a1)
    add  a2, a2, s4               //        noo = half[OREC + lo + f2]
    add  a2, a2, a6
    lhu  a2, 0(a2)
    sh   a1, 4(s0)                //        f->cp = npo
    sh   a2, 6(s0)                //        f->co = noo
    // within(npo, noo, budget): h <= budget, cheapest bound first
    add  t0, s3, a1               //        t0 = &PREC record, t1 = &OREC record
    add  t1, s4, a2
    lbu  t4, 6(t0)                //        hp
    bltu s1, t4, sv_loop          //        hp > budget: drop this child
    lbu  t5, 6(t1)                //        ho
    bltu s1, t5, sv_loop
    lbu  t4, 7(t0)                //        keyA = pkA + qkA
    lhu  t5, 8(t1)
    add  t4, t4, t5
    srli t5, t4, 1                //        nibble(TABA, keyA)
    add  t5, t5, s5
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_loop
    lhu  t4, 8(t0)                //        keyB = pkB + qkB
    lhu  t5, 10(t1)
    add  t4, t4, t5
    srli t5, t4, 1                //        nibble(TABB, keyB)
    add  t5, t5, s6
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_loop
    sb   a5, 10(s0)               //        f->move = move
    or   t0, a1, a2
    beqz t0, sv_found             //        solved: npo == 0 and noo == 0
    addi s0, s0, 12               //        ++f, --budget: descend
    addi s1, s1, -1
    sh   a1, 0(s0)
    sh   a2, 2(s0)
    sb   zero, 8(s0)
    sb   a6, 9(s0)
    j    sv_loop

sv_skip:                          // f->next = move_end[move]
    lbu  t0, 18(t2)
    sb   t0, 8(s0)
    j    sv_loop

sv_pop:                           // all nine moves tried at this level
    beq  s0, s7, sv_next          // at the root: next bound
    addi s0, s0, -12
    addi s1, s1, 1
    j    sv_loop

sv_next:
    addi s2, s2, 1
    li   t0, 12
    bltu s2, t0, sv_bound
    li   a0, -1                   // bound 11 exhausted: cannot happen for a valid state
    ret

// ---- PART 3: output ------------------------------------------------------------------
sv_found:                         // path[i] = frame i's move, for frames root..f; a0 = their number
    la   t1, path
    mv   t2, s7
    li   a0, 0
sv_copy:
    lbu  t3, 10(t2)
    sb   t3, 0(t1)
    addi t1, t1, 1
    addi a0, a0, 1
    addi t2, t2, 12
    bgeu s0, t2, sv_copy
    ret
