#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
binary="${TMPDIR:-/tmp}/projector-uart-console-core-tests"

/usr/bin/clang++ -std=c++17 -Wall -Wextra -Werror \
  "$repo_root/firmware/test/portable/test_console_core.cpp" -o "$binary"
"$binary"
