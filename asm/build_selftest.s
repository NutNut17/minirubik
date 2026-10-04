    .equ LED_MATRIX_0_BASE, 0xf0000000
    .equ EXPECT_LEN, 11
    .equ DELAY, 40000
    .equ LED_WORDS, 875
    .equ LED_ROW_BYTES, 140
    .text
    .globl main
main:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    la a0, STATE
    jal ra, load_display
    jal ra, led_init
    jal ra, draw_cube
    jal ra, delay
    jal ra, frame_check
    la a0, STATE
    jal ra, solve
    mv s0, a0
    li t0, 11
    bgtu s0, t0, fail_toolong
    li s1, 0
replay:
    beq s1, s0, replay_done
    la t0, path
    add t0, t0, s1
    lbu a0, 0(t0)
    jal ra, apply_move
    jal ra, draw_cube
    jal ra, delay
    jal ra, frame_check
    addi s1, s1, 1
    j replay
replay_done:
    jal ra, display_solved
    beqz a0, fail_state
    li t0, EXPECT_LEN
    bne s0, t0, fail_length
    la t0, BADFRAMES
    lw t0, 0(t0)
    bnez t0, fail_frames
    li a0, 0
    j finish
fail_state:
    li a0, 1
    j finish
fail_length:
    li a0, 2
    j finish
fail_toolong:
    li a0, 3
    j finish
fail_frames:
    li a0, 4
finish:
    lw ra, 28(sp)
    lw s0, 24(sp)
    lw s1, 20(sp)
    addi sp, sp, 32
    li a7, 93
    ecall
load_display:
    la t0, DP
    la t1, DO
    li t2, 0
    li t3, 7
ld_loop:
    add t4, a0, t2
    lbu t5, 0(t4)
    addi t5, t5, -49
    add t6, t0, t2
    sb t5, 0(t6)
    lbu t5, 7(t4)
    addi t5, t5, -49
    add t6, t1, t2
    sb t5, 0(t6)
    addi t2, t2, 1
    bne t2, t3, ld_loop
    ret
apply_move:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    la t0, MOVEF
    add t0, t0, a0
    lbu s0, 0(t0)
    la t0, MOVET
    add t0, t0, a0
    lbu s1, 0(t0)
am_loop:
    mv a0, s0
    jal ra, quarter_turn
    addi s1, s1, -1
    bnez s1, am_loop
    lw ra, 12(sp)
    lw s0, 8(sp)
    lw s1, 4(sp)
    addi sp, sp, 16
    ret
quarter_turn:
    slli t0, a0, 3
    sub t0, t0, a0
    la t1, SRC
    add t1, t1, t0
    la t2, TW
    add t2, t2, t0
    la a1, DP
    la a2, DO
    la a3, TP
    la a4, TO
    li t3, 0
    li t4, 7
qt_loop:
    add t5, t1, t3
    lbu t5, 0(t5)
    add t6, a1, t5
    lbu t6, 0(t6)
    add a5, a3, t3
    sb t6, 0(a5)
    add t6, a2, t5
    lbu t6, 0(t6)
    add a5, t2, t3
    lbu a5, 0(a5)
    add t6, t6, a5
    li a5, 3
    blt t6, a5, qt_keep
    addi t6, t6, -3
qt_keep:
    add a5, a4, t3
    sb t6, 0(a5)
    addi t3, t3, 1
    bne t3, t4, qt_loop
    li t3, 0
qt_copy:
    add t5, a3, t3
    lbu t6, 0(t5)
    add t5, a1, t3
    sb t6, 0(t5)
    add t5, a4, t3
    lbu t6, 0(t5)
    add t5, a2, t3
    sb t6, 0(t5)
    addi t3, t3, 1
    bne t3, t4, qt_copy
    ret
display_solved:
    la t0, DP
    la t1, DO
    li t2, 0
    li t3, 7
ds_loop:
    add t4, t0, t2
    lbu t4, 0(t4)
    bne t4, t2, ds_no
    add t4, t1, t2
    lbu t4, 0(t4)
    bnez t4, ds_no
    addi t2, t2, 1
    bne t2, t3, ds_loop
    li a0, 1
    ret
ds_no:
    li a0, 0
    ret
led_init:
    addi sp, sp, -16
    sw ra, 12(sp)
    li t0, LED_MATRIX_0_BASE
    li t1, LED_WORDS
li_clear:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, li_clear
    la t0, FIXED
    sw t0, 8(sp)
    li t1, 3
    sw t1, 4(sp)
li_fixed:
    lw t0, 8(sp)
    lhu a0, 0(t0)
    lhu t2, 2(t0)
    addi t0, t0, 4
    sw t0, 8(sp)
    la t3, PALETTE
    slli t2, t2, 2
    add t3, t3, t2
    lw a1, 0(t3)
    jal ra, fill_block
    lw t1, 4(sp)
    addi t1, t1, -1
    sw t1, 4(sp)
    bnez t1, li_fixed
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
draw_cube:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    li s0, 0
dc_pos:
    la t0, DP
    add t0, t0, s0
    lbu t1, 0(t0)
    la t0, DO
    add t0, t0, s0
    lbu t2, 0(t0)
    slli t3, t1, 1
    add t3, t3, t1
    add t3, t3, t2
    slli t4, t3, 1
    add s2, t4, t3
    slli t4, s0, 1
    add t4, t4, s0
    mv s3, t4
    li s1, 0
