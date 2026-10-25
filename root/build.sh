#!/bin/bash
# Build the root-daemon PoC for the NL5H00X (armeabi-v7a).
#
# Needs an Android NDK. Point NDK at it, or let this find the newest one under
# the default SDK location. Outputs sud, suc, su and privtest next to the sources.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NDK="${NDK:-}"
if [[ -z "$NDK" ]]; then
    NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/* 2>/dev/null | sort -V | tail -1 || true)
    [[ -z "$NDK" ]] && NDK=$(ls -d "$HOME/Android/Sdk/ndk"/* 2>/dev/null | sort -V | tail -1 || true)
fi
[[ -n "$NDK" && -d "$NDK" ]] || { echo "Set NDK to an Android NDK path" >&2; exit 1; }

HOST=$(uname | tr '[:upper:]' '[:lower:]')-x86_64
CC="$NDK/toolchains/llvm/prebuilt/$HOST/bin/armv7a-linux-androideabi28-clang"
[[ -x "$CC" ]] || { echo "No armeabi-v7a clang at $CC" >&2; exit 1; }

for src in sud privtest; do
    "$CC" -O2 -Wall -Wextra -fPIE -pie -o "$HERE/$src" "$HERE/$src.c"
    echo "built $src"
done

# suc and su both need the shared client wire protocol.
for src in suc su; do
    "$CC" -O2 -Wall -Wextra -fPIE -pie -o "$HERE/$src" "$HERE/$src.c" "$HERE/suclient.c"
    echo "built $src"
done

# sudcheck is the device-side probe tools/device/sud-check.sh pushes. It keeps
# its source under tools/device/ so the tools sit together.
if [[ -f "$HERE/../tools/device/sudcheck.c" ]]; then
    "$CC" -O2 -Wall -Wextra -fPIE -pie -o "$HERE/sudcheck" "$HERE/../tools/device/sudcheck.c"
    echo "built sudcheck"
fi

# sudprobe is the compiled fd lister the device check reads; the suite builds
# it from the same source.
if [[ -f "$HERE/../tests/sud/sudprobe.c" ]]; then
    "$CC" -O2 -Wall -Wextra -D_GNU_SOURCE -fPIE -pie -o "$HERE/sudprobe" "$HERE/../tests/sud/sudprobe.c"
    echo "built sudprobe"
fi

file "$HERE"/sud "$HERE"/suc "$HERE"/su "$HERE"/privtest 2>/dev/null || true
