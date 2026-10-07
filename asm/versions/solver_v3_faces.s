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
// REGISTERS during the search (the state of the CURRENT level lives in registers; a frame holds the levels above)
//   s0 f       frame pointer (20-byte frames: +0 lp, +4 lo, +8 cp, +12 co (words), +16 next, +17 last, +18 f2, +19 turn)
//   s1 budget  = bound - depth - 1          s2 bound = iterative-deepening limit
//   s3 PREC    s4 OREC    s5 TABA    s6 TABB    s7 FRAMES (root frame)    t6 = 6
//   s9 lp      s10 lo     this level's state, as ADDRESSES of its PREC / OREC records
//   a0 cpo     a3 coo     the last child generated at this level (addresses of its records)
//   a4 next    a7 last    next face to try (f2 = 0, 2, 4; 6 = done) and the face of the move that led here
//   a6 f2                 the face being tried: 0 R, 2 B, 4 D (a byte offset into a record's next[])
// The three turns of a face (R, R2, R') are three copies of the same code, so no table is read per move.
// =====================================================================================
    .data
    .align 2
FRAMES: .zero 240                 // 12 frames x 20 bytes

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
    add  s9, s9, s3               // lp = &PREC record of the start state
    add  s10, s10, s4             // lo = &OREC record
    mv   s0, s7                   // root frame
    li   s2, 1                    // bound = 1, 2, ... 11 (the start is not solved)
    li   s1, 0                    // budget = bound - 1
    li   a4, 0                    // next face = R
    li   a7, 6                    // last = 6 (no face)
    li   t6, 6                    // constant

sv_face:                          // C: the move loop, one face (three moves) at a time
    beq  a4, t6, sv_pop           //    all three faces tried at this level: back up
    mv   a6, a4                   //    f2 = this face
    addi a4, a4, 2                //    next face for later
    beq  a6, a7, sv_face          //    same face as the move that led here: skip all three of its moves
    mv   a0, s9                   // turn 1 (R, B or D): from this level's state
    mv   a3, s10
    add  t0, a0, a6               // child po = half[record + f2];  its record = PREC + po
    lhu  t0, 0(t0)
    add  a0, t0, s3
    add  t1, a3, a6
    lhu  t1, 0(t1)
    add  a3, t1, s4
    // within(child, budget): h <= budget, cheapest bound first
    lbu  t4, 6(a0)                // hp
    bltu s1, t4, sv_t2              // hp > budget: drop this child
    lbu  t5, 6(a3)                // ho
    bltu s1, t5, sv_t2
    lbu  t4, 7(a0)                // keyA = pkA + qkA
    lhu  t5, 8(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABA, keyA)
    add  t5, t5, s5
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_t2
    lhu  t4, 8(a0)                // keyB = pkB + qkB
    lhu  t5, 10(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABB, keyB)
    add  t5, t5, s6
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_t2
    // The child passed h <= budget. With budget == 0 that means h == 0: the solved state.
    // With budget > 0 it cannot be solved (a shorter solution would have been found with a smaller bound).
    beqz s1, sv_found1
    sw   s9, 0(s0)                // descend: save this level (lp, lo, cp, co, next, last, f2, turn) ...
    sw   s10, 4(s0)
    sw   a0, 8(s0)
    sw   a3, 12(s0)
    sb   a4, 16(s0)
    sb   a7, 17(s0)
    sb   a6, 18(s0)
    li   t0, 1
    sb   t0, 19(s0)
    addi s0, s0, 20               // ... one frame down, one less budget; the child becomes the current level
    addi s1, s1, -1
    mv   s9, a0
    mv   s10, a3
    li   a4, 0
    mv   a7, a6
    j    sv_face
sv_t2:                           // turn 2 (R2, B2, D2): one more turn on the last child (a0, a3)
    add  t0, a0, a6               // child po = half[record + f2];  its record = PREC + po
    lhu  t0, 0(t0)
    add  a0, t0, s3
    add  t1, a3, a6
    lhu  t1, 0(t1)
    add  a3, t1, s4
    // within(child, budget): h <= budget, cheapest bound first
    lbu  t4, 6(a0)                // hp
    bltu s1, t4, sv_t3              // hp > budget: drop this child
    lbu  t5, 6(a3)                // ho
    bltu s1, t5, sv_t3
    lbu  t4, 7(a0)                // keyA = pkA + qkA
    lhu  t5, 8(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABA, keyA)
    add  t5, t5, s5
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_t3
    lhu  t4, 8(a0)                // keyB = pkB + qkB
    lhu  t5, 10(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABB, keyB)
    add  t5, t5, s6
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_t3
    beqz s1, sv_found2
    sw   s9, 0(s0)                // descend: save this level (lp, lo, cp, co, next, last, f2, turn) ...
    sw   s10, 4(s0)
    sw   a0, 8(s0)
    sw   a3, 12(s0)
    sb   a4, 16(s0)
    sb   a7, 17(s0)
    sb   a6, 18(s0)
    li   t0, 2
    sb   t0, 19(s0)
    addi s0, s0, 20               // ... one frame down, one less budget; the child becomes the current level
    addi s1, s1, -1
    mv   s9, a0
    mv   s10, a3
    li   a4, 0
    mv   a7, a6
    j    sv_face
