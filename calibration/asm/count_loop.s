# Pure register loop: retires 2 instructions per pass (addi + bnez) plus 3 fixed.
# @N@ is replaced by the scripts.
.text
    li   t0, @N@
loop:
    addi t0, t0, -1
    bnez t0, loop
    li   a7, 10
    ecall
