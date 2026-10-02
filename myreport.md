. Setup: fork URL, upstream commit 231796c, Ripes version, GCC version, AI-use disclosure.
2. Math of the state space: the group and its order (3,674,160), the Cayley graph, the 9 generators, why BFS proves the diameter is 11, and the mod-3 twist rule.
3. Stage 1, baseline: how solver.c works, its costs, your two Ripes measurements, and why the full table fails on Ripes.
4. Stage 2, design: IDA* plus heuristic tables, the admissibility argument, and memory per table.
5. Stage 3, C optimization: operation counts before and after, and node counts.
6. Stage 4, RV32I: key instruction sequences, a table of --iret and .text size per refinement, and a comparison against gcc -O2.
7. Correctness gates: H1–H4 results (including H3 wall time) and T5–T7.
8. LED matrix: how a facelet maps to a pixel and then to an address.
9. Pipeline walkthrough: IF, ID, EX, MEM, WB with screenshots.
10. What didn't work: negative results you measured.

# Assignment 1: minirubik on RV32I

## 0. Setup and Disclosure
### Fork and versions        (fork URL, upstream commit, Ripes build, GCC version)
### AI usage disclosure

## 1. The State Space
### Cube model and fixed corner
### Group, order and Cayley graph
### The orientation-sum invariant (mod 3)
### Diameter 11 by exhaustive BFS

## 2. Stage 1: Characterizing the Baseline
### What solver.c computes
### Ranking: Lehmer code and base-3
### Where the cost lies
### Measurement: host bytes per guest byte
### Measurement: simulation rate per processor model
### Why the full table fails on Ripes

## 3. Stage 2: Representation and Algorithm
### Search: IDA*
### Heuristic tables
### Admissibility argument
### Memory budget (bytes per table)

## 4. Stage 3: Efficiency in C
### Removing multiply, divide and modulo
### Branches and memory traffic
### Operation and node counts

## 5. Stage 4: RV32I Assembly
### Key instruction sequences
### Iterative refinement (--iret and .text per step)
### Comparison with gcc -O2 -march=rv32i

## 6. Correctness
### Host gates H1–H4
### Target gates T5–T7
### Test cases and results

## 7. LED Matrix Visualization
### Net layout and pixel mapping
### Redrawing after each move

## 8. Pipeline Walkthrough
### IF / ID / EX / MEM / WB
### Signals and memory updates

## 9. Negative Results

## References