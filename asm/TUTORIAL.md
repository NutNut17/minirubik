# Tutorial: from the dummy test to your own solver on Ripes

You get a program that already runs, draws the cube on the LED matrix and checks its own result. It uses a **dummy solver** that
returns the known answer to one test case. You replace the dummy with your solver, and everything else keeps working.

> **Before you use this: course rules.** hw2.md (AI regime) says the RV32I assembly, the search design and the analysis must be your
> own work, and that AI assistance must be disclosed (Section 4.1). The LED template (`main.s`, `gen_led_data.py`) was drafted with AI
> assistance; `solver.s` is a three-line placeholder. Ask your instructor or TA whether using an AI-drafted LED template is allowed,
> disclose it in your note either way, and make sure you can explain every line (the interview asks how the LED mapping is derived,
> and section 8 below is written for that). **Your solver must be your own.**

## 0. What is in this folder

| File | What it is | Who writes it |
| :--- | :--- | :--- |
| `main.s` | harness: loads the state, calls `solve`, replays the moves on a small cube model, redraws, validates, exits | template |
| `solver.s` | **your solver goes here**; now a dummy that returns the 11-move answer | you |
| `led_data.s` | generated tables: colours, facelet positions, move tables, the dummy test case | generated |
| `gen_led_data.py` | generates `led_data.s` and proves it (see section 8) | generated |
| `expected_frames.txt` | what the matrix should show after every move, as text, with a checksum per frame | generated |
| `tables.s` | your solver's lookup tables (`PREC`, `OREC`, `TABA`, `TABB`), only when `USE_TABLES=1` | generated |
| `Makefile` | builds the files below | template |
| `build_cli.s`, `build_gui.s`, `build_selftest.s` | the three flat programs you give to Ripes | generated |
| `SPEC.md` | table layouts, test vectors, numbers to beat | reference |

## 1. What you need

- The Ripes you built: `../../Ripes/build/Ripes.app` (it must list `RV32_ISS`; check with `Ripes --help | grep ISS`).
- `riscv64-elf-gcc` (`brew install riscv64-elf-gcc`). It is used here only as a **C preprocessor**, see the box in section 2.
- `python3` (standard library only).

All commands below run in `minirubik/asm/`. If Ripes is somewhere else: `make run RIPES=/path/to/Ripes`.

## 2. Why a preprocessor

The Ripes assembler in this build only knows `.align .asciz .bss .byte .data .dword .equ .global .globl .half .long .short .string .text
.word .zero`. It has **no `.if`, `.include`, `.macro` or `.section`**, so hw2.md's example `.equ RENDER, 0` with `.if RENDER` cannot be
assembled. The Makefile runs the C preprocessor over `main.s` (`#if RENDER`, `#include "solver.s"`) and writes one flat file. State this
in your write-up: *the CLI and GUI builds are produced from one source tree and differ only in the renderer (113 lines).* Keep comments
in your own `.s` files as `//` or `/* */`; a line that starts with `#` followed by a word like `if` or `define` would be read by the
preprocessor.

## 3. Step 1: generate the data and check it

```sh
python3 gen_led_data.py
```
Expected output:
```
physical model == solver move tables (900 random turns), and 12 frames match the physical cube
wrote led_data.s and expected_frames.txt;  frame checksums: 4EB44E87 D7E2D4C3 0EECF9A0 ...
```
If an assertion fails, the generated data would draw the cube wrongly, so nothing is written until the checks pass.

## 4. Step 2: run the dummy in the command line (no drawing)

```sh
make run
```
Expected: `Program exited with code: 0` and **5031** retired instructions (this is the harness plus the dummy, about 5,000 instructions of
overhead for parsing, replaying 11 moves and validating; subtract it when you compare a solver with the C reference). Try the other model:
`make run PROC=RV32_5S`.

Exit codes:

| Code | Meaning |
| ---: | :--- |
| 0 | the replayed cube is solved and the length is correct |
| 1 | the cube is **not** solved after your path (wrong or incomplete moves) |
| 2 | solved, but the length is not `EXPECT_LEN` (not optimal) |
| 3 | `solve` returned more than 11 moves |
| 4 | (selftest only) the drawing differs from the expected frame |