sv_t3:                           // turn 3 (R', B', D'): one more turn again
    add  t0, a0, a6               // child po = half[record + f2];  its record = PREC + po
    lhu  t0, 0(t0)
    add  a0, t0, s3
    add  t1, a3, a6
    lhu  t1, 0(t1)
    add  a3, t1, s4
    // within(child, budget): h <= budget, cheapest bound first
    lbu  t4, 6(a0)                // hp
    bltu s1, t4, sv_face              // hp > budget: drop this child
    lbu  t5, 6(a3)                // ho
    bltu s1, t5, sv_face
    lbu  t4, 7(a0)                // keyA = pkA + qkA
    lhu  t5, 8(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABA, keyA)
    add  t5, t5, s5
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_face
    lhu  t4, 8(a0)                // keyB = pkB + qkB
    lhu  t5, 10(a3)
    add  t4, t4, t5
    srli t5, t4, 1                // nibble(TABB, keyB)
    add  t5, t5, s6
    lbu  t5, 0(t5)
    andi t4, t4, 1
    slli t4, t4, 2
    srl  t5, t5, t4
    andi t5, t5, 15
    bltu s1, t5, sv_face
    beqz s1, sv_found3
    sw   s9, 0(s0)                // descend: save this level (lp, lo, cp, co, next, last, f2, turn) ...
    sw   s10, 4(s0)
    sw   a0, 8(s0)
    sw   a3, 12(s0)
    sb   a4, 16(s0)
    sb   a7, 17(s0)
    sb   a6, 18(s0)
    li   t0, 3
    sb   t0, 19(s0)
    addi s0, s0, 20               // ... one frame down, one less budget; the child becomes the current level
    addi s1, s1, -1
    mv   s9, a0
    mv   s10, a3
    li   a4, 0
    mv   a7, a6
    j    sv_face

sv_pop:                           // back up one level
    beq  s0, s7, sv_next          // at the root: next bound
    addi s0, s0, -20
    addi s1, s1, 1
    lw   s9, 0(s0)                // reload the level above
    lw   s10, 4(s0)
    lw   a0, 8(s0)
    lw   a3, 12(s0)
    lbu  a4, 16(s0)
    lbu  a7, 17(s0)
    lbu  a6, 18(s0)
    lbu  t0, 19(s0)               // continue after the turn we descended through
    addi t0, t0, -1
    beqz t0, sv_t2
    addi t0, t0, -1
    beqz t0, sv_t3
    j    sv_face

sv_next:                          // the root is current again (lp, lo, last restored)
    addi s2, s2, 1
    li   t0, 12
    bgeu s2, t0, sv_fail
    addi s1, s2, -1
    li   a4, 0
    j    sv_face
sv_fail:
    li   a0, -1                   // bound 11 exhausted: cannot happen for a valid state
    ret

// ---- PART 3: output ------------------------------------------------------------------
sv_found1:
    li   t0, 1
    j    sv_found
sv_found2:
    li   t0, 2
    j    sv_found
sv_found3:
    li   t0, 3
sv_found:                         // this level's move: face a6, turn t0; the frames above hold theirs
    sb   a6, 18(s0)
    sb   t0, 19(s0)
    la   t1, path
    mv   t2, s7
    li   a0, 0
sv_copy:                          // move = 3 * face + turns - 1 = f2 + f2/2 + turn - 1
    lbu  t3, 18(t2)
    lbu  t4, 19(t2)
    srli t5, t3, 1
    add  t3, t3, t5
    add  t3, t3, t4
    addi t3, t3, -1
    sb   t3, 0(t1)
    addi t1, t1, 1
    addi a0, a0, 1
    addi t2, t2, 20
    bgeu s0, t2, sv_copy
    ret
