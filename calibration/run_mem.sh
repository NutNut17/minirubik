#!/usr/bin/env bash
# Measurement 1: HOST bytes per GUEST byte.
#
# Idea: the guest program touches N distinct guest bytes. Ripes keeps every touched
# byte in an unordered_map, so the Ripes process grows by (cost per entry) x N.
# Peak RSS also contains a fixed part (Qt, code, the simulator itself), so we measure
# a small CONTROL and subtract it:
#
#     slope = (RSS(N) - RSS(control)) / (N - control)      [host bytes / guest byte]
#
# Usage: ./run_mem.sh <store|load> <CONTROL_N> <N2> [N3 ...]     (env REP=3 repeats)
set -euo pipefail
. "$(dirname "$0")/env.sh"
KIND=${1:?usage: run_mem.sh store|load CONTROL N2 [N3...]}; shift
[ $# -ge 2 ] || { echo "need a control size and at least one bigger size" >&2; exit 2; }
REP=${REP:-3}; PROC=RV32_ISS
TEMPLATE="$CAL_DIR/asm/${KIND}_loop.s"
[ -f "$TEMPLATE" ] || { echo "no template $TEMPLATE" >&2; exit 2; }

echo "== host bytes per guest byte | loop=$KIND proc=$PROC repeats=$REP (max RSS kept)"
echo "   Ripes: $RIPES"
echo "   per pass the loop retires 4 instructions (sb/lbu, addi, addi, bnez), so a run"
echo "   with N bytes should retire about 4N instructions. That is the sanity check."
echo
printf "%12s %10s %13s %13s %11s %11s\n" N iret peak_RSS_B footprint_B slope_RSS slope_foot

CN=""; CRSS=""; CFOOT=""
for n in "$@"; do
    sed "s/@N@/$n/" "$TEMPLATE" > "$OUT/${KIND}_$n.s"
    bestr=0; bestf=0
    for ((r=1; r<=REP; r++)); do
        rss_run $PROC "$OUT/${KIND}_$n.s" "mem_${KIND}_${n}_run$r"
        [ "$RSS" -gt "$bestr" ] && bestr=$RSS
        [ "$FOOT" -gt "$bestf" ] && bestf=$FOOT
    done
    # sanity: did the guest really run ~4N instructions?
    lo=$((4*n)); hi=$((4*n+10))
    if [ "$IRET" -lt "$lo" ] || [ "$IRET" -gt "$hi" ]; then
        echo "WARNING: iret=$IRET but expected $lo..$hi: the program did not do what we think" >&2
    fi
    if [ -z "$CN" ]; then
        CN=$n; CRSS=$bestr; CFOOT=$bestf
        printf "%12d %10d %13d %13d %11s %11s\n" "$n" "$IRET" "$bestr" "$bestf" "(control)" "(control)"
    else
        sr=$(awk -v r=$bestr -v c=$CRSS -v n=$n -v cn=$CN 'BEGIN{printf "%.2f",(r-c)/(n-cn)}')
        sf=$(awk -v r=$bestf -v c=$CFOOT -v n=$n -v cn=$CN 'BEGIN{printf "%.2f",(r-c)/(n-cn)}')
        printf "%12d %10d %13d %13d %11s %11s\n" "$n" "$IRET" "$bestr" "$bestf" "$sr" "$sf"
    fi
done | tee "$OUT/mem_${KIND}.txt"

SL=$(awk 'NF==6 && $5!="(control)" && $5!="slope_RSS"{s=$5} END{print s}' "$OUT/mem_${KIND}.txt")
SF=$(awk 'NF==6 && $6!="(control)" && $6!="slope_foot"{s=$6} END{print s}' "$OUT/mem_${KIND}.txt")
echo
echo "slope (largest region): RSS = $SL, footprint = $SF host bytes per guest byte"
awk -v s="$SL" -v f="$SF" 'BEGIN{b=18405414
  printf "projection for the 18,405,414-byte baseline peak:\n  by RSS slope:       %.0f B = %.2f GiB\n  by footprint slope: %.0f B = %.2f GiB\n", s*b, s*b/1073741824, f*b, f*b/1073741824}' | tee -a "$OUT/mem_${KIND}.txt"
echo "(machine RAM: $(sysctl -n hw.memsize | awk '{printf "%.0f GiB", $1/1073741824}'))"
