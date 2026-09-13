#!/bin/bash
# End-to-end tests for ROOT.sh against the emulated NL5H00X.
# No hardware involved. Run: bash tests/root-tests.sh

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

# No real arm binaries are built in this environment. A sandbox gets its own
# ROOT_ARTIFACT_DIR with stand-in sud/su files plus the REAL root/sud.rc, so
# the test exercises the install/verify path, not whether a particular
# checked-in binary happens to be right.
new_sandbox() {
    sb=$(mktemp -d)
    sandbox_register "$sb"
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run/projector-backup-20260101_000000"
    cp "$sb/state/blockdev" "$sb/run/projector-backup-20260101_000000/full-system-backup.img"
    echo "device_size=$(stat -f%z "$sb/state/blockdev" 2>/dev/null || stat -c%s "$sb/state/blockdev")" \
        > "$sb/run/projector-backup-20260101_000000/backup-manifest.txt"

    mkdir -p "$sb/artifacts"
    printf 'dummy sud daemon binary\n' > "$sb/artifacts/sud"
    # HYBRID-SU marker, distinct from seed.sh's STOCK-SU: fake-adb's
    # su_binary_ok tells the two apart so a live `su 0 id` / `su_new 0 id`
    # can actually simulate the hybrid execing the preserved stock su.
    printf 'HYBRID-SU dummy hybrid su binary\n'  > "$sb/artifacts/su"
    cp "$REPO_ROOT/root/sud.rc" "$sb/artifacts/sud.rc"
}

# Run ROOT.sh in a sandbox. Extra env goes before the command.
root_sh() {
    local sb="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    (
        cd "$sb/run" || exit 1
        PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" ROOT_ARTIFACT_DIR="$sb/artifacts" \
            env ${envs[@]+"${envs[@]}"} \
            bash "$SCRIPTS/ROOT.sh" "$@" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
        echo "RC=${PIPESTATUS[0]}"
    )
}

