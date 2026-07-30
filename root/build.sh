#!/bin/bash
# Build the root-daemon PoC for the NL5H00X (armeabi-v7a).
#
# Needs an Android NDK. Point NDK at it, or let this find the newest one under
# the default SDK location. Outputs sud, suc and privtest next to the sources.
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

for src in sud suc privtest; do
    "$CC" -O2 -Wall -Wextra -fPIE -pie -o "$HERE/$src" "$HERE/$src.c"
    echo "built $src"
done

file "$HERE"/sud "$HERE"/suc "$HERE"/privtest 2>/dev/null || true
