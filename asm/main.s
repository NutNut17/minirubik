// main.s - test harness and LED renderer for the RV32I solver.
//
// This is preprocessed with the C preprocessor (see Makefile), because the Ripes assembler
// has no .if / .include. Comments written with // or /* */ are removed by the preprocessor.
//
//   RENDER   1: draw the cube on the LED matrix (Ripes GUI, matrix 35 wide x 25 tall)
//            0: no drawing at all (command-line build used for --iret measurements)
//   SELFTEST 1: headless self-check of the drawing (the Makefile defines the LED symbols)
//   USE_TABLES 1: append tables.s (PREC, OREC, TABA, TABB) for the real solver
//
// The program:  1. copies the state string into the display cube      (load_display)
//               2. calls  solve(a0 = address of the 14-character string)   <- YOUR code in solver.s
//                  which returns a0 = number of moves, and the moves in  path[]
//               3. replays every move on the display cube and redraws    (apply_move, draw_cube)
//               4. checks that the display cube is solved and the length is EXPECT_LEN
//   exit code: 0 pass, 1 cube not solved, 2 wrong length, 3 length > 11, 4 drawing differs (SELFTEST)

#ifndef RENDER
#define RENDER 1
#endif
#ifndef SELFTEST
#define SELFTEST 0
#endif
#ifndef USE_TABLES
#define USE_TABLES 0
#endif

    .equ EXPECT_LEN, 11          // optimal length of the test case in led_data.s
    .equ DELAY, 40000            // busy-wait loops between frames; raise it if the animation is too fast
    .equ LED_WORDS, 875          // 35 * 25 pixels, one 32-bit word each
    .equ LED_ROW_BYTES, 140      // one pixel row = 35 words * 4 bytes (matrix must be 35 wide)

    .text
    .globl main
main:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   s0, 24(sp)
    sw   s1, 20(sp)

    la   a0, STATE
    jal  ra, load_display        // display cube <- scrambled state
#if RENDER
    jal  ra, led_init            // clear the matrix, draw the fixed corner
    jal  ra, draw_cube
    jal  ra, delay
#endif
#if SELFTEST
    jal  ra, frame_check
#endif

    la   a0, STATE
    jal  ra, solve               // <- the solver under test
    mv   s0, a0                  // s0 = number of moves
    li   t0, 11
    bgtu s0, t0, fail_toolong    // path[] holds at most 11 moves

    li   s1, 0                   // s1 = move index
replay:
    beq  s1, s0, replay_done
    la   t0, path
    add  t0, t0, s1
    lbu  a0, 0(t0)
    jal  ra, apply_move          // update the display cube by one move
#if RENDER
    jal  ra, draw_cube
    jal  ra, delay
#endif
#if SELFTEST
    jal  ra, frame_check
#endif
    addi s1, s1, 1
    j    replay
replay_done:

    jal  ra, display_solved
    beqz a0, fail_state
    li   t0, EXPECT_LEN
    bne  s0, t0, fail_length
#if SELFTEST
    la   t0, BADFRAMES
    lw   t0, 0(t0)
    bnez t0, fail_frames
#endif
    li   a0, 0
    j    finish
fail_state:
    li   a0, 1
    j    finish
fail_length:
    li   a0, 2
    j    finish
fail_toolong:
    li   a0, 3
    j    finish
#if SELFTEST
fail_frames:
    li   a0, 4
#endif
finish:
    lw   ra, 28(sp)
    lw   s0, 24(sp)
    lw   s1, 20(sp)
    addi sp, sp, 32
    li   a7, 93                  // exit with a0 as the status
    ecall

// ---------------------------------------------------------------------------------------
// load_display(a0 = string): DP[i] = digit(i) - '1', DO[i] = digit(7 + i) - '1'
load_display:
    la   t0, DP
    la   t1, DO
    li   t2, 0
    li   t3, 7
ld_loop:
    add  t4, a0, t2
    lbu  t5, 0(t4)
    addi t5, t5, -49             // '1' = 49
    add  t6, t0, t2
    sb   t5, 0(t6)
    lbu  t5, 7(t4)
    addi t5, t5, -49
    add  t6, t1, t2
    sb   t5, 0(t6)
    addi t2, t2, 1
    bne  t2, t3, ld_loop
    ret

