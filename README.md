# iotop-static

Portable builds of [iotop-c](https://github.com/Tomas-M/iotop), the C implementation of `iotop`
that shows the I/O of processes, with ncurses linked in statically, built with
[zig](https://ziglang.org) as the C toolchain.

- Linux glibc: only glibc is linked dynamically, and only symbols up to glibc 2.17, so the
  binaries run on anything from CentOS 7 onwards
- Linux musl (`--static`): fully static, no runtime dependencies at all (e.g. Alpine)

iotop reads the taskstats interface of the Linux kernel, so there is no build for macOS. It
needs root or the `CAP_NET_ADMIN` capability, and a kernel with `CONFIG_TASK_DELAY_ACCT` (and
`kernel.task_delayacct=1` where it is a sysctl).

Common terminal descriptions (xterm, xterm-256color, screen, screen-256color, tmux, tmux-256color,
linux, vt100, vt220, rxvt, alacritty, kitty, foot, wezterm, ...) are compiled into ncurses, so
iotop works even on systems without a terminfo database. The system database is still used
first, from `/etc/terminfo`, `/lib/terminfo`, `/usr/share/terminfo`, and `/usr/lib/terminfo`, or
from `$TERMINFO`, `$TERMINFO_DIRS`, and `~/.terminfo`.

## Prerequisites

- `zig`, GNU make, `perl`, `git`

## Installation

Clone the repo with submodules (shallow, the history of the vendored projects is not needed):

```shell
git clone --recurse-submodules --shallow-submodules https://github.com/zshsetup/iotop-static
cd iotop-static
```

## Usage

```shell
./build.sh
```

This builds ncurses from `vendor/` as static libraries, then builds iotop against them. Output is
installed under `dist/`:

- `dist/bin/iotop`: the binary; copy it anywhere on your `PATH`
- `dist/share/man/man8/iotop.8`: the man page

Pass `--static` for the fully static musl build (output in `dist-static/`), `--clean` to remove
previous build output first, and `--jobs N` to control parallelism.

To run the smoke tests against the build:

```shell
./tests/run_smoke_tests.sh            # dist/
./tests/run_smoke_tests.sh --static   # dist-static/
```

## Releases

Publishing a GitHub release tagged with the iotop version (e.g. `v1.31`, matching the tag checked
out in `vendor/iotop`) builds and attaches `iotop-static-<platform>.tar.gz` for `linux-amd64`,
`linux-arm64`, `linux-musl-amd64`, and `linux-musl-arm64`, together with the sources they were
built from (`iotop-static-sources.tar.gz`).

To update a vendored project, check out a new release tag in its submodule and commit it, e.g.
`git -C vendor/iotop fetch --depth 1 origin tag v1.32 && git -C vendor/iotop checkout v1.32`.

## Acknowledgments

This repository builds and vendors the following upstream projects, unmodified, as git
submodules under `vendor/`. Credit goes to their respective authors:

- [iotop-c](https://github.com/Tomas-M/iotop) by Vyacheslav Trushkin, Boian Bonev, and
  contributors
- [ncurses](https://invisible-island.net/ncurses/) by Thomas E. Dickey and the Free Software
  Foundation

## License

MIT for the code in this repository. See `NOTICE` for the licenses of the upstream projects and the
resulting binaries, which are GPL-2.0-or-later (iotop).
