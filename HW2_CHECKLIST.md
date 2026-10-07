# hw2.md requirements check (state of 2026-10-07)

Legend: OK done and evidenced | CHECK needs a look from you | TODO not done, only you can do it

## Phase 1 requirements
| Requirement (hw2.md) | Status | Evidence / what to do |
| :--- | :---: | :--- |
| Ripes build with RV32_ISS, version recorded | OK | report section 0: master `5b8a616`, Release |
| Fork recorded with the commit it was forked from | OK | report section 0: `231796c` |
| All Phase 1 work pushed as commits **with meaningful messages** | TODO | the history has "My Fork Initialization", "Save", HackMD syncs; commit the new work (asm/, solver, report) with real messages (imperative subject, short body) and push |
| HTM metric used throughout | OK | report sections 1, 3 |
| Stage 1: explain program, representation, invariants, cost | OK | report sections 1-2 |
| Stage 1: host-bytes-per-guest-byte and instructions/s on ISS + one pipelined model | OK | 57 B/B; 25.56 M/s ISS, 0.284 M/s RV32_5S |
| Stage 1: why `report.md` section 7's full table fails on Ripes | OK | report "Why full table fails" |
| Stage 2: optimal algorithm, optimality shown, justified against stage 1 and the budget | OK | IDA*, admissibility argument, H1/H3 |
| Stage 3: C improved, effect argued from operation counts | OK | report section 4 |
| Stage 4: assembly + test data, measured with `--iret` | OK | `asm/solver.s`, `asm/versions/`, `asm/OPTIMIZATION.md` |
| Static data (.data + .bss + .rodata) <= 128 KiB | OK | 119,251 B |
| No distance-11 state over the retired-instruction limit on RV32_ISS, renderer compiled out | CHECK | worst of all 2,644 states: 1,203,894. The limit is missing from the copy of hw2.md I read (I reconstructed about 5e7): read the number on the course page |
| Count for `21345671111111` reported separately | OK | 326,073 (report T6) |
| Precomputation rule: no complete distance table | OK | largest table 68,040 keys, not 3.67 M |
| RV32I only, no M extension, no `__mulsi3` | OK | assembles with `-march=rv32i`; 0 mul/div/rem |
| No heap, no recursion, no floating point | OK | |
| Any 14-character state, inlined at assembly time | OK | `make run STATE=... LEN=...` (`LEN=255`: no length check) |
| >= 3 own test cases (solved, short scramble, distance 11), validated inside the program | OK | `make suite` (4 cases in one file) |
| Beat `gcc -O2 -march=rv32i` on retired instructions and code size; report the reference build; explain losses | OK | 1,203,894 vs 2,540,235 retired. Code size: solver 1,056 B < C 1,220 B, but whole program 1,640 B > 1,220 B, explained in the report |
| Iterative refinement with measurements per step; both conventions stated | OK | report Stage 4 table |
| Everything runs on Ripes | CHECK | CLI verified; open `asm/build_gui.s` once in the GUI |
| H1-H4 (host), H3 wall time reported | OK | 0 violations; 28 s |
| T5-T7 on RV32_ISS and one pipelined model | OK | report section 6; add a grader's state when given |
| LED matrix 35 x 25, net, redraw after every move, driven by the solver's output | CHECK | verified headless (12 frame checksums); **watch it once in the GUI** and take a screenshot |
| Renderer behind an assemble-time switch; note says the builds differ only in the renderer | OK | C-preprocessor `#if RENDER` (Ripes has no `.if`); 112 lines; stated in the report |
| Instruction-level walkthrough in Ripes (IF/ID/EX/MEM/WB, signals, memory) | TODO | text is drafted in report section 8; **you must take the screenshots** in the Ripes GUI (RV32_5S) |

## Documentation and submission
| Requirement | Status | What to do |
| :--- | :---: | :--- |
| HackMD note with math, optimisation argument, memory, RV32I work, analysis | OK | `myreport.md` is complete; paste it into HackMD (HackMD is the master) |
| No complete program listings in the note; link to the fork | OK | fragments only; links in the "Code" section: replace `main` by the tag after pushing |
| >= 3 substantive HackMD revisions | CHECK | the repo shows HackMD syncs on Oct 4 and Oct 7; confirm in HackMD's history |
| Note published, anyone can read, **write = owner only** (not "signed-in") | CHECK | HackMD share settings |
| All writing in English | OK | |
| AI disclosure (Section 4.1) | CHECK | section 0 is rewritten to what happened; fill in the two bracketed gaps (who permitted AI for the assembly; what you did yourself) |
| Tag the submitted commit; record the tag and the HackMD revision URL on the form | TODO | `git tag phase1 && git push origin phase1`, then the form (opened Sep 28) |
| Phase 2 interview (Oct 18) | TODO | be able to explain every part; the draft sections are yours to reword |

## Things in the repository to clean before submitting
- Generated or binary files are tracked: `ida`, `rv/ida_rv.elf`, `rv/tables.h` (9,546 lines), `asm/tables.s` (19 k lines), `calibration/results/*.s`. Untrack them (`git rm --cached`) and ignore them; keep `asm/build_cli.s`, `build_gui.s`, `build_suite.s`, which are the ready-to-run programs.
- `report.md` is upstream's; your note is `myreport.md`.
- In `myreport.md`, the quoted note under "Ranking" ("Lehmer is designed to punish the state that has more false of the cubies...") is not accurate: the Lehmer code only counts, for each position, how many later entries are smaller. Reword or remove it.
