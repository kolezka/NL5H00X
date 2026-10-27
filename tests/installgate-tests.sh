#!/bin/bash
# Install-gate tests against the emulated projector only.
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
head_() { SCENARIO="$1"; echo; echo "=== $1 ==="; }

new_sandbox() {
    sb=$(mktemp -d)
    sandbox_register "$sb"
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run/projector-backup-20260101_000000"
    cp "$sb/state/blockdev" "$sb/run/projector-backup-20260101_000000/full-system-backup.img"
    echo "device_size=$(stat -f%z "$sb/state/blockdev" 2>/dev/null || stat -c%s "$sb/state/blockdev")" \
        > "$sb/run/projector-backup-20260101_000000/backup-manifest.txt"
    cp "$sb/state/system/build.prop" "$sb/seed-build.prop"
}
strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }
gate() {
    local sb="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    (
        cd "$sb/run" || exit 1
        PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" \
            env ${envs[@]+"${envs[@]}"} /bin/bash "$SCRIPTS/INSTALL_GATE.sh" "$@" </dev/null 2>&1 | strip_ansi
        echo "RC=${PIPESTATUS[0]}"
    )
}
dev() { PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$1/state" adb shell "$2" 2>/dev/null | tr -d '\r\n'; }
reboot_dev() { PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$1/state" adb reboot >/dev/null 2>&1; }
sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

head_ "status and apply on a stock projector"
new_sandbox
out=$(gate "$sb" status)
[[ "$out" == *"RC=0"* ]] && echo "$out" | grep -qE '^  \[todo\] +install_gate +[^[:space:]]' \
    && ok "status reports install_gate as todo and exits 0" || bad "stock status did not report todo"
[[ "$(dev "$sb" 'getprop zyzys.install.whitelist')" == "" ]] \
    && ok "property is absent before changing build.prop" || bad "stock property is present"
out=$(gate "$sb" off --yes)
[[ "$out" == *"RC=0"* ]] && ok "off completes" || bad "off did not complete"
[[ $(grep -xc 'zyzys.install.whitelist=0' "$sb/state/system/build.prop" 2>/dev/null) == 1 ]] \
    && ok "off writes exactly one disabling line" || bad "off did not write the exact line once"
backup="$sb/state/data/local/tmp/build.prop.orig"
record="$backup.sha256"
[[ -f "$backup" && -f "$record" && "$(tr -d ' \r\n' < "$record")" == "$(sha256_of "$backup")" ]] \
    && ok "backup has a matching recorded sha256" || bad "backup or its sha256 is missing or wrong"
[[ "$(cat "$sb/state/mount_system")" == ro ]] \
    && ok "off restores the read-only mount" || bad "off left the system writable"
[[ "$out" == *"takes effect after a restart: adb reboot"* ]] \
    && ok "off prints the reboot note" || bad "off did not print the reboot note"
[[ "$(dev "$sb" 'getprop zyzys.install.whitelist')" == "" ]] \
    && ok "property does not change before reboot" || bad "property changed before reboot"
reboot_dev "$sb"
[[ "$(dev "$sb" 'getprop zyzys.install.whitelist')" == 0 ]] \
    && ok "property becomes zero after reboot" || bad "property was not loaded on reboot"
out=$(gate "$sb" on --yes)
[[ "$out" == *"RC=0"* ]] && ok "on completes" || bad "on did not complete"
cmp -s "$sb/seed-build.prop" "$sb/state/system/build.prop" \
    && ok "on restores build.prop byte for byte" || bad "on did not restore original bytes"
[[ "$(cat "$sb/state/mount_system")" == ro ]] \
    && ok "on restores the read-only mount" || bad "on left the system writable"
sandbox_finish "$sb"

head_ "off requires confirmation"
new_sandbox
out=$(gate "$sb" off)
[[ "$out" == *"RC=0"* && "$out" == *"Cancelled"* \
    && "$out" == *"This lets every app on the projector install other apps, not only the launcher."* \
    && "$out" == *"It changes /system/build.prop and takes effect after a restart: adb reboot"* ]] \
    && ok "off warns and cancels on closed stdin" || bad "off did not warn and cancel"
cmp -s "$sb/seed-build.prop" "$sb/state/system/build.prop" \
    && ok "cancelled off leaves build.prop unchanged" || bad "cancelled off changed build.prop"
sandbox_finish "$sb"

head_ "on never rolls back a build.prop change made after the backup"
new_sandbox
gate "$sb" off --yes >/dev/null
gate "$sb" on --yes >/dev/null
# An update or a hand edit lands after the first cycle; the old backup stays.
printf '%s\n' 'ro.build.fingerprint=POST-OTA' >> "$sb/state/system/build.prop"
cp "$sb/state/system/build.prop" "$sb/post-edit.prop"
gate "$sb" off --yes >/dev/null
out=$(gate "$sb" on --yes)
[[ "$out" == *"RC=0"* ]] && ok "second on completes" || bad "second on did not complete"
cmp -s "$sb/post-edit.prop" "$sb/state/system/build.prop" \
    && ok "second on keeps the later edit and drops only the whitelist line" \
    || bad "second on restored a stale backup over a later edit"
[[ "$out" == *"differs from the live build.prop"* ]] \
    && ok "second on says why it did not use the backup" || bad "second on gave no reason for skipping the backup"
[[ "$(cat "$sb/state/mount_system")" == ro ]] \
    && ok "second on restores the read-only mount" || bad "second on left the system writable"
sandbox_finish "$sb"

head_ "unreadable mount state after remount is a failure"
new_sandbox
out=$(gate "$sb" FAKE_ADB_MOUNTS_UNREADABLE=1 off --yes)
[[ "$out" == *"RC=1"* && "$out" == *"Could not read the mount state"* ]] \
    && ok "off refuses to claim success without read-only proof" || bad "off did not report unreadable read-only state"
sandbox_finish "$sb"

echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
child_release_all
[[ "$FAIL" -eq 0 ]]
