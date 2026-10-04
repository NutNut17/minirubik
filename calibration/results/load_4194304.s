# Control: READS 4194304 never-written guest addresses.
# Tests whether a read alone allocates host memory (readMem uses operator[]).
.text
    li   t0, 4194304
    lui  a1, 0x20000
loop:
    lbu  t1, 0(a1)
    addi a1, a1, 1
    addi t0, t0, -1
    bnez t0, loop
    li   a7, 10
    ecall
