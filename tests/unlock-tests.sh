#!/bin/bash
# End-to-end tests for UNLOCK.sh against the emulated NL5H00X.
# No hardware involved. Run: bash tests/unlock-tests.sh

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
SCRIPTS="${TOOLKIT_SCRIPTS:-$REPO_ROOT/scripts}"

PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()   { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "=== $1 ==="; }

# A sandbox is an emulated device plus a working directory that already holds a
# verified backup, since UNLOCK.sh refuses to run without one.
new_sandbox() {
    local sb; sb=$(mktemp -d)
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run/projector-backup-20260101_000000"
    cp "$sb/state/blockdev" "$sb/run/projector-backup-20260101_000000/full-system-backup.img"
    echo "device_size=$(stat -f%z "$sb/state/blockdev" 2>/dev/null || stat -c%s "$sb/state/blockdev")" \
        > "$sb/run/projector-backup-20260101_000000/backup-manifest.txt"
    # A stand-in for the shipped launcher APK. The suite stays hermetic this
    # way: it tests the install path, not whether a particular binary happens
    # to be committed. The .meta sidecar is how fake-adb learns what is inside.
    mkdir -p "$sb/apks"
    echo "not a real apk" > "$sb/apks/projectivy-launcher-4.71.apk"
    cat > "$sb/apks/projectivy-launcher-4.71.apk.meta" <<EOF
pkg=$PROJECTIVY
home=$PROJECTIVY/com.spocky.projengmenu.ui.home.MainActivity
EOF
    echo "$sb"
}

# Run UNLOCK.sh in a sandbox. Extra env goes before the command.
unlock() {
    local sb="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    (
        cd "$sb/run" || exit 1
        # stdin from /dev/null: a version that stops to ask a question must fail
        # the test rather than hang it.
        # `env` is not decoration. A VAR=val word that arrives from an
        # expansion is not treated as an assignment -- bash decides that before
        # expanding -- so "${envs[@]}" in prefix position ran the variable as a
        # command and returned 127. Tests then read that 127 as the script
        # failing and passed while proving nothing.
        PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" APK_DIR="$sb/apks" \
            env "${envs[@]}" \
            bash "$SCRIPTS/UNLOCK.sh" "$@" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
        echo "RC=${PIPESTATUS[0]}"
    )
}

