#!/usr/bin/env bash
# Measurement 2: retired instructions per second of the SIMULATOR for one processor model.
#
# Wall time of a run = fixed cost (start Ripes, assemble, build the model) + instrs/rate.
# Run the same loop with two sizes; the fixed cost cancels in the difference:
#
#     rate = (iret_big - iret_small) / (ms_big - ms_small) * 1000        [instr/s]
#
# ms comes from Ripes' own --exectime (integer ms), iret from --iret.
# Pick N_BIG so the difference is several seconds, otherwise 1 ms resolution dominates.
#
# Usage: ./run_rate.sh <PROC> <N_SMALL> <N_BIG> [REPEATS=3] [LOOP=store|count|load]
set -euo pipefail
. "$(dirname "$0")/env.sh"
PROC=${1:?usage: run_rate.sh PROC N_SMALL N_BIG [REPEATS] [LOOP]}; NS=${2:?}; NB=${3:?}
REP=${4:-3}; LOOP=${5:-store}
TEMPLATE="$CAL_DIR/asm/${LOOP}_loop.s"
[ -f "$TEMPLATE" ] || { echo "no template $TEMPLATE" >&2; exit 2; }

measure() {   # N -> sets M_IRET, M_MS (min ms over REP runs: least disturbed by the OS)
    local n=$1 best=""
    sed "s/@N@/$n/" "$TEMPLATE" > "$OUT/${LOOP}_$n.s"
    for ((r=1; r<=REP; r++)); do
        ripes_run "$PROC" "$OUT/${LOOP}_$n.s" "rate_${PROC}_${LOOP}_${n}_run$r"
        printf "   N=%-10d run %d: iret=%-12d ms=%d\n" "$n" "$r" "$IRET" "$MS" >&2
        if [ -z "$best" ] || [ "$MS" -lt "$best" ]; then best=$MS; fi
    done
    M_IRET=$IRET; M_MS=$best
}

echo "== simulation rate | proc=$PROC loop=$LOOP repeats=$REP"
echo "   Ripes: $RIPES"
measure "$NS"; IS=$M_IRET; MSS=$M_MS
measure "$NB"; IB=$M_IRET; MSB=$M_MS
echo
echo "   small: iret=$IS  ms=$MSS      big: iret=$IB  ms=$MSB"
if [ "$MSB" -le "$MSS" ]; then
    echo "ERROR: ms_big ($MSB) <= ms_small ($MSS): N_BIG is too small for this model; raise it." >&2
    exit 1
fi
echo "   rate = ($IB - $IS) / ($MSB - $MSS) ms * 1000"
awk -v is="$IS" -v ib="$IB" -v ms="$MSS" -v mb="$MSB" -v p="$PROC" -v l="$LOOP" 'BEGIN{
    r=(ib-is)/(mb-ms)*1000
    printf "RESULT loop=%s proc=%s  %.0f instr/s = %.3f M instr/s\n", l, p, r, r/1e6
    printf "        baseline ~9.92e8 instr would take %.0f s = %.2f h at this rate\n", 9.92e8/r, 9.92e8/r/3600 }' | tee -a "$OUT/rate.txt"