dev() { # run a command on the emulated device; leading VAR=val become env
    local sb="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" \
        env ${envs[@]+"${envs[@]}"} adb shell "$@" 2>/dev/null | tr -d '\r'
}
reboot_dev() { PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$1/state" adb reboot >/dev/null 2>&1; }

sha256_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$1" | awk '{print $1}'; }
mode_of()   { stat -f%Lp "$1" 2>/dev/null || stat -c%a "$1"; }

# ---------------------------------------------------------------------------
head_ "apply-all installs the daemon, its service and the allow-list"

new_sandbox
out=$(root_sh "$sb" --apply-all --yes)
[[ "$out" == *"RC=0"* ]] && ok "apply-all completes" || { bad "apply-all failed"; echo "$out" | tail -10 | sed 's/^/        /'; }

if [[ -f "$sb/state/system/xbin/sud" ]]; then
    [[ "$(sha256_of "$sb/state/system/xbin/sud")" == "$(sha256_of "$sb/artifacts/sud")" ]] \
        && ok "sud matches the built artifact" || bad "sud on device does not match the artifact"
else
    bad "/system/xbin/sud was not installed"
fi

if [[ -f "$sb/state/system/etc/init/sud.rc" ]]; then
    grep -qx "    seclabel u:r:su:s0" "$sb/state/system/etc/init/sud.rc" \
        && ok "sud.rc carries the default seclabel u:r:su:s0" || bad "sud.rc seclabel is wrong"
else
    bad "/system/etc/init/sud.rc was not installed"
fi

if [[ -f "$sb/state/data/adb/su-allow" ]]; then
    ok "su-allow exists"
    [[ "$(mode_of "$sb/state/data/adb/su-allow")" == "600" ]] \
        && ok "su-allow is mode 600" || bad "su-allow mode is $(mode_of "$sb/state/data/adb/su-allow"), not 600"
    [[ ! -s "$sb/state/data/adb/su-allow" ]] && ok "su-allow starts empty (fail closed)" || bad "su-allow is not empty"
else
    bad "/data/adb/su-allow was not created"
fi

reboot_dev "$sb"
[[ -n "$(dev "$sb" 'pidof sud')" ]] && ok "sud is running after a reboot" || bad "sud did not come up after a reboot"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a seclabel this device's policy does not define means sud never starts"
# Never a brick: init just logs an error and the service does not start, same
# as the real AOSP behaviour root/sud.rc documents.

new_sandbox
out=$(root_sh "$sb" --apply-all --yes --seclabel u:r:bogus:s0)
[[ "$out" == *"RC=0"* ]] && ok "apply-all still completes with an unknown seclabel" || bad "apply-all failed"

reboot_dev "$sb"
[[ -z "$(dev "$sb" 'pidof sud')" ]] && ok "sud does not come up with an unrecognised seclabel" || bad "sud came up anyway"

out=$(root_sh "$sb" --status)
[[ "$out" == *"not running"* ]] && ok "--status reports the daemon as not running" || bad "--status did not flag it"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--with-su installs the hybrid su and keeps the stock one"

new_sandbox
out=$(root_sh "$sb" --apply-all --yes --with-su)
[[ "$out" == *"RC=0"* ]] && ok "apply-all --with-su completes" || { bad "apply-all --with-su failed"; echo "$out" | tail -12 | sed 's/^/        /'; }

[[ -f "$sb/state/system/xbin/su_orig" ]] && ok "the stock su was preserved as su_orig" || bad "su_orig is missing"

if [[ -f "$sb/state/system/xbin/su" ]]; then
    [[ "$(sha256_of "$sb/state/system/xbin/su")" == "$(sha256_of "$sb/artifacts/su")" ]] \
        && ok "su was replaced with the hybrid artifact" || bad "su on device does not match the hybrid artifact"
else
    bad "/system/xbin/su is missing"
fi

[[ "$(dev "$sb" 'su 0 id')" == *"uid=0"* ]] && ok "su 0 id still returns uid=0, with no reboot" || bad "su 0 id broke"
[[ ! -f "$sb/state/system/xbin/su_new" ]] && ok "su_new was cleaned up after promotion" || bad "su_new lingered on device"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--revert removes the daemon and restores the stock su"

new_sandbox
root_sh "$sb" --apply-all --yes --with-su >/dev/null
out=$(root_sh "$sb" --revert --yes)
[[ "$out" == *"RC=0"* ]] && ok "revert completes" || { bad "revert failed"; echo "$out" | tail -10 | sed 's/^/        /'; }

[[ ! -f "$sb/state/system/xbin/sud" ]] && ok "sud was removed" || bad "sud is still there"
[[ ! -f "$sb/state/system/etc/init/sud.rc" ]] && ok "sud.rc was removed" || bad "sud.rc is still there"
# su_orig is the permanent stock copy -- ROOT.sh never deletes it, on apply or
# revert, precisely so a broken live su can always be restored from it.
[[ -f "$sb/state/system/xbin/su_orig" ]] && ok "su_orig was kept as the permanent stock copy" || bad "su_orig was deleted"
[[ "$(cat "$sb/state/system/xbin/su" 2>/dev/null)" == "STOCK-SU stock su placeholder" ]] \
    && ok "su is back to the stock binary" || bad "su was not restored to stock"
[[ "$(sha256_of "$sb/state/system/xbin/su")" == "$(sha256_of "$sb/state/system/xbin/su_orig")" ]] \
    && ok "su hashes match su_orig after revert" || bad "su and su_orig diverge after revert"

reboot_dev "$sb"
[[ -z "$(dev "$sb" 'pidof sud')" ]] && ok "sud does not come back after a reboot post-revert" || bad "sud is still running"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a hybrid that fails live-verify never touches the live su"
# su_orig already present but not actually stock (as if a previous run left it
# broken) makes su_binary_ok's live-verify fail on su_new even though the
# artifact itself carries a valid HYBRID-SU marker -- exactly the case the
# stage-then-live-verify-then-promote ordering exists to catch before the live
# su is ever touched.

new_sandbox
printf 'garbage not stock\n' > "$sb/state/system/xbin/su_orig"
out=$(root_sh "$sb" --apply-all --yes --with-su)
[[ "$out" != *"RC=0"* ]] && ok "su_hybrid_apply fails when live-verify fails" || bad "apply reported success despite a failed live-verify"
[[ "$out" != *"matches the hybrid artifact"* ]] && ok "no su_hybrid success message was printed" || bad "a success message leaked through the failure"
[[ "$(cat "$sb/state/system/xbin/su" 2>/dev/null)" == "STOCK-SU stock su placeholder" ]] \
    && ok "live su is untouched, still stock" || bad "live su was changed despite the failed live-verify"
[[ ! -f "$sb/state/system/xbin/su_new" ]] && ok "su_new was cleaned up after the failed live-verify" || bad "su_new lingered after failure"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "service installed without its binary never comes up as running"
# sud.rc + an accepted seclabel are not enough on their own -- init has
# nothing to exec if the binary itself is gone (e.g. removed out of band).

new_sandbox
root_sh "$sb" --apply-all --yes >/dev/null
rm -f "$sb/state/system/xbin/sud"
reboot_dev "$sb"
[[ -z "$(dev "$sb" 'pidof sud')" ]] && ok "sud is not running after a reboot with the binary missing" || bad "sud came up without its binary"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "guards: wrong device, no backup, --status needs neither"

new_sandbox
sed -i '' 's/^ro.product.model=.*/ro.product.model=SOMETHING_ELSE/' "$sb/state/props" 2>/dev/null || \
    sed -i 's/^ro.product.model=.*/ro.product.model=SOMETHING_ELSE/' "$sb/state/props"
sed -i '' 's/^ro.product.device=.*/ro.product.device=other/' "$sb/state/props" 2>/dev/null || \
    sed -i 's/^ro.product.device=.*/ro.product.device=other/' "$sb/state/props"
out=$(root_sh "$sb" --apply-all --yes)
if [[ "$out" != *"RC=0"* ]] && [[ "$out" == *"Unsupported device"* ]]; then
    ok "refuses hardware it was not written for"
else
    bad "did not refuse an unsupported device"
fi
sandbox_finish "$sb"

new_sandbox
rm -rf "$sb"/run/projector-backup-*
out=$(root_sh "$sb" --apply-all --yes)
if [[ "$out" != *"RC=0"* ]] && [[ "$out" == *"backup"* ]]; then
    ok "refuses to change anything without a verified backup"
else
    bad "ran without a backup"
fi
[[ ! -f "$sb/state/system/xbin/sud" ]] && ok "device untouched after refusal" || bad "device changed despite refusal"

out=$(root_sh "$sb" --status)
[[ "$out" == *"RC=0"* ]] && ok "--status succeeds without a backup" || bad "--status failed without a backup"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "running apply-all twice changes nothing the second time"

new_sandbox
root_sh "$sb" --apply-all --yes >/dev/null
snap1=$(find "$sb/state/system" "$sb/state/data/adb" -type f -exec sha256_of {} \; 2>/dev/null | sort)
out=$(root_sh "$sb" --apply-all --yes)
snap2=$(find "$sb/state/system" "$sb/state/data/adb" -type f -exec sha256_of {} \; 2>/dev/null | sort)

[[ "$out" == *"RC=0"* ]] && ok "second run succeeds" || bad "second run failed"
[[ "$snap1" == "$snap2" ]] && ok "second run left the device identical" || bad "second run changed device state"
[[ "$out" == *"already"* ]] && ok "reports it had nothing to do" || bad "did not report a no-op"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"

child_release_all

[[ "$FAIL" -eq 0 ]]
