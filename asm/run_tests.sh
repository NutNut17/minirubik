#!/usr/bin/env bash
# Runs your solver on a list of test cases on Ripes and checks each result.
#
#   ./run_tests.sh                       fixed cases + 12 random ones, RV32_ISS and RV32_5S, with tables
#   ./run_tests.sh --random 40           more random cases
#   ./run_tests.sh --models RV32_ISS     one model only (faster)
#   ./run_tests.sh --no-tables           do not append tables.s (solver that does not use PREC/OREC)
#   ./run_tests.sh --solver other.s      test another file instead of solver.s
#   ./run_tests.sh --state 41625372313211   one case only (the expected length comes from the host oracle)
#
# For every case the harness (main.s) replays your moves on its own cube model and exits 0 only if the cube is
# solved AND the number of moves equals the optimal length, which comes from the host program ../ida.
# With the placeholder solver only the LED demo case can pass; that is expected.
set -u
cd "$(dirname "$0")"
RANDOMN=12; MODELS="RV32_ISS RV32_5S"; TABLES=1; SOLVER=solver.s; ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --random)    RANDOMN=$2; shift 2;;
        --models)    MODELS=$2; shift 2;;
        --no-tables) TABLES=0; shift;;
        --solver)    SOLVER=$2; shift 2;;
        --state)     ONLY=$2; shift 2;;
        *) sed -n 2,13p "$0"; exit 2;;
    esac
done
RIPES_BIN=${RIPES_BIN:-../../Ripes/build/Ripes.app/Contents/MacOS/Ripes}
RVCC=${RVCC:-riscv64-elf-gcc}
[ -x "$RIPES_BIN" ] || { echo "Ripes not found: $RIPES_BIN (set RIPES_BIN=...)" >&2; exit 2; }
[ -x ../ida ] || make -s ../ida >/dev/null || { echo "cannot build ../ida" >&2; exit 2; }
[ "$TABLES" = 1 ] && { [ -f tables.s ] || make -s tables.s >/dev/null; }
[ -f led_data.s ] || python3 gen_led_data.py >/dev/null
reason() {   # exit code of the harness -> words
    case "$1" in
        1) echo "cube not solved";;
        2) echo "wrong length";;
        3) echo "more than 11 moves";;
        asm-error) echo "assembler error";;
        *) echo "exit $1";;
    esac
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---- the cases: "state" lines; expected lengths from the oracle ------------------------------
{
  if [ -n "$ONLY" ]; then echo "$ONLY"; else
    echo 12345671111111      # solved
    echo 35724612221132      # short scramble (R B D R)
    echo 21345671111111      # sample vector, distance 11
    echo 41625372313211      # hardest state, 45,312 nodes
    python3 - "$RANDOMN" <<'PY'
import random, sys
random.seed(2026)
for _ in range(int(sys.argv[1])):
    p = list(range(1, 8)); random.shuffle(p)
    o = [random.randrange(3) for _ in range(6)]; o.append((-sum(o)) % 3)
    print(''.join(map(str, p)) + ''.join(str(x + 1) for x in o))
PY
  fi
} > "$TMP/cases"

printf "%-16s %4s  %-9s %5s %12s  %s\n" state want model exit retired result
fail=0; total=0
while read -r state; do
    want=$(../ida "$state" | tail -1 | awk '{print $1}')
    for m in $MODELS; do
        $RVCC -E -P -x assembler-with-cpp -DUSE_TABLES=$TABLES -DRENDER=0 -DSOLVER_FILE="\"$SOLVER\"" \
              -DTEST_STATE="\"$state\"" -DTEST_LEN=$want main.s > "$TMP/t.s" 2> "$TMP/cpp.err" \
              || { echo "preprocessing failed:"; cat "$TMP/cpp.err"; exit 2; }
        out=$("$RIPES_BIN" --mode cli --src "$TMP/t.s" -t asm --proc "$m" --iret --timeout 120000 2>&1)
        code=$(echo "$out" | awk '/exited with code/{print $NF}')
        ret=$(echo "$out" | awk '/instructions retired/{getline; print $1}')
        if echo "$out" | grep -q "Error during assembly"; then code="asm-error"; fi
        total=$((total + 1))
        if [ "$code" = 0 ]; then
            res=PASS
        else
            res="FAIL ($(reason "$code"))"; fail=$((fail + 1))
        fi
        printf "%-16s %4s  %-9s %5s %12s  %s\n" "$state" "$want" "$m" "${code:--}" "${ret:--}" "$res"
    done
done < "$TMP/cases"
echo
echo "$((total - fail)) of $total passed"
[ $fail -eq 0 ]