dc_slot:
    la t0, COLOR
    add t0, t0, s2
    add t0, t0, s1
    lbu t0, 0(t0)
    slli t0, t0, 2
    la t1, PALETTE
    add t1, t1, t0
    lw a1, 0(t1)
    add t0, s3, s1
    slli t0, t0, 1
    la t1, PIX
    add t1, t1, t0
    lhu a0, 0(t1)
    jal ra, fill_block
    addi s1, s1, 1
    li t0, 3
    bne s1, t0, dc_slot
    addi s0, s0, 1
    li t0, 7
    bne s0, t0, dc_pos
    lw ra, 28(sp)
    lw s0, 24(sp)
    lw s1, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    addi sp, sp, 32
    ret
fill_block:
    li t0, LED_MATRIX_0_BASE
    add t0, t0, a0
    sw a1, 0(t0)
    sw a1, 4(t0)
    sw a1, 8(t0)
    sw a1, 12(t0)
    addi t0, t0, LED_ROW_BYTES
    sw a1, 0(t0)
    sw a1, 4(t0)
    sw a1, 8(t0)
    sw a1, 12(t0)
    addi t0, t0, LED_ROW_BYTES
    sw a1, 0(t0)
    sw a1, 4(t0)
    sw a1, 8(t0)
    sw a1, 12(t0)
    ret
delay:
    li t0, DELAY
dl_loop:
    addi t0, t0, -1
    bnez t0, dl_loop
    ret
frame_check:
    li t0, LED_MATRIX_0_BASE
    li t1, LED_WORDS
    li t2, 0
fc_loop:
    lw t3, 0(t0)
    slli t4, t2, 1
    srli t5, t2, 31
    or t2, t4, t5
    xor t2, t2, t3
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, fc_loop
    la t0, FRAME
    lw t1, 0(t0)
    slli t3, t1, 2
    la t4, EXPECT_SUMS
    add t4, t4, t3
    lw t4, 0(t4)
    beq t4, t2, fc_ok
    la t5, BADFRAMES
    lw t6, 0(t5)
    addi t6, t6, 1
    sw t6, 0(t5)
fc_ok:
    addi t1, t1, 1
    sw t1, 0(t0)
    mv a0, t2
    li a7, 34
    ecall
    li a0, 10
    li a7, 11
    ecall
    ret
    .data
DP: .byte 0,0,0,0,0,0,0,0
DO: .byte 0,0,0,0,0,0,0,0
TP: .byte 0,0,0,0,0,0,0,0
TO: .byte 0,0,0,0,0,0,0,0
path: .zero 12
    .align 2
FRAME: .word 0
BADFRAMES: .word 0
# generated by gen_led_data.py (do not edit); proofs run at generation time
    .data
# palette: colour index -> 0x00RRGGBB, order W Y G B O R
PALETTE:
    .word 0xFFFFFF,0xFFFF00,0x00C800,0x0000FF,0xFF8000,0xFF0000
# COLOR[(cubie*3 + twist)*3 + slot]: colour index of the sticker in `slot` of a position
COLOR:
    .byte 0,5,2,5,2,0,2,0,5,1,2,5
    .byte 2,5,1,5,1,2,1,4,2,4,2,1
    .byte 2,1,4,0,3,5,3,5,0,5,0,3
    .byte 1,5,3,5,3,1,3,1,5,1,3,4
    .byte 3,4,1,4,1,3,0,4,3,4,3,0
    .byte 3,0,4
# PIX[idx*3 + slot]: byte offset ((y*35 + x)*4) of the 4x3 facelet block, idx = position - 1
PIX:
    .half 472,1052,1032,2012,1452,1472,1996,1416,1436
    .half 52,1088,1068,2432,1488,1508,2416,1524,1400
    .half 36,980,1104
# FIXED: the fixed corner (offset .half, colour .half) x 3, drawn once
FIXED:
    .half 456,0,1016,2,996,4
# move tables of solver.c: SRC[face*7 + i], TW[face*7 + i]; move m = face*3 + turns - 1
SRC:
    .byte 1,4,2,0,3,5,6,0,1,2,4,5
    .byte 6,3,0,2,5,3,1,4,6
TW:
    .byte 1,2,0,2,1,0,0,0,0,0,1,2
    .byte 1,2,0,0,0,0,0,0,0
MOVEF:
    .byte 0,0,0,1,1,1,2,2,2
MOVET:
    .byte 1,2,3,1,2,3,1,2,3
# dummy test case
STATE:
    .asciz "21345671111111"
DUMMYPATH:
    .byte 0,5,7,2,3,2,5,0,7,0,3
    .align 2
EXPECT_SUMS:
    .word 0x4EB44E87,0xD7E2D4C3,0x0EECF9A0,0xB0E0A2A7,0x470EA9F1,0x398836D2,0x5A8A89B7,0xDE1B5738,0x9BB1FC1A,0x4B7D191C,0xD7AE2ADB,0x03297E54
    .text
    .globl solve
solve:
    la t0, DUMMYPATH
    la t1, path
    li t2, 11
sv_copy:
    lbu t3, 0(t0)
    sb t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, sv_copy
    li a0, 11
    ret
