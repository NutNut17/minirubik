# Session 1: Calibration (Stage 1 measurements)

Goal (hw2.md, Stage 1): reproduce **two measurements on your own installation**.

1. **Host bytes per guest byte** in Ripes (the `unordered_map<address, byte>` guest memory).
2. **Retired instructions per second**, for `RV32_ISS` and at least one pipelined model.

Then use them to explain why `solver.c`'s 17.553 MiB / ~10^9-instruction build cannot run on the target.

All scripts are in this folder and call **the Ripes you built yourself**:
`hw1/Ripes/build/Ripes.app/Contents/MacOS/Ripes` (Release, `-O3`). Override with `RIPES_BIN=/path/to/Ripes ./run_rate.sh ...`.
Output goes to `results/` (created automatically): a summary file per measurement and the full raw Ripes output of every run in `results/raw/`.
Scripts only measure; they never edit anything outside `results/`. If Ripes is missing or has no `RV32_ISS`, they stop with an error instead of printing empty results.

## Files

| File | Purpose |
| :--- | :--- |
| `env.sh` | Sets `$RIPES` (your build), checks it exists and has `RV32_ISS`, defines the `ripes_run` / `rss_run` helpers. Sourced by the others. |
| `gcc_check.sh` | Records Mac model, macOS, Ripes build, commits, GCC/Clang versions → `results/versions.txt` |
| `asm/store_loop.s` | Template: writes 1 byte to each of `@N@` guest addresses (4 instr per pass) |
| `asm/load_loop.s` | Control template: only *reads* `@N@` never-written addresses |
| `asm/count_loop.s` | Template: register-only loop (2 instr per pass), no memory traffic |
| `run_mem.sh` | Peak RSS of Ripes for several region sizes → slope = host bytes per guest byte |
| `run_rate.sh` | Instructions/second for one processor model, by difference of two sizes |
| `host_baseline.sh` | Native `solver` / `mini` time and peak RSS (compare with report.md §4) |

## Reference files (read these *before* measuring)

hw2.md asks you to read the container declaration first, so the number is predicted, not a surprise.

| What | Where | Why |
| :--- | :--- | :--- |
| Guest memory container | `Ripes/external/VSRTL/include/VSRTL/core/vsrtl_addressspace.h:94` `std::unordered_map<VSRTL_VT_U, uint8_t> m_data;` | One map node per guest **byte** |
| Write path | same file, `writeMem` lines 28-35: loop `m_data[address++] = value & 0xFF` | A 32-bit `sw` creates 4 nodes |
| Read path | same file, `readMem` lines 37-43 uses `m_data[address++]` | `operator[]` **inserts** on a miss, so a read of an unwritten byte may also allocate. `load_loop.s` tests this. |
| Const read path | same file, `readMemConst` uses `find` | Does *not* insert (used by the GUI/memory view) |
| Memory used by ISS | `Ripes/src/processors/RISC-V/rviss/rviss.h:78,94` (`ADDRESSSPACEMM(m_memory)`) | Confirms the ISS uses this container |
| VSRTL memory (pipelines) | `external/VSRTL/include/VSRTL/core/vsrtl_memory.h:146` | Second map, used by the pipeline models |
| CLI options | `Ripes/docs/cli.md` (but it lags: it lacks `--exectime`; use `Ripes --help`) | `--iret`, `--exectime`, `--timeout`, `--proc` |
| Ecalls | Ripes GUI `Help → System calls`; `docs/ecalls.md` | `a7=10` exit |
| Baseline numbers | `minirubik/report.md` §4 "Memory Footprint and Performance" | 18,405,414 B peak; `solver` 0.065 s |
| Task text | `hw1/hw2.md` "Why the target changes the answer", Stage 1 | Idealized time table |

## How to calibrate (what these scripts teach)

A measurement tool is only trustworthy if you know what it measures and how noisy it is.

1. **Separate fixed cost from per-unit cost.** Starting Ripes costs ~70 ms and tens of MB before any guest instruction runs. Measuring two sizes and taking the **difference** removes it (the control run is the zero point).
2. **Check that the workload did what you think.** Each memory run must retire about `4N` instructions; the script warns if not. A wrong `iret` means you are measuring something else.
3. **Estimate noise before trusting a number.** Repeat runs (`REP`), keep the min time (OS interruptions only add time) or max RSS (reclaim only removes it), and look at how much the repeats disagree.
4. **Use more than one size.** If the slope changes with N, the model "bytes per entry" is not linear and one number is misleading; report the range.
5. **Predict first, then measure.** Before running, write your prediction in the note from the source (`unordered_map` node = key + value + next pointer + malloc header + bucket slot, i.e. tens of bytes) and from hw2.md's rate table; then compare. A large mismatch is the interesting finding.
6. **Cross-check with a second metric.** RSS vs footprint (memory); `store` vs `count` loops (rate).
7. **State the conditions.** Mac model, build type, repeats, idle machine, loop used.

## Procedure

Run from this folder. Close heavy apps first; keep the machine idle and plugged in.

### 0. Record versions
```sh
cd ~/mycode/sysprog/hw1/minirubik/calibration
./gcc_check.sh
```
Copy `results/versions.txt` into the "Fork and versions" section.

