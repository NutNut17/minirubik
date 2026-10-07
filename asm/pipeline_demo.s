# pipeline_demo.s - a tiny program for the pipeline screenshots (Ripes, processor RV32_5S). Not part of the solver.
# It runs, once, the five instructions of the report (section 8): the child generation of the search and its first
# pruning check, on a table of two 10-byte records, so each stage of the pipeline shows one clear instruction.
#   exit code 0: the check fell through (budget 4 >= hp 2)      exit code 1: the branch was taken (try  li s1, 1 )
# Comments use # ; to run it without the GUI:  Ripes --mode cli --src pipeline_demo.s -t asm --proc RV32_5S --iret --cycles
    .data
T:  .half 10, 0, 0               # record 0: next[R] = 10 (byte offset of record 1), next[B], next[D]
    .byte 5, 0, 0, 0             #           hp = 5 at +6
    .half 0, 0, 0                # record 1
    .byte 2, 0, 0, 0             #           hp = 2 at +6

    .text
    .globl main
main:
    la   a0, T                   # parent record
    li   a6, 0                   # f2 = 0 (face R)
    la   s3, T                   # table base
    li   s1, 4                   # budget
    nop                          # four nops: the five instructions then enter an empty pipeline
    nop
    nop
    nop
# ---- the five instructions -------------------------------------------------------------
    add  t0, a0, a6              # 1: address of next[f2] in the parent's record
    lhu  t0, 0(t0)               # 2: load the 16-bit successor offset (10)
    add  a0, t0, s3              # 3: record address of the child; uses t0 right after the load: one stall cycle
    lbu  t4, 6(a0)               # 4: hp of the child (2); uses a0 right after the add: forwarded, no stall
    bltu s1, t4, drop            # 5: drop the child if hp > budget: here 4 < 2 is false, so it falls through
# ----------------------------------------------------------------------------------------
    li   a0, 0                   # check passed
    j    done
drop:
    li   a0, 1                   # check failed (branch taken)
done:
    nop
    nop
    nop
    nop
    li   a7, 93
    ecall
