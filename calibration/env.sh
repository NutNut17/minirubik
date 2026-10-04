# Source me:  . ./env.sh
# Uses the Ripes you built yourself in  hw1/Ripes/build  (override: RIPES_BIN=/path/to/Ripes).
# A stale exported $RIPES in your shell is deliberately ignored.
CAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HW1="$(cd "$CAL_DIR/../.." && pwd)"
export RIPES="${RIPES_BIN:-$HW1/Ripes/build/Ripes.app/Contents/MacOS/Ripes}"
export RIPES_SRC="$HW1/Ripes"
export OUT="$CAL_DIR/results"
export CAL_DIR
mkdir -p "$OUT/raw"

# Fail loudly instead of producing empty results.
if [ ! -x "$RIPES" ]; then
    echo "ERROR: Ripes binary not found/executable: $RIPES" >&2
    echo "       Build it:  cd $RIPES_SRC && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \\" >&2
    echo "                    -DCMAKE_PREFIX_PATH=\"\$(brew --prefix qt)\" && cmake --build build -j" >&2
    return 1 2>/dev/null || exit 1
fi
if ! "$RIPES" --help 2>&1 | grep -q RV32_ISS; then
    echo "ERROR: this Ripes build has no RV32_ISS processor (hw2.md requires it)." >&2
    return 1 2>/dev/null || exit 1
fi

# --- helpers -----------------------------------------------------------------
# ripes_run PROC FILE.s TAG  -> sets IRET (retired instrs) and MS (model exec time, ms)
# The complete Ripes output is saved to results/raw/TAG.txt so you can read it.
ripes_run() {
    local proc=$1 src=$2 tag=$3 raw="$OUT/raw/$3.txt"
    "$RIPES" --mode cli --src "$src" -t asm --proc "$proc" \
        --iret --cycles --exectime --timeout 3600000 >"$raw" 2>&1 || true
    IRET=$(awk '/^===== instructions retired/{getline; print $1}' "$raw")
    MS=$(awk '/execution time/{getline; print $1}' "$raw")
    case "$IRET$MS" in *[!0-9]*|"")
        echo "ERROR: could not read results for $tag. Ripes said:" >&2
        sed 's/^/    | /' "$raw" >&2
        return 1;;
    esac
}

# rss_run PROC FILE.s TAG -> sets RSS (peak resident set size, bytes), FOOT (macOS
# "peak memory footprint", bytes) and IRET. macOS /usr/bin/time -l prints both numbers.
# RSS counts resident pages incl. shared libraries; footprint counts memory the process
# itself owns. They differ by a large fixed amount but should have the SAME slope.
rss_run() {
    local proc=$1 src=$2 tag=$3 raw="$OUT/raw/$3.txt"
    /usr/bin/time -l "$RIPES" --mode cli --src "$src" -t asm --proc "$proc" \
        --iret --timeout 3600000 >"$raw" 2>&1 || true
    RSS=$(awk '/maximum resident set size/{print $1}' "$raw")
    FOOT=$(awk '/peak memory footprint/{print $1}' "$raw")
    IRET=$(awk '/^===== instructions retired/{getline; print $1}' "$raw")
    case "$RSS$FOOT$IRET" in *[!0-9]*|"")
        echo "ERROR: could not read results for $tag. Ripes said:" >&2
        sed 's/^/    | /' "$raw" >&2
        return 1;;
    esac
}
