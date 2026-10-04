# Assignment 1: minirubik on RV32I

## 0. Setup and Disclosure

| Setup | Detail |
| - | - |
| Fork URL | https://github.com/NutNut17/minirubik (commit `73e4239`) |
| Upstream URL | https://github.com/sysprog21/minirubik (commit `231796c`) | 
| Ripes Build | master `5b8a616` (`v2.2.6-106-g5b8a616`), built from source in Release mode with CMake 4.4.3 and Qt 6.11.2 |
| System GCC Version | Apple clang version 17.0.0 (clang-1700.6.4.2) Target: arm64-apple-darwin25.5.0 |
| `riscv64-elf-gcc` version | GNU GCC 16.2.0 |

### AI usage disclosure

Claude Code was used to explain concepts in `report.md` and `hw2.md`, to set up the fork, and to
install and build the tools. Nothing here has been written as final analysis;
the representation, the search design, the measurements, the optimization
reasoning and the RV32I assembly will be my own work.

## 1. The State Space

> Outline: Math of the state space: the group and its order (3,674,160), the Cayley graph, the 9 generators, why BFS proves the diameter is 11, and the mod-3 twist rule.

### Cube model and fixed corner

The 2x2x2 cube has 8 corner cubies and no edges or centers. Turning the whole
cube does not change the puzzle, so I fix one corner (cubie 0, front-upper-left)
and only turn the three faces that do not touch it: R, B and D.

A state is a position-to-cubie map `p[0..6]` (a permutation of the seven free
cubies) and a twist `o[0..6]` in {0, 1, 2} for each position. 0 indicates correct, 1 indicates 120deg and 2 indicates 240 degree.

### Group, order and Cayley graph

The reachable states form a group G, the stabilizer of the fixed corner. Its
order comes from counting:

- the 7 free cubies can be permuted in 7! = 5,040 ways;
- the 7 twists give 3^7 values, but only those whose sum is 0 mod 3 are
  reachable, which leaves 3^6 = 729.

|G| = 7! x 3^6 = 5,040 x 729 = **3,674,160**.

The generators are the nine half-turn-metric moves
`R R2 R' B B2 B' D D2 D'`. The Cayley graph has the 3,674,160 group elements
as vertices and an edge from `g` to `g.s` for each generator `s`. The generator set
is closed under inverses, so the graph is undirected and every vertex has
degree 9. That gives 3,674,160 x 9 = 33,067,440 directed edges, which is the
edge count that the baseline's BFS expands. This is a Cayley graph.

### The orientation-sum invariant (mod 3)

Each quarter turn adds twists that total 0 mod 3:

- R: positions with +1, +2, +1, +2, total 6 = 0 mod 3
- B: the same pattern, total 6 = 0 mod 3
- D: all +0, total 0

The sum of all seven twists therefore never changes, and the solved state has sum 0. This is a modulo-3 invariant.

### Ranking: Lehmer code and base-3

A state maps to a unique integer in [0, 3,674,160):

```
rank = p * 729 + o
```

- `p` in [0, 5040) is the Lehmer (factoradic) rank of the permutation: for each
  position, count the later entries that are smaller, and combine the counts
  with `p = p * (7 - i) + c_i`.
- `o` in [0, 729) is the first six twists read as a base-3 number.

The solved state has rank 0. Because a move changes the permutation using only
the permutation and the twists using only the twists, `solver.c` keeps two
small transition tables per face instead of one large one.

### Diameter 11 by exhaustive BFS

Breadth-first search from the solved state visits all 3,674,160 states, so the
graph is connected and the search sees every distance. The deepest level is 11
and it contains 2,644 states, so a state at distance 11 exists, and because
the search ran out of unvisited states there is none deeper. The Cayley graph
looks the same from every vertex, so the distance from the identity to the
farthest vertex is the diameter.

Distance distribution from `report.md`

| d | states | d | states |
| ---: | ---: | ---: | ---: |
| 0 | 1 | 6 | 50,136 |
| 1 | 9 | 7 | 227,536 |
| 2 | 54 | 8 | 870,072 |
| 3 | 321 | 9 | 1,887,748 |
| 4 | 1,847 | 10 | 623,800 |
| 5 | 9,992 | 11 | 2,644 |

## 2. Stage 1: Characterizing the Baseline

> Outline: Stage 1, baseline: how solver.c works, its costs, your two Ripes measurements, and why the full table fails on Ripes.
> 
### What solver.c computes

`solver.c` builds a table `toward_solved[rank]` over all 3,674,160 states by BFS backward from the solved state. For each state it stores the move that leads one step closer to solved. A query follows those moves until the rank is 0, which gives an optimal solution of at most 11 moves.

Example: `./solver 21345671111111` prints `B' R' D2 R' B R B' R D2 B R'`.

### Where the cost lies

Peak memory of the baseline, computed and measured on my
machine with `/usr/bin/time -l`:

### Where the cost lies

Peak memory of the baseline computed, and measured on my machine with `/usr/bin/time -l`:

| Program | State | Wall time (s, min) | Peak RSS (B) |
| :--- | :--- | ---: | ---: |
| `solver` | 21345671111111 | 0.06 | 19,824,640 |
| `solver` | 12345671111111 | 0.06 | 19,824,640 |
| `mini` | 21345671111111 | 0.48 | 56,524,800 |
| `mini` | 12345671111111 | 0.48 | 56,524,800 |

This agrees with `report.md` (solver 0.065 s / 19.8 MB, mini 0.51 s / 56.5 MB).

### Measurement: Ripes memory usage