### 1. Host bytes per guest byte
Sizes: a small control, then growing regions. 65536 = 64 KiB control; 1, 4, 8 MiB.
```sh
./run_mem.sh store 65536 1048576 4194304 8388608
./run_mem.sh load  65536 1048576 4194304 8388608     # does a read allocate too?
```
- The slope columns = (peak − control peak) ÷ (N − control N). Rows should be close to each other; if they drift, use the largest sizes.
- The script prints a **projection for the 18,405,414-byte baseline** from the slope, and your machine's RAM next to it.
- Run it 3 times and use the **maximum** per size on an idle machine, as report.md does.
- Write your prediction (host bytes per guest byte) in the note **before** you run this, then compare.

### 2. Retired instructions per second
`run_rate.sh <PROC> <N_SMALL> <N_BIG> [REPEATS] [LOOP]`: uses `--iret` and `--exectime` (model execution time in ms, integer), so use sizes big enough that the difference is seconds, not milliseconds.
```sh
./run_rate.sh RV32_ISS       1000000 5000000 3 store
./run_rate.sh RV32_ISS       1000000 5000000 3 count
./run_rate.sh RV32_SS          20000  100000 3 store
./run_rate.sh RV32_5S           5000   25000 3 store
./run_rate.sh RV32_6S_DUAL      2000   10000 3 store
```
- The assignment's table is for a *"simple memory loop"*: compare `store` first; `count` is a second data point. State which loop you quote.
- If a run prints `ms_big <= ms_small`, raise `N_BIG`.
- Tune sizes so each big run takes roughly 5-30 s.
- Requirement is ISS + one pipelined model; the 5-stage is the natural choice. Measure SS / 6S_DUAL only if time allows.

### 3. Turn rates into the idealized baseline time
```
baseline_instructions ≈ 66,134,880 updates × 15 instr ≈ 9.92 × 10^8
time = baseline_instructions / rate
```
Compare with the table in hw2.md (15 min on ISS, 3.2 h on SS, 13.5 h on 5S, 45 h on 6S_DUAL) and state whether your machine agrees.

### 4. Native baseline (context row for the report)
```sh
./host_baseline.sh
```
Expected from report.md: `solver` ≈ 0.065 s / 19.8 MB RSS, `mini` ≈ 0.51 s / 56.5 MB.

## Report skeleton (fill in; paste into HackMD "Stage 1")

```markdown
### Measurement: host bytes per guest byte
Environment: <results/versions.txt>
| Region (guest B) | Peak RSS (B) | Slope vs 64 KiB control |
| ---: | ---: | ---: |
| 65,536 (control) | | - |
| 1,048,576 | | |
| 4,194,304 | | |
| 8,388,608 | | |
Slope ≈ ___ host B per guest B. Reads of unwritten memory: allocate / do not allocate (load_loop result).
Projection for 18,405,414 B: ___ GiB.

### Measurement: simulation rate
| Processor | Loop | iret small / big | ms small / big | instr/s | Idealized baseline time (9.92e8 instr) |
| --- | --- | --- | --- | ---: | ---: |
| RV32_ISS | store | | | | |
| RV32_5S  | store | | | | |

### Why the full table fails on Ripes
Memory: ___ ; Time: ___ ; Budget: 128 KiB vs 3,674,160 B table (even 4-bit packed: 1,794 KiB).
```

## Things easy to miss (checked against hw2.md)

- [ ] **Pin and record the Ripes build**: `v2.2.6-106-g5b8a616` (mac-universal2), plus **`RV32_ISS` present** (`Ripes --help | grep ISS`). T7 depends on it.
- [ ] **Record the fork base commit** `231796c` and your fork URL (`github.com/NutNut17/minirubik`).
- [ ] **GCC name**: hw2.md says `riscv64-unknown-elf-gcc`; Homebrew installs it as `riscv64-elf-gcc` (GCC 16.2.0 on this machine). Use that and say so in the note. It is needed in stage 4, not in this session.
- [ ] **ISS and one pipelined model**, not just ISS.
- [ ] **Read the container declaration first** (table above), then measure; hw2.md says this is the point of the order.
- [ ] **Use a difference, not a single run**: the Ripes process itself already uses ~70 MB RSS and ~70 ms before running anything, so single-run ratios are wrong.
- [ ] **Say it is an empirical property of one build**, not an API guarantee (hw2.md's own wording).
- [ ] **Project the 18,405,414-byte peak** (hw2.md asks for this explicitly).
- [ ] **State the 15 instr/update figure is an estimate**, not measured; hw2.md says so itself. (Optional extra: count instructions per update by compiling the update loop with `riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -S` and counting.)
- [ ] The note also asks for **why report.md §7's "keep the full table" argument fails on Ripes**: memory (host cost), time (hours), 128 KiB budget, and the "no precomputed distance table" rule.
- [ ] Keep **`results/*.txt`** and commit them; they are the evidence behind "every measurement you report" being yours.
- [ ] Two memory metrics are recorded: *peak RSS* and macOS *peak memory footprint*. They differ by a large fixed amount (shared libraries) but their **slopes** should agree; if they do not, say why.
- [ ] Update your `TODO.md` ("Measure observed Memory", "Use RV32_ISS") when done.
- [ ] Make the HackMD revision after this stage so it counts as one of the 3+ revisions.

## Known limits of these measurements

- `--exectime` has 1 ms resolution; hence large N and the difference method.
- Peak RSS counts only resident pages; under memory pressure it can read low. Use the max of several idle-machine runs.
- The instruction mix matters: the `store`, `load` and `count` loops give different rates. Say which one each figure uses.
- Rates depend on the Mac (M1 here) and the build; do not compare with hw2.md's table as if it were the same machine.
