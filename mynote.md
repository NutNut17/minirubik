# Project notes: structure, how to run, how to take the pipeline screenshots

## Structure (everything under `minirubik/`)
| Group | Files | Role |
| :--- | :--- | :--- |
| **Run on Ripes** | `asm/build_cli.s` | the final program, hardest case, no drawing (what `--iret` measures) |
| | `asm/build_suite.s` | same program, 4 built-in cases; exit code = number of failures |
| | `asm/build_gui.s` | LED animation (add an LED Matrix 35 x 25 first) |
| | `asm/pipeline_demo.s` | 5-instruction demo for the pipeline screenshots |
| **Assembly sources** | `asm/solver.s` | **the solver** |
| | `asm/main.s` | harness, validation, LED renderer |
| | `asm/led_data.s`, `asm/tables.s` | generated data (LED tables, solver tables) |
| | `asm/versions/` | the five refinement steps + the dummy solver |
| **Optimized C** | `ida_core4.h` (lines 56-126) | the search (OPT 5), translated into `solver.s` |
| | `ida_core.h`, `records.h` | OPT switch, record layouts |
| | `ida.c` | tables, gates H1-H4, writes the assembly tables |
| | `rv/ida_rv.c` | C reference build for RV32I (what gcc compiles) |
| **Baseline** | `solver.c`, `mini.c`, `report.md` | the original full-table solver |
| **Measurements** | `calibration/` | Stage 1 scripts and results |
| **Tools** | `asm/run_tests.sh`, `asm/bench.sh`, `asm/gen_led_data.py` | tests, benchmark, generator |
| **Docs** | `myreport.md`, `HW2_CHECKLIST.md`, `asm/TUTORIAL.md`, `asm/OPTIMIZATION.md`, `asm/SPEC.md`, `img/` | note, checklist, quick start, numbers, specs, screenshots |

## Run (in `asm/`)
```sh
make run        # build_cli.s on RV32_ISS: exit code and retired instructions (expect 1,203,894)
make suite      # the four built-in cases
./run_tests.sh  # fixed + random cases on RV32_ISS and RV32_5S
make gui        # rebuild build_gui.s, then open it in the Ripes GUI
```

## Pipeline screenshots (Ripes GUI, processor RV32_5S)
Labels may differ slightly in your Ripes build; the idea is the same.
1. Ripes: click the processor button (top left) and choose the **5-stage** processor (RV32_5S, with forwarding and hazard detection).
2. **Editor** tab: open `asm/pipeline_demo.s` (it uses `#` comments, so Ripes reads it directly). Fix any assembler error shown.
3. **Processor** tab: the datapath with IF, ID, EX, MEM, WB. Turn on the display of signal values if your build has the option. Press **Reset**.
4. Press the single-step (clock) button repeatedly. The instruction list shows which instruction is in which stage. After about 11 steps `add t0, a0, a6`
   (instruction 1 of the five) is in **IF**: take screenshot 1. One more step: it is in **ID** (screenshot 2), then **EX** (3), **MEM** (4), **WB** (5). Use Undo to go back and retake.
5. Also take one when `add a0, t0, s3` appears in ID **twice** with a bubble in EX: that is the load-use stall.
6. For the branch: change `li s1, 4` to `li s1, 1`, reassemble, and step until `bltu` is in EX: the two instructions behind it are flushed.
7. macOS: **Shift+Cmd+4**, press **Space**, click the Ripes window; the PNG lands on the Desktop. Move it to `img/` and rename (`if.png`, `id.png`, `ex.png`, `mem.png`, `wb.png`, `stall.png`).
8. In `myreport.md`, section 8, add under each stage `![IF](img/if.png)` and so on.

What each screenshot must show (hw2.md: signals and stages):
| Stage | Show |
| :--- | :--- |
| IF | PC, instruction memory output, PC + 4 |
| ID | register-file read ports (the two source registers), the immediate, the control signals (register write, memory read/write) |
| EX | ALU inputs and result; for `bltu` the comparison; the forwarding multiplexer selects |
| MEM | data-memory address and read data (`lhu`, `lbu` only); nothing for the others |
| WB | the write-back multiplexer (ALU result or memory data) and the register-write enable |

## Also to do (see `HW2_CHECKLIST.md`)
Watch `asm/build_gui.s` once in the GUI (screenshot of the LED matrix at the start and at the end), commit and push with real messages, tag, fill in the AI-disclosure gaps in `myreport.md`.
