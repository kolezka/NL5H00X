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
head_ "diagnostics reach the operator, not the caller's variable"
# Helpers that return a payload on stdout are called as out=$(helper ...).
# A diagnostic written to stdout is swallowed by that capture and the operator
# sees nothing. This locks the contract for all of them, not just the one
# helper that surfaced it.

probe='source "'"$SCRIPTS"'/lib/common.sh"; SU_MODE=""; out=$(adb_root_exec whoami); echo "CAPTURED:[$out]"'
captured=$(bash -c "$probe" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
on_stderr=$(bash -c "$probe" 2>&1 >/dev/null | sed 's/\x1b\[[0-9;]*m//g')

if [[ "$captured" == "CAPTURED:[]" ]]; then
    ok "helper diagnostic is not captured as the helper's return value"
else
    bad "diagnostic leaked into the caller's variable: $captured"
fi

if [[ "$on_stderr" == *ERROR* ]]; then
    ok "helper diagnostic reaches stderr"
else
    bad "diagnostic went nowhere the operator can see it"
fi

# print_warning moved to stderr in the same commit as print_error but was
# asserted nowhere, so a revert of half the fix would have stayed green.
warn_out=$(bash -c 'source "'"$SCRIPTS"'/lib/common.sh"; print_warning hi' 2>/dev/null)
if [[ -z "$warn_out" ]]; then
    ok "print_warning is on stderr too, not just print_error"
else
    bad "print_warning still writes to stdout: $warn_out"
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

manifest=$(find "$rundir" -name backup-manifest.txt -print -quit)
if grep -q '^method=stream$' "$manifest" 2>/dev/null; then
    ok "streaming is the path taken by default"
else
    bad "expected method=stream, got: $(grep '^method=' "$manifest" 2>/dev/null)"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "a reaped remote dd is retried, not fatal"
# The failure measured on hardware: the remote dd dies partway and the stream
# simply stops. One short block must not cost the whole transfer.

sandbox=$(new_sandbox)
rundir=$(run_backup "$sandbox" env FAKE_ADB_SHORT_STREAM_ONCE=1 STREAM_CHUNK_MB=8)
rc=$(cat "$rundir/rc")
img=$(backup_img "$rundir")

if [[ "$rc" == "0" ]]; then
    ok "run survives a block that comes back short"
else
    bad "exit $rc after a single short block"
fi
if [[ -n "$img" ]] && cmp -s "$img" "$sandbox/state/blockdev"; then
    ok "retried image is byte-identical to the device"
else
    bad "retried image differs from the device"
fi
if grep -q "wanted" "$rundir/log"; then
    ok "the short block is reported, not silently swallowed"
else
    bad "no mention of the short block in the log"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "an interrupted transfer resumes instead of restarting"

sandbox=$(new_sandbox)
bdir="$sandbox/run/projector-backup-20260101_000000"
mkdir -p "$bdir"
# 20 MB of a 40 MB device already pulled, plus a 3 MB partial tail that must
# be discarded rather than trusted.
dd if="$sandbox/state/blockdev" of="$bdir/full-system-backup.img" \
   bs=1048576 count=23 2>/dev/null
rundir=$(run_backup "$sandbox" env STREAM_CHUNK_MB=8)
rc=$(cat "$rundir/rc")
img=$(find "$rundir" -name full-system-backup.img -print -quit)

if grep -qi "partial tail" "$rundir/log"; then
    ok "partial tail past the block boundary is dropped"
else
    bad "partial tail was kept or not reported"
fi
if grep -qi "Resume point verified" "$rundir/log"; then
    ok "resume point is checked against the device, not assumed"
else
    bad "resumed without verifying the existing prefix"
fi
if [[ "$rc" == "0" ]] && cmp -s "$img" "$sandbox/state/blockdev"; then
    ok "resumed image is byte-identical to the device"
else
    bad "resumed image differs (rc=$rc)"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "a resumed prefix that does not match the device is rejected"
# Size alone cannot distinguish a good prefix from a corrupt one, so a
# mismatched carry-over must be refused rather than extended.

sandbox=$(new_sandbox)
bdir="$sandbox/run/projector-backup-20260101_000000"
mkdir -p "$bdir"
dd if=/dev/urandom of="$bdir/full-system-backup.img" bs=1048576 count=16 2>/dev/null
rundir=$(run_backup "$sandbox" env STREAM_CHUNK_MB=8 FAKE_ADB_NO_EXEC_OUT=0)
rc=$(cat "$rundir/rc")

if grep -qi "Resume check FAILED" "$rundir/log"; then
    ok "mismatched prefix is detected and named"
else
    bad "corrupt carry-over was not detected"
fi
# Rejecting the prefix drops it and rebuilds from scratch via the staged path,
# so success here is correct -- what matters is that the corrupt bytes were
# never extended into the final image.
img=$(find "$rundir" -name full-system-backup.img -print -quit)
if [[ -n "$img" ]] && cmp -s "$img" "$sandbox/state/blockdev"; then
    ok "corrupt prefix discarded; final image matches the device"
else
    bad "corrupt bytes survived into the final image"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "device diagnostics cannot pass as image data"
# dd writes a ~95 byte summary to stderr and this device's su merges it into
# stdout. adb_root_stream suppresses it; if a device merges it anyway, the
# image comes back LARGER than the device and must be rejected, not trusted.

sandbox=$(new_sandbox)
rundir=$(run_backup "$sandbox" env FAKE_ADB_FORCE_DD_SUMMARY=1)
rc=$(cat "$rundir/rc")
img=$(backup_img "$rundir")

# Block streaming catches contamination per block, before it ever reaches the
# assembled image -- an earlier and more precise signal than the whole-image
# size check that used to report it.
if grep -qiE "wanted|larger than the device" "$rundir/log"; then
    ok "over-sized block is named at the point it arrives"
else
    bad "contamination not reported"
fi

# Degrading to the staged path is the correct response, not a failure: the
# staged path writes via of=, so the summary never reaches the image. What
# must never happen is the contaminated stream being kept.
if [[ -n "$img" ]] && cmp -s "$img" "$sandbox/state/blockdev"; then
    ok "contaminated stream discarded; final image is byte-identical"
else
    bad "final image is not the device's contents"
fi

manifest=$(find "$rundir" -name backup-manifest.txt -print -quit)
if grep -qE '^method=(chunked|direct)$' "$manifest" 2>/dev/null; then
    ok "manifest records the staged fallback, not the stream that failed"
else
    bad "manifest method wrong: $(grep '^method=' "$manifest" 2>/dev/null)"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "falls back to a staged backup when exec-out is unavailable"

sandbox=$(new_sandbox)
rundir=$(run_backup "$sandbox" env FAKE_ADB_NO_EXEC_OUT=1)
rc=$(cat "$rundir/rc")
img=$(backup_img "$rundir")

if [[ "$rc" == "0" ]]; then
    ok "still completes without exec-out"
else
    bad "exit $rc when exec-out is unavailable"
fi

if [[ -n "$img" ]] && cmp -s "$img" "$sandbox/state/blockdev"; then
    ok "fallback image is byte-identical to the device"
else
    bad "fallback image differs from the device"
fi

manifest=$(find "$rundir" -name backup-manifest.txt -print -quit)
if grep -qE '^method=(chunked|direct)$' "$manifest" 2>/dev/null; then
    ok "manifest records the staged method actually used"
else
    bad "manifest method wrong: $(grep '^method=' "$manifest" 2>/dev/null)"
fi
rm -rf "$sandbox"

# ---------------------------------------------------------------------------
head_ "truncated chunk is caught (the bug this suite exists for)"
# dd silently writes short and reports success. Every chunk comes back
# non-empty, so a size-blind script concatenates them and declares victory.

sandbox=$(new_sandbox)
# Chunk 0 lands intact; chunk 1 (skip=15) comes back short. exec-out is
# disabled so the run actually reaches the chunked path under test.
rundir=$(run_backup "$sandbox" env \
    FAKE_ADB_NO_EXEC_OUT=1 \
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
