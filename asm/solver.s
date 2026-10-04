// solver.s - PLACEHOLDER. Replace the body of solve with your solver.
//
// Contract (what main.s expects):
//   input   a0 = address of the 14-character state string (digits '1'..'7' then '1'..'3')
//   output  a0 = number of moves; the moves are stored in path[0 .. a0-1] (bytes, face * 3 + turns - 1)
//   free    t0-t6, a1-a7 (you may not keep anything in s-registers without saving them)
//
// This dummy ignores the input and returns the known 11-move solution of the test case in led_data.s.
    .text
    .globl solve
solve:
    la   t0, DUMMYPATH
    la   t1, path
    li   t2, 11
sv_copy:
    lbu  t3, 0(t0)
    sb   t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, sv_copy
    li   a0, 11
    ret
