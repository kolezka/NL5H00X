#!/bin/bash
# Tests for the RESTORE.sh and reset-launcher.sh that MAKE_BACKUP.sh generates,
# run against the fake device. No hardware involved. Run: bash tests/restore-tests.sh
#
# The contract under test: a restore step that fails must say so and exit
# non-zero, never print a success line. The fake intercepts every block write,
# so no scenario here can change a device even if the script is wrong.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/local/lifecycle.sh"
source "$TEST_DIR/local/sandboxes.sh"
FAKE_ADB_DIR=${PT_FAKE_ADB_CANONICAL:-"$TEST_DIR/fake-adb/adb"}
FAKE_ADB_DIR=${FAKE_ADB_DIR%/*}
SCRIPTS="${TOOLKIT_SCRIPTS:-$REPO_ROOT/scripts}"

PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()   { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); sandbox_fail; }
head_() { echo; echo "=== $1 ==="; }

# One generated backup directory, produced by a real MAKE_BACKUP.sh run against
# the fake device, copied fresh for every scenario so no case sees another's
# leftovers.
PRISTINE=""
generate_once() {
    local sb; sb=$(mktemp -d); sandbox_register "$sb"
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run"
    ( cd "$sb/run" && PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" \
        FAKE_ADB_SU_MODE=direct FAKE_ADB_PROPAGATE_RC=1 \
        BACKUP_DIR="$sb/run/generated" STREAM_CHUNK_MB=1 STREAM_STALL_SECS=3 STREAM_RETRIES=1 \
        bash "$SCRIPTS/MAKE_BACKUP.sh" > "$sb/generate.log" 2>&1 )
    [[ -f "$sb/run/generated/RESTORE.sh" ]] || { echo "MAKE_BACKUP did not produce RESTORE.sh; see $sb/generate.log"; exit 2; }
    PRISTINE="$sb/run/generated"
}

# A scenario: fresh device state, fresh copy of the generated directory, block
# writes intercepted. Extra env goes before the option.
new_case() {
    cs=$(mktemp -d); sandbox_register "$cs"
    bash "$TEST_DIR/device-emu/seed.sh" "$cs/state" >/dev/null
    cp -R "$PRISTINE" "$cs/backup"
    mkdir -p "$cs/state/dev/block"
    printf 'whole target marker\n' > "$cs/state/dev/block/mmcblk0"
    printf 'partition target marker\n' > "$cs/state/dev/block/mmcblk0p20"
}

# restore CASE_DIR [VAR=val ...] OPTION
# Feeds the option and the RESTORE confirmation on stdin. Output and exit code
# land in $cs/out and $cs/rc.
restore() {
    local cs="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    local option="$1"
    (
        cd "$cs/backup" || exit 1
        printf '%s\nRESTORE\n' "$option" | \
        PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$cs/state" \
            FAKE_ADB_SU_MODE=direct FAKE_ADB_PROPAGATE_RC=1 FAKE_ADB_INTERCEPT_BLOCK_DD=1 \
            env ${envs[@]+"${envs[@]}"} \
            bash ./RESTORE.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$cs/out"
        echo "${PIPESTATUS[1]}" > "$cs/rc"
    )
}

generate_once

# ---------------------------------------------------------------------------
head_ "option 1: a launcher reset that the device rejects is reported as a failure"
# The saved component names a package the device has disabled, so
# set-home-activity answers an error. The script must not print success.
new_case
printf 'com.newlink.hisilauncher/.WizardAciticity\n' > "$cs/backup/current-home-activity.txt"
printf 'com.newlink.hisilauncher\n' > "$cs/state/packages_disabled"
restore "$cs" 1
grep -q '^Launcher reset$' "$cs/out" && bad "prints 'Launcher reset' after set-home-activity failed" || ok "no success line"
[[ "$(cat "$cs/rc")" != 0 ]] && ok "exits non-zero" || bad "exited 0 after a failed launcher reset"

head_ "option 1: a saved diagnostic instead of a component is not forwarded to the device"
# An old MAKE_BACKUP recorded the text of a failed query in this file.
new_case
printf 'Unknown command: get-home-activity\n' > "$cs/backup/current-home-activity.txt"
restore "$cs" 1
grep -q 'get-home-activity' "$cs/state/invocations.log" && bad "forwarded the diagnostic text as a component" || ok "diagnostic text not sent to the device"

# ---------------------------------------------------------------------------
head_ "option 2: an adb restore that fails is reported as a failure, not as a missing file"
new_case
restore "$cs" FAKE_ADB_RESTORE_RC=7 2
grep -q 'No app backup found' "$cs/out" && bad "masks a restore failure as a missing file" || ok "does not claim the file is missing"
[[ "$(cat "$cs/rc")" != 0 ]] && ok "exits non-zero" || bad "exited 0 after adb restore returned 7"

# ---------------------------------------------------------------------------
head_ "option 3: a system image of the wrong size is refused before any write"
new_case
head -c 4096 "$cs/backup/full-system-backup.img" > "$cs/backup/system.img"
restore "$cs" 3
[[ ! -e "$cs/state/block-dd.log" ]] && ok "no block dd issued" || bad "issued a block dd for a 4096-byte image"
grep -q 'System partition restored' "$cs/out" && bad "claims the partition was restored" || ok "no success line"
[[ "$(cat "$cs/rc")" != 0 ]] && ok "exits non-zero" || bad "exited 0 after refusing nothing"

# ---------------------------------------------------------------------------
head_ "option 3: a dd that fails on the device is reported as a failure"
new_case
# Right size: the fake's partition is the whole fixture, so use the full image.
cp "$cs/backup/full-system-backup.img" "$cs/backup/system.img"
restore "$cs" FAKE_ADB_INTERCEPT_DD_RC=23 3
grep -q 'System partition restored' "$cs/out" && bad "claims the partition was restored after dd rc 23" || ok "no success line"
[[ "$(cat "$cs/rc")" != 0 ]] && ok "exits non-zero" || bad "exited 0 after dd failed"

# ---------------------------------------------------------------------------
head_ "option 4: a push that succeeds must be followed by a block write before reboot"
new_case
restore "$cs" 4
[[ -e "$cs/state/block-dd.log" ]] && ok "a block dd was issued" || bad "rebooted without any restore write"
grep -q 'of=/dev/block/mmcblk0 ' "$cs/state/block-dd.log" 2>/dev/null && ok "dd targets the whole device" || bad "no whole-device dd recorded"

# ---------------------------------------------------------------------------
head_ "option 4: a streamed restore whose dd fails must not reboot"
new_case
restore "$cs" FAKE_ADB_PUSH_FAIL_TARGET=/sdcard/ FAKE_ADB_PUSH_FAIL_RC=19 FAKE_ADB_INTERCEPT_DD_RC=5 4
[[ "$(cat "$cs/state/reboots")" == 0 ]] && ok "no reboot" || bad "rebooted after the streamed dd failed"
[[ "$(cat "$cs/rc")" != 0 ]] && ok "exits non-zero" || bad "exited 0 after the streamed dd failed"

# ---------------------------------------------------------------------------
head_ "option 4: reboot happens only after the write reported success"
# Positive control for the reboot assertion above: with a successful dd the
# script does reboot, so a reboot counter stuck at 0 would be a broken probe.
new_case
restore "$cs" 4
[[ "$(cat "$cs/state/reboots")" == 1 ]] && ok "rebooted after a successful write" || bad "did not reboot after a successful write (reboot probe or script broken)"

echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]]
