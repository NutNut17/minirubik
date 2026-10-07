# Stage 4 numbers: the RV32I solver against the C reference

All numbers: Ripes `--iret` on RV32_ISS (source `5b8a616`, Release), from `./bench.sh <file>` (14 hardest distance-11 states) and `./run_tests.sh`.
`retired` of the asm includes about 5,000 instructions of harness (parse, replay, validate); the C numbers are the search alone.
`.text` of the asm is the solver only (total minus the harness, measured by linking with an empty `solve`).

## Result

| | C reference (`gcc -O2 -march=rv32i`) | assembly (`solver.s`) |
| :--- | ---: | ---: |
| hardest state `41625372313211`, retired | 2,540,235 | **1,203,894** (about 1,199,000 without the harness, 2.1 times fewer) |
| 14 hardest states, retired | 25,109,302 | 12,281,162 (2.0 times fewer) |
| instructions per child | 55.9 | 27.4 |
| `21345671111111` (reported vector) | 628,454 (parse included) | 326,073 (harness included) |
| code size | 1,220 B (whole program) | 1,056 B (solver) |
| static data | 118,747 B | 119,251 B (116.5 KiB of 128) |

Correctness of the final `solver.s`: all 2,644 distance-11 states and 700 random states of every distance solve optimally on RV32_ISS (0 failures); the fixed cases plus random cases pass on RV32_ISS and RV32_5S (`./run_tests.sh`); the file assembles with `-march=rv32i`, with 0 `mul/div/rem` instructions and no helper calls.

## Iterative refinement (each step measured; files in `versions/`)

| Step | File | Change | Hardest | 14 hardest | per child | solver B |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: |
| 1 | `solver_v1_direct.s` | direct translation of the C loop, frame in memory | 1,972,360 | 19,502,087 | 43.5 | 784 |
| 2 | `solver_v2_registers.s` | this level's state (lp, lo, cp, co, next, last) in registers; records kept as addresses; solved test is `beqz budget` | 1,616,997 | 15,979,237 | 35.6 | 800 |
| 3 | `solver_v3_faces.s` | loop over faces, the three turns of a face are three copies of the code | 1,289,409 | 12,732,247 | 28.4 | 1,232 |
| 4 | `solver_v4_order.s` | pruning checks in the order hp, B, A, ho | 1,203,581 | 12,276,780 | 27.4 | 1,232 |
| 5 | `solver.s` | rank the string with loops instead of straight-line code | 1,203,894 | 12,281,162 | 27.4 | 1,056 |

Why each step pays, in operation counts per child:
- **1 to 2.** The C code keeps lp, lo, cp, co, next, last in the frame, so every child loads and stores them (about 9 memory operations) and re-adds the table base to the child's offset. Holding the state in registers and spilling to the frame only when going down or up (about 17 percent of children descend) removes most of that. A record is addressed through its address, so the `PREC +` add that computes the child also serves the pruning loads. Solved test: with `budget == 0` a surviving child has h = 0, and only the solved state has h = 0; with `budget > 0` it cannot be solved (a smaller bound would have found it).
- **2 to 3.** The per-move table reads (`move_f2`, `move_turns`, `move_end`), the turn test and the `last`-face compare cost about 9 instructions per child. Looping over faces and writing the three turns out removes all of them; the price is 432 bytes of code.
- **3 to 4.** Same code, different order of four independent tests (measured over 7 orders, 14 hardest states, retired): hp,B,A,ho 12,276,780; hp,A,B,ho 12,505,976; hp,B,ho,A 12,329,060; hp,A,ho,B 12,642,553; hp,ho,A,B 12,732,247; ho,hp,A,B 12,914,253; A first 13.7 million. Table B rejects more than table A at equal cost, and ho rejects least of the cheap tests.
- **4 to 5.** The rank runs once per query: loops cost about 300 more instructions (0.03 percent of the hardest state) and save 176 bytes, which brings the solver under the C code size.

Ideas measured or argued and not used: unrolling the code per face (faces as immediates, about 2 fewer instructions per child, three times the code); storing `pk >> 1` and the shift amount in the records (every twist key is even, so the nibble read could be 9 instead of 11 instructions, about 2 per child, but it needs 12-byte records, 10 KB more data, and a generator change); testing the solved state with `xor/or` instead of `beqz budget` (3 more instructions, same result).

## Reproduce
```sh
cd minirubik/asm
./bench.sh versions/solver_v1_direct.s      # and v2, v3, v4, solver.s
./run_tests.sh                              # fixed + random cases on RV32_ISS and RV32_5S
./run_tests.sh --state 41625372313211 --models RV32_ISS
```