## 5. Step 3: check the drawing without the GUI

```sh
make selftest
```
This builds the drawing version and defines a fake LED base address, so the matrix is ordinary memory. After every frame the program
adds up all 875 pixels (`s = rotl(s,1) xor pixel`), prints the sum in hex and compares it with the sum in `expected_frames.txt`. Expected:
twelve lines `0x4eb44e87 0xd7e2d4c3 0xeecf9a0 ...` (Ripes prints hex without leading zeros), `Program exited with code: 0`. This proves the
assembly draws exactly the pictures the generator proved correct. It does not prove that the real LED peripheral shows them; the next
step does.

## 6. Step 4: see it in the Ripes GUI

```sh
make gui          # writes build_gui.s
```
1. Open the Ripes app.
2. **I/O tab:** add an **LED Matrix**. Set **Width 35** and **Height 25** (the panel lists Height above Width, check which box you type in).
   The program uses the symbol `LED_MATRIX_0_BASE` that Ripes defines for the first matrix.
3. **Processor tab:** choose a processor. `RV32_ISS` is fastest; a pipeline model lets you watch IF/ID/EX/MEM/WB but runs about 100 times slower.
4. **Editor tab:** open `build_gui.s` (File, load source file) and assemble it. If the assembler complains about `LED_MATRIX_0_BASE`, the
   matrix has not been added yet.
5. Run (the play button). Expected: the first frame is the scrambled cube, then 11 redraws, one per move, ending on the solved cube:

```
.........WWWWWWWW..................
.........WWWWWWWW..................
.........WWWWYYYY..................
.........WWWWYYYY..................
.........WWWWYYYY..................
...................................
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
OOOOOOOO.GGGGRRRR.GGGGRRRR.BBBBBBBB
...................................
.........YYYYWWWW..................
.........YYYYWWWW..................
.........YYYYWWWW..................
.........YYYYYYYY..................
.........YYYYYYYY..................
.........YYYYYYYY..................
```
(Letters stand for colours: W white = Up, Y yellow = Down, G green = Front, B blue = Back, O orange = Left, R red = Right. Rows 21 to 25 stay
dark. This is frame 0; `expected_frames.txt` has all 12.)

If the animation is too fast or too slow, change `DELAY` at the top of `main.s` (busy-wait loops between frames) and run `make gui` again.
I could not open the GUI while preparing this, so steps 1 to 5 above are what I expect from Ripes' documentation; section 9 lists what to
check if something differs.

## 7. Step 5: put your solver in

Edit `solver.s`. The contract:

| | |
| :--- | :--- |
| input | `a0` = address of the 14-character state string (`'1'..'7'` for the seven cubies, then `'1'..'3'` for the twists) |
| output | `a0` = number of moves (0 to 11); the moves go in `path[0 .. a0-1]`, one byte each: `face * 3 + turns - 1` |
| faces | R = 0, B = 1, D = 2, so R, R2, R' = 0, 1, 2 and B, B2, B' = 3, 4, 5 and D, D2, D' = 6, 7, 8 |
| registers | save any `s`-register you use; `ra` is restored for you only if you save it too |

Your solver must rank the string itself (Lehmer code and base-3, see `ida_core4.h` and `report.md`). If it needs the lookup tables, build with them:
```sh
make run USE_TABLES=1          # appends tables.s (PREC, OREC, TABA, TABB), see SPEC.md for the layout
make gui USE_TABLES=1
```
Work in small steps, one `make run` after each: first make `solve` return `a0 = 0` for the solved cube and check exit code 0, then add
the ranking and print `p` and `o` (`li a7, 1` prints an integer) and compare with the test vectors in `SPEC.md`, then the search.
To use another test case, put its string in `STATE` and its length in `EXPECT_LEN`; the drawing and the validation are independent of the
solver, so they keep working. `DUMMYPATH` and `EXPECT_SUMS` belong to the dummy case only; `make selftest` is meaningful only for it.

The harness cannot be fooled by a wrong solver: it replays your moves on its own cube model (`DP`, `DO`), so a wrong path ends with exit
code 1 even if your solver believes it succeeded.