Method: `calibration/asm/store_loop.s` writes one non-zero byte to each of N consecutive guest addresses on `RV32_ISS` (4 instructions per byte). Peak host memory is recorded for N = 64 KiB (control) up to 8 MiB, three runs each (maximum kept), and
`slope = (peak(N) − peak(control)) / (N − control)`. Two metrics from `/usr/bin/time -l`: peak RSS and macOS peak memory footprint.

| Guest bytes N | Instructions retired | Peak RSS (B) | Peak footprint (B) | Slope, RSS (B/B) | Slope, footprint (B/B) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 65,536 (control) | 262,149 | 75,382,784 | 15,845,760 | — | — |
| 1,048,576 | 4,194,309 | 129,613,824 | 72,026,368 | 55.17 | 57.15 |
| 4,194,304 | 16,777,221 | 309,706,752 | 252,234,368 | 56.75 | 57.25 |
| 8,388,608 | 33,554,437 | 549,830,656 | 492,489,920 | 57.00 | 57.27 |

Read control (`load_loop.s`: `lbu` from never-written addresses):

| Guest bytes N | Peak RSS (B) | Peak footprint (B) | Slope, RSS | Slope, footprint |
| ---: | ---: | ---: | ---: | ---: |
| 65,536 (control) | 74,924,032 | 15,599,808 | — | — |
| 1,048,576 | 129,597,440 | 72,010,112 | 55.62 | 57.38 |
| 4,194,304 | 309,755,904 | 252,267,200 | 56.88 | 57.32 |
| 8,388,608 | 504,512,512 | 492,506,240 | 51.61 | 57.30 |

Projection for the baseline's 18,405,414-byte peak (57.27 B/B × 18,405,414):

| Metric | Projected host memory |
| :--- | ---: |
| Footprint slope | 1,054,078,060 B = 1005 MiB = **0.98 GiB** (12 % of this machine's 8 GiB) |
| RSS slope | 1,049,108,598 B = 0.98 GiB |

### Measurement: simulation rate per processor model

Method: `calibration/asm/store_loop.s` run at two sizes per model, `--iret --exectime`, three runs each, minimum time kept. `rate = (iret_big − iret_small) / (ms_big − ms_small) × 1000`.

| Model | Loop N small / big | iret small / big | ms small / big (min of 3) | Rate (instr/s) |
| :--- | :--- | :--- | :--- | ---: |
| RV32_ISS | 1,000,000 / 5,000,000 | 4,000,006 / 20,000,006 | 163 / 789 | **25,559,105** |
| RV32_5S | 5,000 / 25,000 | 20,006 / 100,006 | 70 / 352 | **283,688** |

All repeated runs (ms):

| Model | Size | Run 1 | Run 2 | Run 3 |
| :--- | ---: | ---: | ---: | ---: |
| RV32_ISS | 1,000,000 | 163 | 164 | 163 |
| RV32_ISS | 5,000,000 | 830 | 829 | 789 |
| RV32_5S | 5,000 | 72 | 70 | 75 |
| RV32_5S | 25,000 | 352 | 353 | 352 |

This rate is for a sequential 4-instruction loop, the baseline's loads and stores go through the same hash map (about 1 GiB of host memory by the measurement above, which also slows lookups), and its 3.67 MB table and 17.553 MiB peak exceed the 128 KiB static-data budget regardless of speed.

### Why full table fails on Ripes

| Constraint | My data | Does it kill the baseline? |
| :--- | :--- | :--- |
| 128 KiB static data | The table alone is 3,674,160 B = 3,588 KiB | **Yes**, 28× over. |
| Instruction budget | Worst case about 5×10⁷ (my reconstruction from `hw2.md`) vs about 10⁹ | **Yes**, about 20× over. |

## 3. Stage 2: Representation and Algorithm

> Outline: Stage 2, design: IDA* plus heuristic tables, the admissibility argument, and memory per table.

### Search: IDA*

### Heuristic tables

### Admissibility argument


### Memory budget (bytes per table)


#### solver.c vs mini.c

| `solver.c` | `mini.c` | `final.c` |
| -- | -- | -- |
| Optimized | Brute Force | More optimized |
| Prebuild a mapping tables to the next rank for step of each stage before BFS (2 ops) | Reranking byte representation to rank on every edge during BFS (21 ops) | Use `solver.c` |

## 4. Stage 3: Efficiency in C

> Outline: 5. Stage 3, C optimization: operation counts before and after, and node counts.

### Removing multiply, divide and modulo
### Branches and memory traffic
### Operation and node counts

## 5. Stage 4: RV32I Assembly

> Outline: 6. Stage 4, RV32I: key instruction sequences, a table of --iret and .text size per refinement, and a comparison against gcc -O2.

### Key instruction sequences
### Iterative refinement (--iret and .text per step)
### Comparison with gcc -O2 -march=rv32i

## 6. Correctness


> Outline: Correctness gates: H1–H4 results (including H3 wall time) and T5–T7.

### Host gates H1–H4
### Target gates T5–T7
### Test cases and results

## 7. LED Matrix Visualization

> Outline: LED matrix: how a facelet maps to a pixel and then to an address.

### Net layout and pixel mapping
### Redrawing after each move

## 8. Pipeline Walkthrough

> Outline: Pipeline walkthrough: IF, ID, EX, MEM, WB with screenshots.

### IF / ID / EX / MEM / WB
### Signals and memory updates

## 9. Negative Results

> Outline: What didn't work: negative results you measured.


## References

1. `report.md` in the repository, sections 1 to 7.
2. Ripes, https://github.com/mortbopet/Ripes, commit `5b8a616`.
3. Jaap Scherphuis, Pocket Cube (distance distribution in both metrics).
4. Korf, *Finding Optimal Solutions to Rubik's Cube Using Pattern Databases*, AAAI-97.
