#!/usr/bin/env bash
# Native C baseline on this Mac: wall time and peak RSS of ./solver and ./mini.
# Compare with report.md section 4 (solver ~0.065 s / 19.8 MB, mini ~0.51 s / 56.5 MB).
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$CAL_DIR/.."
make -s solver mini
REP=${REP:-5}
echo "== native baseline (max RSS, min wall over $REP runs)"
printf "%-8s %-16s %10s %14s\n" pråog state "min_real_s" "max_RSS_B"
for bin in solver mini; do
  for state in 21345671111111 12345671111111; do
    mn=""; mx=0
    for ((r=1;r<=REP;r++)); do
      o=$( { /usr/bin/time -l ./$bin $state >/dev/null; } 2>&1 )
      t=$(echo "$o" | awk '/ real /{print $1}'); m=$(echo "$o" | awk '/maximum resident/{print $1}')
      if [ -z "$mn" ] || awk -v a="$t" -v b="$mn" 'BEGIN{exit !(a<b)}'; then mn=$t; fi
      [ "$m" -gt "$mx" ] && mx=$m
    done
    printf "%-8s %-16s %10s %14d\n" "$bin" "$state" "$mn" "$mx"
  done
done | tee "$OUT/host_baseline.txt"
