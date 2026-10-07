// solver_dummy.s - the placeholder used while the LED template was built: ignores the input and returns the
// known 11-move answer of the default test case (led_data.s). Use it with:  make selftest SOLVER=versions/solver_dummy.s FULL=1
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