// apply_move(a0 = move): move = face * 3 + turns - 1, performed as `turns` quarter turns
apply_move:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s0, 8(sp)
    sw   s1, 4(sp)
    la   t0, MOVEF
    add  t0, t0, a0
    lbu  s0, 0(t0)               // s0 = face
    la   t0, MOVET
    add  t0, t0, a0
    lbu  s1, 0(t0)               // s1 = quarter turns left
am_loop:
    mv   a0, s0
    jal  ra, quarter_turn
    addi s1, s1, -1
    bnez s1, am_loop
    lw   ra, 12(sp)
    lw   s0, 8(sp)
    lw   s1, 4(sp)
    addi sp, sp, 16
    ret

// quarter_turn(a0 = face): p'[i] = p[SRC[face][i]],  o'[i] = (o[SRC[face][i]] + TW[face][i]) mod 3
quarter_turn:
    slli t0, a0, 3
    sub  t0, t0, a0              // face * 7 (no multiply instruction in RV32I)
    la   t1, SRC
    add  t1, t1, t0              // t1 -> SRC[face][0]
    la   t2, TW
    add  t2, t2, t0              // t2 -> TW[face][0]
    la   a1, DP
    la   a2, DO
    la   a3, TP
    la   a4, TO
    li   t3, 0                   // i
    li   t4, 7
qt_loop:
    add  t5, t1, t3
    lbu  t5, 0(t5)               // j = SRC[face][i]
    add  t6, a1, t5
    lbu  t6, 0(t6)               // p[j]
    add  a5, a3, t3
    sb   t6, 0(a5)               // TP[i]
    add  t6, a2, t5
    lbu  t6, 0(t6)               // o[j]
    add  a5, t2, t3
    lbu  a5, 0(a5)               // TW[face][i]
    add  t6, t6, a5              // 0..4
    li   a5, 3
    blt  t6, a5, qt_keep
    addi t6, t6, -3              // mod 3: one conditional subtract is exact for sums <= 4
qt_keep:
    add  a5, a4, t3
    sb   t6, 0(a5)               // TO[i]
    addi t3, t3, 1
    bne  t3, t4, qt_loop
    li   t3, 0                   // copy TP, TO back into DP, DO
qt_copy:
    add  t5, a3, t3
    lbu  t6, 0(t5)
    add  t5, a1, t3
    sb   t6, 0(t5)
    add  t5, a4, t3
    lbu  t6, 0(t5)
    add  t5, a2, t3
    sb   t6, 0(t5)
    addi t3, t3, 1
    bne  t3, t4, qt_copy
    ret

// display_solved() -> a0 = 1 if DP[i] == i and DO[i] == 0 for all i, else 0
display_solved:
    la   t0, DP
    la   t1, DO
    li   t2, 0
    li   t3, 7
ds_loop:
    add  t4, t0, t2
    lbu  t4, 0(t4)
    bne  t4, t2, ds_no
    add  t4, t1, t2
    lbu  t4, 0(t4)
    bnez t4, ds_no
    addi t2, t2, 1
    bne  t2, t3, ds_loop
    li   a0, 1
    ret
ds_no:
    li   a0, 0
    ret

#if RENDER
// ---------------------------------------------------------------------------------------
// LED matrix: row-major, pixel (x, y) is the word at  LED_MATRIX_0_BASE + (y * 35 + x) * 4.
// The offsets of all facelets were computed on the host (PIX), so there is no multiply here.

// led_init(): clear all 875 pixels, then draw the three stickers of the fixed corner
led_init:
    addi sp, sp, -16
    sw   ra, 12(sp)
    li   t0, LED_MATRIX_0_BASE
    li   t1, LED_WORDS
li_clear:
    sw   zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, li_clear
    la   t0, FIXED
    sw   t0, 8(sp)               // keep the table pointer across the calls
    li   t1, 3
    sw   t1, 4(sp)
li_fixed:
    lw   t0, 8(sp)
    lhu  a0, 0(t0)               // block offset
    lhu  t2, 2(t0)               // colour index
    addi t0, t0, 4
    sw   t0, 8(sp)
    la   t3, PALETTE
    slli t2, t2, 2
    add  t3, t3, t2
    lw   a1, 0(t3)               // colour word
    jal  ra, fill_block
    lw   t1, 4(sp)
    addi t1, t1, -1
    sw   t1, 4(sp)
    bnez t1, li_fixed
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

