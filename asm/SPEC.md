# Interface and test vectors for the hand-written RV32I solver

This file describes the data and the checks. The code is yours (hw2.md requires the RV32I assembly to be your own work).

## What is generated for you

`make -C asm tables.s` writes `tables.s`: pure `.data` (Ripes' assembler accepts only `.data` and `.text`; it rejects `.rodata`, `.section`, `.if` and `.include`). The Makefile joins `main.s`, your `solver.s`, `led_data.s` and (with `USE_TABLES=1`) `tables.s` into one flat file with the C preprocessor (see `TUTORIAL.md`), because Ripes' CLI takes a single source file. Loading was verified against the host program on eight probes (first, last and middle entries of each table: all equal).

| Label | Contents | Size |
| :--- | :--- | ---: |
| `PREC` | 5,040 records of 10 B indexed by permutation rank p | 50,400 B |
| `OREC` | 729 records of 12 B indexed by twist rank o | 8,748 B |
| `TABA` | 51,030 nibbles | 25,515 B |
| `TABB` | 68,040 nibbles | 34,020 B |

Record layouts (byte offsets, all fields little-endian):

| PREC (10 B) | +0 | +2 | +4 | +6 | +7 | +8 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| field | next R | next B | next D | hp | pkA | pkB (half) |

| OREC (12 B) | +0 | +2 | +4 | +6 | +7 | +8 | +10 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| field | next R | next B | next D | ho | 0 | qkA (half) | qkB (half) |

- `next` fields hold the **byte offset** (10 p' or 12 o') of the record after one quarter turn of that face, so the offset is the state.
- A state is solved when both offsets are 0.
- `qkA` and `qkB` are already multiplied by 210 and 2,520. A table index is `pkA + qkA` (A) and `pkB + qkB` (B), and the entry is the nibble at that index: byte `index >> 1`, shifted right by `(index & 1) * 4`, masked with 15. Even index = low nibble.
- Heuristic `h = max(hp, ho, nibble A, nibble B)`. A child at depth g survives iff `g + h <= bound`.
- The algorithm is in `ida_core.h` / `ida_core4.h` (the OPT 5 branch is the reference); the reasoning is in your report, Stage 2.

## Rules to remember (hw2.md)

- RV32I only: no `mul`, `div`, `rem`; no `__mulsi3`-style helpers.
- No heap, no recursion, no floating point; size everything at assembly time.
- Static data `.data` + `.bss` at most 128 KiB (131,072 B). The tables above are 118,683 B.
- Accept any valid 14-character state inlined at assembly time; validate results inside the program.
- Search must run on the target. LED code is guarded by `#if RENDER` (the C preprocessor in the Makefile); Ripes' assembler has no `.if`, and its CLI cannot assemble LED symbols.
- Ranking the input (Lehmer code of the 7 digits, base-3 of the first six twists) is yours to write; p and o are used separately.
- Move numbers in the reference: `face * 3 + turns - 1` with faces R = 0, B = 1, D = 2; R2 and R' are 2 and 3 quarter turns but cost 1.

## Test vectors (expected values from the host oracle)

| Case | State | p | o | Optimal length | One optimal solution | Reference nodes |
| :--- | :--- | ---: | ---: | ---: | :--- | ---: |
| solved | `12345671111111` | 0 | 0 | 0 |  | 0 |
| short scramble (R B D R) | `35724612221132` | 1905 | 353 | 4 | R' D' B' R' | 18 |
| sample, distance 11 | `21345671111111` | 720 | 0 | 11 | R B' D2 R' B R' B' R D2 R B | 11439 |
| hardest distance-11 (45,312 nodes) | `41625372313211` | 2234 | 426 | 11 | R' D R' B D B2 R' D B D2 B' | 45312 |

Any optimal solution is acceptable; check the length and replay the path to the solved state inside the program.

## Numbers to beat (C reference, `riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32`, RV32_ISS, Ripes source 5b8a616)

| Quantity | C reference |
| :--- | ---: |
| `.text` | 1,220 B |
| Hardest distance-11 state (p = 2234, o = 426), search only | 2,540,235 retired |
| `21345671111111` including parsing the string | 628,454 retired |
| Short scramble including parsing | 1,129 retired |
| Solved cube including parsing | 89 retired |
| Instructions per node | about 56 (53.3 to 60.2) |

hw2.md also asks you to report this reference build next to your assembly and to explain any case where the assembly does not win.

## Measuring your build

```sh
make run                                   # exit code and retired instructions on RV32_ISS (renderer compiled out)
make run PROC=RV32_5S                      # a pipelined model
riscv64-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -static -T ../rv/link.ld -Wl,-e,main -o x.elf build_cli.s
riscv64-elf-size -A x.elf | grep -E '^\.(text|data|bss)'     # .text bytes; .data + .bss is the static data (limit 131072)
```
`build_cli.s` includes the harness (about 5,000 instructions and a few hundred bytes of `.text` for parsing, replaying and validating the cube). When you compare with the C reference (which measured the search alone), subtract that or report both.
