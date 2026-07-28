#!/bin/bash
# Regression tests for the toolkit, run against the fake-adb stand-in device.
# No hardware required.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
# Overridable so the suite can be pointed at an older checkout to confirm it
# actually goes red on the behaviour it is guarding against.
SCRIPTS="${TOOLKIT_SCRIPTS:-$REPO_ROOT/scripts}"

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "=== $1 ==="; }

# Small stand-in device: 40 MB in 15 MB chunks -> 3 chunks, the last one a
# legitimately short 10 MB. Same arithmetic as 7.65 GB / 3000 MB, 200x faster.
DEV_SIZE_MB=40
CHUNK_MB=15

new_sandbox() {
    local sandbox
    sandbox=$(mktemp -d)
    mkdir -p "$sandbox/state/sdcard"
    dd if=/dev/urandom of="$sandbox/state/blockdev" \
        bs=1048576 count="$DEV_SIZE_MB" 2>/dev/null
    echo "$sandbox"
}

# Run MAKE_BACKUP.sh against the fake device. Echoes the run directory; the
# script's exit status is written to <rundir>/rc and its output to <rundir>/log.
run_backup() {
    local sandbox="$1"; shift
    local rundir="$sandbox/run"
    mkdir -p "$rundir"

    (
        cd "$rundir" || exit 1
        PATH="$TEST_DIR/fake-adb:$PATH" \
        FAKE_ADB_STATE="$sandbox/state" \
        CHUNK_SIZE_MB="$CHUNK_MB" \
        "$@" \
        bash "$SCRIPTS/MAKE_BACKUP.sh" > "$rundir/log" 2>&1
        echo $? > "$rundir/rc"
    )
    echo "$rundir"
}

backup_img() {
    local rundir="$1"
    local f
    f=$(find "$rundir" -name full-system-backup.img -print -quit 2>/dev/null)
    echo "$f"
}

file_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
head_ "common.sh loads under set -u"
# Guards against the regression where a bare $_COMMON_SH_LOADED aborts every
# entry script at source time.

# Sentinel must not be a substring of any identifier in common.sh -- an earlier
# version of this test used "LOADED" and matched the _COMMON_SH_LOADED in the
# very error message it was supposed to catch.
out=$(bash -c 'set -euo pipefail; source "'"$SCRIPTS"'/lib/common.sh"; echo __SRC_OK__' 2>&1)
if [[ "$out" == *__SRC_OK__* ]]; then
    ok "common.sh sources cleanly under set -euo pipefail"
else
    bad "common.sh failed to source: $out"
fi

out=$(bash -c 'set -euo pipefail
source "'"$SCRIPTS"'/lib/common.sh"
source "'"$SCRIPTS"'/lib/common.sh"
echo __TWICE_OK__' 2>&1)
if [[ "$out" == *__TWICE_OK__* ]]; then
    ok "double-sourcing is still a no-op (readonly block not re-run)"
else
    bad "double-sourcing broke: $out"
fi

# ---------------------------------------------------------------------------
head_ "healthy device produces a complete backup"

sandbox=$(new_sandbox)
rundir=$(run_backup "$sandbox")
rc=$(cat "$rundir/rc")
img=$(backup_img "$rundir")

if [[ "$rc" == "0" ]]; then
    ok "exit status 0 on a healthy device"
else
    bad "exit status $rc on a healthy device"
    sed -n '$p;/ERROR/p' "$rundir/log" | head -5 | sed 's/^/        /'
fi

if [[ -n "$img" ]]; then
    got=$(file_size "$img")
    want=$((DEV_SIZE_MB * 1048576))
    if [[ "$got" == "$want" ]]; then
        ok "image is exactly device size ($want bytes)"
    else
        bad "image is $got bytes, expected $want"
    fi
    if cmp -s "$img" "$sandbox/state/blockdev"; then
        ok "image is byte-identical to the device"
    else
        bad "image differs from the device"
    fi
else
    bad "no full-system-backup.img produced"
fi

if grep -q "BACKUP COMPLETE" "$rundir/log"; then
    ok "reports BACKUP COMPLETE"
else
    bad "did not report BACKUP COMPLETE"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "truncated chunk is caught (the bug this suite exists for)"
# dd silently writes short and reports success. Every chunk comes back
# non-empty, so a size-blind script concatenates them and declares victory.

sandbox=$(new_sandbox)
# Chunk 0 lands intact; chunk 1 (skip=15) comes back short.
rundir=$(run_backup "$sandbox" env \
    FAKE_ADB_TRUNCATE_AT=$((5 * 1048576)) \
    FAKE_ADB_TRUNCATE_MIN_SKIP="$CHUNK_MB")
rc=$(cat "$rundir/rc")
img=$(backup_img "$rundir")

if [[ "$rc" != "0" ]]; then
    ok "exits non-zero when chunks come back short"
else
    bad "exited 0 despite a truncated backup"
fi

if grep -q "BACKUP COMPLETE" "$rundir/log"; then
    bad "printed 'BACKUP COMPLETE' over a truncated image -- unsafe to proceed"
else
    ok "did not print BACKUP COMPLETE"
fi

if [[ -z "$img" ]]; then
    ok "no image left behind claiming to be a backup"
elif [[ "$(file_size "$img")" != "$((DEV_SIZE_MB * 1048576))" ]]; then
    ok "short image ($(file_size "$img") bytes) is not passed off as complete"
else
    bad "truncated image somehow matches device size"
fi

if find "$rundir" -name 'backup_chunk_*.img' -print -quit | grep -q .; then
    ok "chunk files kept as evidence after a failed run"
else
    bad "chunk files deleted despite the failure"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "require_backup rejects a truncated image"
# The gate UNLOCK.sh depends on. A short image must not satisfy it.

sandbox=$(mktemp -d)
(
    cd "$sandbox" || exit 1
    mkdir -p projector-backup-20260727_000000
    # 2 GB image, well over the old hardcoded 1 GB floor, but the manifest
    # says the device is 7.65 GB.
    dd if=/dev/zero of=projector-backup-20260727_000000/full-system-backup.img \
        bs=1048576 count=1 seek=2047 2>/dev/null
    echo "device_size=8213084160" > projector-backup-20260727_000000/backup-manifest.txt
)

out=$(cd "$sandbox" && bash -c '
set -uo pipefail
source "'"$SCRIPTS"'/lib/common.sh"
require_backup' 2>&1)
rc=$?
if [[ "$rc" != "0" ]]; then
    ok "require_backup rejects an image smaller than the manifest"
else
    bad "require_backup accepted a truncated image (exit 0)"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "remote failure is not mistaken for success"
# adb returns 0 regardless; the real status has to come back another way.

sandbox=$(new_sandbox)
rundir=$(run_backup "$sandbox" env FAKE_ADB_SU_MODE=none)
rc=$(cat "$rundir/rc")

if [[ "$rc" != "0" ]]; then
    ok "exits non-zero when root is unavailable"
else
    bad "exited 0 with no working su"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]]
