#!/usr/bin/env bash
# Usage: ./tests/run_smoke_tests.sh [--static] [--dist DIR]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --static)
      DIST="$ROOT_DIR/dist-static"
      shift
      ;;
    --dist)
      DIST="$(cd "$2" && pwd)"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

IOTOP="$DIST/bin/iotop"

pass() { echo "ok: $*"; }
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

version="$("$IOTOP" --version)"
# prints the command as run, then the version
echo "$version" | grep -Eq ' [0-9]+\.[0-9]+$' || fail "iotop --version: $version"
pass "$version"

# the options and the full-screen mode need the taskstats interface of the kernel, which containers
# often lack, so only the usage output is checked
"$IOTOP" --help 2>&1 | grep -q -i 'usage' || fail "iotop --help"
pass "usage"

if ! LC_ALL=C grep -a -q 'ld-musl' "$IOTOP"; then
  max="$(LC_ALL=C grep -aoh 'GLIBC_2\.[0-9]*' "$IOTOP" | sort -uV | tail -n 1)" || true
  if [ -n "$max" ]; then
    [ "$(printf '%s\n' "$max" GLIBC_2.17 | sort -V | tail -n 1)" = GLIBC_2.17 ] \
      || fail "needs $max, newer than GLIBC_2.17"
    pass "glibc floor ($max)"
  fi
fi

echo "all smoke tests passed"
