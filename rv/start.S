    .section .text.init
    .globl _start
_start:
    lui   sp, 0x7ffff        # Ripes does not initialise sp for ELF input
    addi  sp, sp, -16
    jal   ra, main
    li    a7, 93             # exit, status in a0
    ecall
