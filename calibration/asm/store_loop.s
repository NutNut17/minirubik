# Writes one byte to each of @N@ consecutive guest addresses.
# 0x20000000 is above .text (0x0) and .data (0x10000000) and far below the stack.
# The stored value is non-zero so nothing can be optimised away as "zero".
.text
    li   t0, @N@
    lui  a1, 0x20000
    li   t1, 0x5a
loop:
    sb   t1, 0(a1)
    addi a1, a1, 1
    addi t0, t0, -1
    bnez t0, loop
    li   a7, 10
    ecall