dev() { # run a command on the emulated device
    local sb="$1"; shift
    PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" adb shell "$@" 2>/dev/null | tr -d '\r'
}
home_now() { tr -d '\r\n' < "$1/state/home_activity"; }
reboot_dev() { PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$1/state" adb reboot >/dev/null 2>&1; }

STOCK=com.newlink.hisilauncher
NOVA=com.teslacoilsw.launcher
PROJECTIVY=com.spocky.projengmenu

# ---------------------------------------------------------------------------
head_ "the device starts locked, exactly as the real one does"

sb=$(new_sandbox)
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen is the stock launcher" || bad "unexpected home: $home"

# Nova is already in /system/app on the real device and it changes nothing --
# the whole point of the unlock is that presence is not enough.
if dev "$sb" 'pm list packages -f' | grep -q "=$NOVA$"; then
    ok "Nova is already present yet the device is still locked"
else
    bad "seed does not match the real device (Nova missing)"
fi

# Sharper version of the same point: Nova does not merely exist, it registers a
# home activity, and the device still will not use it.
if dev "$sb" 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME' | grep -q "$NOVA"; then
    ok "an alternative home activity is already registered and still unused"
else
    bad "seed does not register Nova as a home activity"
fi
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "--status changes nothing and needs no backup"

sb=$(new_sandbox)
rm -rf "$sb"/run/projector-backup-*          # no backup at all
before=$(cat "$sb/state/settings" "$sb/state/home_activity")
out=$(unlock "$sb" --status)
after=$(cat "$sb/state/settings" "$sb/state/home_activity")

[[ "$out" == *"RC=0"* ]] && ok "--status succeeds without a backup" || bad "--status failed without a backup"
[[ "$before" == "$after" ]] && ok "--status left the device untouched" || bad "--status modified device state"
[[ "$out" == *"CURRENT STATE"* ]] && ok "--status reports the state" || bad "no state in output"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "applying without a backup is refused"

sb=$(new_sandbox)
rm -rf "$sb"/run/projector-backup-*
out=$(unlock "$sb" --apply-all --yes)
if [[ "$out" != *"RC=0"* ]] && [[ "$out" == *"backup"* ]]; then
    ok "refuses to modify anything without a verified backup"
else
    bad "ran without a backup"
fi
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "device untouched after refusal" || bad "device changed despite refusal"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "a different projector model is refused"

sb=$(new_sandbox)
sed -i '' 's/^ro.product.model=.*/ro.product.model=SOMETHING_ELSE/' "$sb/state/props" 2>/dev/null || \
    sed -i 's/^ro.product.model=.*/ro.product.model=SOMETHING_ELSE/' "$sb/state/props"
sed -i '' 's/^ro.product.device=.*/ro.product.device=other/' "$sb/state/props" 2>/dev/null || \
    sed -i 's/^ro.product.device=.*/ro.product.device=other/' "$sb/state/props"
out=$(unlock "$sb" --apply-all --yes)
if [[ "$out" != *"RC=0"* ]] && [[ "$out" == *"Unsupported device"* ]]; then
    ok "refuses hardware it was not written for"
else
    bad "did not refuse an unsupported device"
fi
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "the full unlock works and survives a restart"

sb=$(new_sandbox)
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" == *"RC=0"* ]] && ok "unlock completes" || { bad "unlock failed"; echo "$out" | tail -6 | sed 's/^/        /'; }

dev "$sb" 'pm list packages -f' | grep -q "=$PROJECTIVY\$" \
    && ok "Projectivy was installed" || bad "Projectivy is not installed"

home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "home screen is Projectivy" || bad "home is '$home'"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && ok "stock launcher is disabled" || bad "stock launcher still enabled"

# The decisive one. Setting the home activity alone reverts on boot while the
# stock launcher is enabled -- that is why Nova sat unused since July.
reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "still Projectivy after a restart" || bad "reverted to '$home' after restart"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "a launcher that does not actually run is never trusted"
# "Installed" and "usable" are different things. A launcher that starts and
# dies still appears in pm list packages, and disabling the stock launcher on
# that basis leaves the projector with no home screen at all.

sb=$(new_sandbox)
out=$(unlock "$sb" FAKE_ADB_LAUNCHER_CRASHES=1 --apply-all --yes)

[[ "$out" == *"not usable as a home screen"* ]] \
    && ok "the dead launcher is detected" || bad "did not notice the launcher was dead"
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails rather than proceeding" || bad "unlock claimed success with a dead launcher"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "stock launcher was disabled anyway" || ok "stock launcher left enabled"

home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen still works" || bad "user left with home='$home'"

reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "and still works after a restart" || bad "home drifted to '$home' after restart"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "running it twice changes nothing the second time"

sb=$(new_sandbox)
unlock "$sb" --apply-all --yes >/dev/null
snap1=$(cat "$sb/state/settings" "$sb/state/home_activity" "$sb/state/packages_disabled")
out=$(unlock "$sb" --apply-all --yes)
snap2=$(cat "$sb/state/settings" "$sb/state/home_activity" "$sb/state/packages_disabled")

[[ "$out" == *"RC=0"* ]] && ok "second run succeeds" || bad "second run failed"
[[ "$snap1" == "$snap2" ]] && ok "second run left the device identical" || bad "second run changed state"
[[ "$out" == *"already"* ]] && ok "says it had nothing to do" || bad "did not report a no-op"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "undo puts the stock launcher back"

sb=$(new_sandbox)
unlock "$sb" --apply-all --yes >/dev/null
out=$(unlock "$sb" --revert --yes)

home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen is the stock launcher again" || bad "home is '$home'"
dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "stock launcher left disabled" || ok "stock launcher re-enabled"
reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "still stock after a restart" || bad "home drifted to '$home'"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "a device that will not let go of its launcher fails safely"
# If disabling the stock launcher does not take, the unlock must not leave the
# user with no home screen at all. It backs its own change out.

sb=$(new_sandbox)
unlock "$sb" FAKE_ADB_REFUSE_DISABLE=1 --apply-all --yes >/dev/null 2>&1
home=$(home_now "$sb")
if [[ "$home" == "$STOCK"* ]]; then
    ok "left the stock launcher working when it could not be disabled"
else
    bad "user left with home='$home' after a failed unlock"
fi
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "the shipped launcher APK is the one we say it is"
# This APK is installed as the home screen on a rooted device, so "where did it
# come from" has to stay answerable. apks/PROVENANCE.md records the hash that
# was checked against the developer's signature; if the file and that record
# ever disagree, one of them is wrong and neither should be trusted quietly.

prov="$REPO_ROOT/apks/PROVENANCE.md"
apk=$(ls "$REPO_ROOT"/apks/projectivy*.apk 2>/dev/null | head -1)
if [[ -z "$apk" ]]; then
    echo "  [SKIP] no Projectivy APK checked in"
elif [[ ! -f "$prov" ]]; then
    bad "an APK is shipped with no PROVENANCE.md recording where it came from"
else
    want=$(grep -oE '\b[0-9a-f]{64}\b' "$prov" | head -1)
    got=$(shasum -a 256 "$apk" | cut -d' ' -f1)
    [[ "$want" == "$got" ]] \
        && ok "$(basename "$apk") matches the recorded hash" \
        || bad "$(basename "$apk") is $got, PROVENANCE.md says $want"
    grep -q 'com.spocky.projengmenu' "$prov" \
        && ok "PROVENANCE names the package it installs" \
        || bad "PROVENANCE does not name the package"
fi

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"

# A suite that leaks processes poisons whatever runs after it.
leaked=$(pgrep -f 'sleep 600' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$leaked" -gt 0 ]]; then
    echo "  WARNING: $leaked orphaned hang-simulation processes left behind"
    pkill -f 'sleep 600' 2>/dev/null || true
fi

[[ "$FAIL" -eq 0 ]]
