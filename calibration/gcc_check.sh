#!/usr/bin/env bash
# Records versions for the "Fork and versions" section -> results/versions.txt
set -u
. "$(dirname "$0")/env.sh" || exit 1
{
  echo "date: $(date -u +%FT%TZ)"
  echo "machine: $(uname -m), macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.memsize | awk '{printf "%.0f GiB RAM", $1/1073741824}')"
  echo "ripes binary: $RIPES"
  echo "ripes source commit: $(git -C "$RIPES_SRC" rev-parse --short HEAD) ($(git -C "$RIPES_SRC" describe --tags 2>/dev/null))"
  echo "ripes build type: $(awk -F= '/^CMAKE_BUILD_TYPE:/{print $2}' "$RIPES_SRC/build/CMakeCache.txt") ($(awk -F= '/^CMAKE_CXX_FLAGS_RELEASE:/{print $2}' "$RIPES_SRC/build/CMakeCache.txt"))"
  echo "ripes processors: $("$RIPES" --help 2>&1 | grep -o 'RV32_[A-Z0-9_]*' | sort -u | tr '\n' ' ')"
  echo "minirubik commit: $(git -C "$CAL_DIR/.." rev-parse --short HEAD)   upstream base: 231796c"
  for g in riscv64-elf-gcc riscv64-unknown-elf-gcc riscv32-unknown-elf-gcc; do
    command -v $g >/dev/null && echo "$g: $($g --version | head -1)"
  done
  echo "host cc: $(cc --version | head -1)"
} | tee "$OUT/versions.txt"
