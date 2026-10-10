#!/usr/bin/env bash
# Usage: ./build.sh [--jobs N] [--clean] [--static]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
CLEAN=0
STATIC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --static)
      STATIC=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GLIBC_VER=2.17

# terminal entries compiled into ncurses, used when the system terminfo database lacks them.
FALLBACKS=(
  ansi dumb linux vt100 vt220
  xterm xterm-256color xterm-color
  screen screen-256color screen.xterm-256color
  tmux tmux-256color
  rxvt rxvt-256color
  alacritty kitty foot wezterm
)
TERMINFO_DIRS_DEFAULT=/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo:/usr/share/lib/terminfo

OS="$(uname -s)"
ARCH="$(uname -m)"
[ "$ARCH" = arm64 ] && ARCH=aarch64

# iotop reads the taskstats interface of the Linux kernel, so there is no build for other systems.
if [ "$OS" != Linux ]; then
  echo "iotop only runs on Linux" >&2
  exit 1
fi
case "$ARCH" in
  x86_64 | aarch64) ;;
  *)
    echo "unsupported host $OS-$ARCH" >&2
    exit 1
    ;;
esac

SUFFIX=""
[ "$STATIC" = 1 ] && SUFFIX="-static"
WORK="$ROOT_DIR/build$SUFFIX"
PREFIX="$WORK/deps"
HOST="$WORK/host"
DIST="$ROOT_DIR/dist$SUFFIX"

ZIG_TARGET=$ARCH-linux-gnu.$GLIBC_VER
[ "$STATIC" = 1 ] && ZIG_TARGET=$ARCH-linux-musl

MAKE="${MAKE:-$(command -v gmake || command -v make)}"
"$MAKE" --version 2>/dev/null | grep -q 'GNU Make' || {
  echo "GNU make required" >&2
  exit 1
}

export CC="zig cc -target $ZIG_TARGET"
export AR="zig ar"
export RANLIB="zig ranlib"
export LD="zig ld.lld"

if [ "$CLEAN" = 1 ]; then
  echo ">>> cleaning $WORK and $DIST"
  rm -rf "$WORK" "$DIST"
fi
mkdir -p "$WORK/src" "$PREFIX/include" "$PREFIX/lib"

cd "$WORK/src"

prepare() {
  [ -d "$1" ] && return
  if [ ! -f "$ROOT_DIR/vendor/$1/.git" ] && [ ! -d "$ROOT_DIR/vendor/$1/.git" ]; then
    echo "vendor/$1 is missing, run: git submodule update --init --depth 1" >&2
    exit 1
  fi
  echo ">>> preparing $1 ($(git -C "$ROOT_DIR/vendor/$1" describe --tags 2>/dev/null || echo unknown))"
  cp -R "$ROOT_DIR/vendor/$1" "$1"
  rm -rf "$1/.git"
}

prepare ncurses
prepare iotop

NCURSES_COMMON=(
  --without-shared --with-normal --without-debug
  --without-cxx --without-cxx-binding --without-ada
  --without-tests --without-manpages
  --enable-widec --disable-db-install
)

# builds tic and infocmp for the build machine to compile the fallback entries.
if [ ! -x "$HOST/bin/infocmp" ]; then
  echo ">>> ncurses (host tic/infocmp)"
  rm -rf ncurses-host
  cp -R ncurses ncurses-host
  (
    cd ncurses-host
    ./configure --prefix="$HOST" "${NCURSES_COMMON[@]}" --with-progs
    "$MAKE" -j"$JOBS"
    "$MAKE" install.progs
  )
fi

echo ">>> ncurses"
(
  cd ncurses
  [ -f Makefile ] && "$MAKE" distclean >/dev/null 2>&1 || true
  ./configure \
    --prefix="$PREFIX" \
    "${NCURSES_COMMON[@]}" \
    --without-progs --with-termlib \
    --with-default-terminfo-dir=/usr/share/terminfo \
    --with-terminfo-dirs="$TERMINFO_DIRS_DEFAULT" \
    --with-fallbacks="$(
      IFS=,
      echo "${FALLBACKS[*]}"
    )" \
    --with-tic-path="$HOST/bin/tic" \
    --with-infocmp-path="$HOST/bin/infocmp"
  "$MAKE" -j"$JOBS" libs
  "$MAKE" install.libs
)

echo ">>> iotop"
(
  cd iotop
  LDFLAGS="-s"
  [ "$STATIC" = 1 ] && LDFLAGS="-static -s"
  # no LTO, which zig does not do for these targets; the flags of the Makefile otherwise stay
  "$MAKE" -j"$JOBS" NO_FLTO=1 CC="$CC" CFLAGS="-Os -fno-stack-protector" LDFLAGS="$LDFLAGS" \
    NCCC="-I$PREFIX/include -I$PREFIX/include/ncursesw" \
    NCLD="-L$PREFIX/lib -lncursesw -ltinfow"
  rm -rf "$DIST"
  mkdir -p "$DIST/bin" "$DIST/share/man/man8"
  cp iotop "$DIST/bin/iotop"
  cp iotop.8 "$DIST/share/man/man8/iotop.8"
)

IOTOP_BIN="$DIST/bin/iotop"
echo
echo ">>> done: $IOTOP_BIN"
"$IOTOP_BIN" --version
if [ "$STATIC" = 1 ]; then
  # static musl libc embeds the loader path as a string, so check for an interpreter header.
  if readelf -l "$IOTOP_BIN" | grep -q INTERP; then
    echo "WARNING: iotop references a dynamic loader, not fully static" >&2
  else
    echo "fully static"
  fi
elif LC_ALL=C grep -a -q -E 'lib(ncurses|tinfo)[a-z]*\.so' "$IOTOP_BIN"; then
  echo "WARNING: iotop links a dependency dynamically, not only glibc" >&2
else
  echo "only glibc is dynamic"
fi