// draw_cube(): draw the 7 moving corners (3 stickers each) from DP / DO
draw_cube:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   s0, 24(sp)
    sw   s1, 20(sp)
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    li   s0, 0                   // s0 = position index 0..6
dc_pos:
    la   t0, DP
    add  t0, t0, s0
    lbu  t1, 0(t0)               // cubie
    la   t0, DO
    add  t0, t0, s0
    lbu  t2, 0(t0)               // twist
    slli t3, t1, 1
    add  t3, t3, t1              // cubie * 3
    add  t3, t3, t2              // + twist
    slli t4, t3, 1
    add  s2, t4, t3              // s2 = (cubie * 3 + twist) * 3, the COLOR row
    slli t4, s0, 1
    add  t4, t4, s0              // s3 base = position * 3, the PIX row
    mv   s3, t4
    li   s1, 0                   // s1 = slot 0..2
dc_slot:
    la   t0, COLOR
    add  t0, t0, s2
    add  t0, t0, s1
    lbu  t0, 0(t0)               // colour index
    slli t0, t0, 2
    la   t1, PALETTE
    add  t1, t1, t0
    lw   a1, 0(t1)               // colour word
    add  t0, s3, s1              // position * 3 + slot
    slli t0, t0, 1
    la   t1, PIX
    add  t1, t1, t0
    lhu  a0, 0(t1)               // block offset
    jal  ra, fill_block
    addi s1, s1, 1
    li   t0, 3
    bne  s1, t0, dc_slot
    addi s0, s0, 1
    li   t0, 7
    bne  s0, t0, dc_pos
    lw   ra, 28(sp)
    lw   s0, 24(sp)
    lw   s1, 20(sp)
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    addi sp, sp, 32
    ret

// fill_block(a0 = byte offset of the top-left pixel, a1 = colour word): a 4 x 3 pixel block
fill_block:
    li   t0, LED_MATRIX_0_BASE
    add  t0, t0, a0
    sw   a1, 0(t0)
    sw   a1, 4(t0)
    sw   a1, 8(t0)
    sw   a1, 12(t0)
    addi t0, t0, LED_ROW_BYTES
    sw   a1, 0(t0)
    sw   a1, 4(t0)
    sw   a1, 8(t0)
    sw   a1, 12(t0)
    addi t0, t0, LED_ROW_BYTES
    sw   a1, 0(t0)
    sw   a1, 4(t0)
    sw   a1, 8(t0)
    sw   a1, 12(t0)
    ret

// delay(): busy wait so that every frame stays visible
delay:
    li   t0, DELAY
dl_loop:
    addi t0, t0, -1
    bnez t0, dl_loop
    ret
#endif

#if SELFTEST
// frame_check(): checksum of the whole matrix (s = rotl(s, 1) xor word, row-major), printed in hex
// and compared with EXPECT_SUMS[frame]; a difference is counted in BADFRAMES.
frame_check:
    li   t0, LED_MATRIX_0_BASE
    li   t1, LED_WORDS
    li   t2, 0
fc_loop:
    lw   t3, 0(t0)
    slli t4, t2, 1
    srli t5, t2, 31
    or   t2, t4, t5
    xor  t2, t2, t3
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, fc_loop
    la   t0, FRAME
    lw   t1, 0(t0)               // frame number
    slli t3, t1, 2
    la   t4, EXPECT_SUMS
    add  t4, t4, t3
    lw   t4, 0(t4)
    beq  t4, t2, fc_ok
    la   t5, BADFRAMES
    lw   t6, 0(t5)
    addi t6, t6, 1
    sw   t6, 0(t5)
fc_ok:
    addi t1, t1, 1
    sw   t1, 0(t0)
    mv   a0, t2
    li   a7, 34                  // print a0 in hex
    ecall
    li   a0, 10
    li   a7, 11                  // print a newline
    ecall
    ret
#endif

    .data
DP:  .byte 0,0,0,0,0,0,0,0       // display cube: cubie at each position
DO:  .byte 0,0,0,0,0,0,0,0       // display cube: twist at each position
TP:  .byte 0,0,0,0,0,0,0,0       // scratch for quarter_turn
TO:  .byte 0,0,0,0,0,0,0,0
path: .zero 12                   // moves written by solve(): face * 3 + turns - 1
    .align 2
FRAME: .word 0
BADFRAMES: .word 0

#include "led_data.s"
#include "solver.s"
#if USE_TABLES
#include "tables.s"
#endif