## 8. How the picture is made (for the interview)

**Pixels.** The matrix is 35 wide and 25 tall, one 32-bit word (`0x00RRGGBB`) per pixel, row-major: pixel (x, y) is at
`LED_MATRIX_0_BASE + (y * 35 + x) * 4`. (Ripes' in-GUI text says column-major; it is wrong, as hw2.md notes.) A facelet is a 4 x 3 block;
a face is 2 x 2 facelets, 8 x 6 pixels; the six faces are arranged as the net of `report.md`: Up above Front, and Left, Front, Right, Back
in a row, Down below Front. With one pixel between faces that is 4 * 8 + 3 = 35 columns and 3 * 6 + 2 = 20 rows. No multiplication is
needed at run time: `gen_led_data.py` computes every block offset (`PIX`) in advance, and a block is filled with 12 `sw` instructions
(one row is `LED_ROW_BYTES` = 140 bytes).

**Colours.** The state is seven cubies on seven positions plus a fixed corner. Each corner has three stickers, numbered by `slot`: slot 0 is
the sticker on the Up or Down face, slots 1 and 2 follow clockwise seen from outside the cube. A cubie sitting at a position with twist `t`
shows its sticker `j` in slot `(j - t) mod 3` (this rule was found by comparing a 3D model of the cube with the solver's own `twist` table; it
agrees on 900 random turns). `COLOR[(cubie*3 + twist)*3 + slot]` stores the result, so drawing needs no modulo either.

**Moves.** The harness updates its cube model with the same rule as `solver.c`: `p'[i] = p[SRC[face][i]]`,
`o'[i] = (o[SRC[face][i]] + TW[face][i]) mod 3`, where the mod 3 is one conditional subtract because the sum is at most 4. A move is
1 to 3 quarter turns, but counts once.

**Why trust it.** Before writing `led_data.s`, `gen_led_data.py` (1) rotates a 3D model of the stickers and checks it against the
solver's move tables, then (2) compares, for each of the 12 frames of the dummy case, the picture made from the tables with the
picture of the 3D model. `make selftest` then proves the assembly reproduces the table pictures bit for bit.

Exercises that check your understanding: derive by hand the byte offset of the Front-face facelet of position 2 (FDR) from the net; change a
facelet to 5 x 4 pixels and say which tables change; explain why `COLOR` has 63 entries; explain why `qt_keep` needs only one subtract.

## 9. If something goes wrong

| Symptom | Likely cause |
| :--- | :--- |
| `Error during assembly ... Unknown directive/opcode` on `build_gui.s` in the CLI | the CLI has no LED peripheral; use `build_cli.s`, or the GUI |
| Ripes GUI: unknown symbol `LED_MATRIX_0_BASE` | add the LED Matrix in the I/O tab before assembling |
| picture is shifted or garbled | the matrix is not 35 x 25 (width and height boxes swapped) |
| picture is correct but nothing animates | `DELAY` too small, or you are on a very fast model; raise it |
| `Unknown directive '.if'` or `'.include'` | the Ripes assembler has no such directive; use `#if` / `#include` in the `.s` sources (preprocessed) |
| exit code 1 with the dummy | `led_data.s` and `solver.c` disagree: run `python3 gen_led_data.py` |
| `make: riscv64-elf-gcc: No such file` | any C compiler can preprocess: `make run RVCC=cc` |
| strange preprocessor error on a `#` line | a comment starting with `# if` or `# define`; use `//` |

## 10. Final builds for the submission

- Measurement build: `make cli` (the renderer is compiled out, `--iret` counts), `.text` size with the GNU link command in `SPEC.md`.
- Demonstration build: `make gui`, with the matrix at 35 x 25.
- State in the note that the two differ only in the renderer, and that the Ripes assembler has no `.if`, so a C-preprocessor switch is used.
- Keep one test case per required kind: solved, short scramble, distance 11 (`SPEC.md` has the strings and expected lengths). Each needs its
  own `STATE`/`EXPECT_LEN`; running three cases in one program is a loop over a table of states that you can add around the `solve` call.
