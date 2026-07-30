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

dev() { # run a command on the emulated device; leading VAR=val become env
    local sb="$1"; shift
    local envs=()
    while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
    PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" \
        env "${envs[@]}" adb shell "$@" 2>/dev/null | tr -d '\r'
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

# CORRECTED 2026-07-30. This used to assert the opposite -- that the unlock
# disables the stock launcher -- on the belief that it would otherwise re-claim
# HOME on boot. It never competes: an interceptor owns the vendor intent and
# starts the stock launcher by explicit component. Disabling that interceptor is
# what stopped a real projector booting for three days, so the invariant now is
# that the unlock disables nothing and leaves a working fallback behind.
dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "stock launcher was disabled - that is the bricking pattern" \
    || ok "stock launcher left enabled as the fallback"

# The decisive one: a home preference survives a restart on its own.
reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "still Projectivy after a restart" || bad "reverted to '$home' after restart"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "stock launcher ended up disabled after a restart" \
    || ok "and the fallback is still there after a restart"
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
head_ "a device that refuses to disable its launcher is no longer a special case"
# This scenario used to check that the unlock backed itself out when
# `pm disable-user` did not take. There is no disable left to fail: the unlock
# reaches its goal with a preference alone. The scenario is kept, pointed at the
# invariant that outlived it -- a device that refuses disables must reach the
# same end state as one that would allow them, because we never ask.

sb=$(new_sandbox)
unlock "$sb" FAKE_ADB_REFUSE_DISABLE=1 --apply-all --yes >/dev/null 2>&1
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] \
    && ok "reaches Projectivy without ever needing a disable" \
    || bad "home is '$home' on a device that refuses disables"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "something disabled the stock launcher" \
    || ok "and the stock launcher is still enabled"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "a firmware that owns HOME is handed back to the user, not fought"
# The real NL5H00X adds CATEGORY_SETUP_WIZARD to the home intent, so
# com.newlink.wtprovision/.MainActivity wins HOME outright and then starts the
# stock launcher by name.
#
# The refusal is kept but its reason is now the true one. It is NOT that
# disabling the stock launcher "would leave none" -- that was the model that
# bricked a device. It is that no command on API 28 writes a preference covering
# SETUP_WIZARD, so the CLI simply cannot win that intent. A human can, from the
# device's own chooser, and the step has to say so instead of trying.

sb=$(new_sandbox)
ICEPT=com.newlink.wtprovision/.MainActivity
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" --apply-all --yes)

[[ "$out" == *"owns the home intent on this firmware"* ]] \
    && ok "names the component that owns HOME" || bad "did not name the interceptor"
[[ "$out" == *"CATEGORY_SETUP_WIZARD"* ]] \
    && ok "gives the real reason the CLI cannot win" || bad "did not explain why the CLI cannot do it"
[[ "$out" == *"press HOME"* && "$out" == *"Always"* ]] \
    && ok "tells the user how to finish it on the device" || bad "no instruction for the user"
[[ "$out" != *"RC=0"* ]] && ok "refuses rather than reporting success" || bad "claimed the unlock worked"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "disabled the stock launcher anyway - that is the bricking pattern" \
    || ok "stock launcher left enabled"

dev "$sb" 'pm list packages -d' | grep -q 'com.newlink.wtprovision' \
    && bad "disabled the home interceptor - this is what stops the device booting" \
    || ok "and the home interceptor was never touched"

home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "no stale preference was written" || bad "home changed to '$home'"

# and --status has to say so too, rather than offering a step that cannot work
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" --status)
[[ "$out" == *"owns the home intent on this firmware"* ]] \
    && ok "--status reports it as blocked" || bad "--status did not flag the interception"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "the launcher the user picked from the chooser survives a restart"
# The one path that does work on this firmware. The system's own chooser records
# a preference against the real intent -- including SETUP_WIZARD -- so it wins
# where set-home-activity cannot. home_pref_strong is how the emulator models a
# preference written that way; there is no CLI that produces one.

sb=$(new_sandbox)
ICEPT=com.newlink.wtprovision/.MainActivity
unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" --apply-all --yes >/dev/null 2>&1

# the user presses HOME on the device and picks Projectivy
echo "$PROJECTIVY/com.spocky.projengmenu.ui.home.MainActivity" > "$sb/state/home_activity"
touch "$sb/state/home_pref_strong"

reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] \
    && ok "the chooser's preference survives a restart" || bad "reverted to '$home'"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "the stock launcher ended up disabled" || ok "with nothing disabled to achieve it"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "a device that refuses installs still gets the launcher"
# The real projector rejects every pm install with
# INSTALL_FAILED_INVALID_INSTALL_LOCATION -- nothing has ever been installed
# normally on it. Copying into /system/app is the only route that works there,
# so the fallback has to fire, and it must be honest that a restart is needed
# rather than reporting a launcher that is not registered yet as present.

sb=$(new_sandbox)
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 --apply-all --yes)

[[ "$out" == *"INSTALL_FAILED_INVALID_INSTALL_LOCATION"* ]] \
    && ok "reports why the normal install failed" || bad "swallowed the install failure"
[[ -f "$sb/state/system/app/Projectivy/Projectivy.apk" ]] \
    && ok "fell back to /system/app" || bad "no APK in /system/app after the fallback"
[[ "$out" == *"restart"* ]] \
    && ok "says a restart is needed" || bad "did not mention the restart"
[[ "$out" != *"RC=0"* ]] \
    && ok "does not claim the unlock finished" || bad "claimed success with an unregistered launcher"

# and it must not have touched the stock launcher on the way past
dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "disabled the stock launcher despite an incomplete install" \
    || ok "stock launcher left alone"

# The filesystem holding /system must not be left writable. On this device that
# is / -- it is system-as-root, so /system is never its own mount.
dev "$sb" 'cat /proc/mounts' | awk '$2 == "/" && $4 ~ /^ro(,|$)/ { f = 1 } END { exit !f }' \
    && ok "/ put back read-only" || bad "/ left writable"
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
head_ "--repair fixes a projector that will not finish booting"
# The failure this repairs: com.newlink.wtprovision/.MainActivity disabled. It
# owns the vendor home intent, so with it gone the intent has no candidate,
# no activity ever starts, boot never completes, and Wi-Fi and adb never come
# back. `pm list packages -d` cannot see it -- the package is enabled and only
# the component is not, which is why this went undiagnosed for three days.

sb=$(new_sandbox)
ICEPT=com.newlink.wtprovision/.MainActivity
echo "$ICEPT" > "$sb/state/components_disabled"

# the trap that hid it: the package-level query says everything is fine
dev "$sb" 'pm list packages -d' | grep -q 'wtprovision' \
    && bad "pm list packages -d saw a disabled component (it cannot)" \
    || ok "pm list packages -d shows nothing, as on hardware"

# and the vendor intent has nobody left to answer it
out=$(dev "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME -c android.intent.category.SETUP_WIZARD')
[[ -z "${out// /}" ]] && ok "the home intent resolves to nothing" || bad "still resolves to '$out'"

out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" --repair)
[[ "$out" == *"is disabled"* ]] && ok "names the disabled component" || bad "did not report the disabled component"
[[ "$out" == *"RC=0"* ]] && ok "repair succeeds" || { bad "repair failed"; echo "$out" | tail -5 | sed 's/^/        /'; }

grep -q . "$sb/state/components_disabled" 2>/dev/null \
    && bad "the component is still disabled" || ok "the component was re-enabled"

out=$(dev "$sb" FAKE_ADB_HOME_INTERCEPTOR="$ICEPT" 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME -c android.intent.category.SETUP_WIZARD')
[[ "$out" == *"wtprovision"* ]] && ok "the home intent resolves again" || bad "intent still unanswered"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "--repair says so when there is nothing to repair"

sb=$(new_sandbox)
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR=com.newlink.wtprovision/.MainActivity --repair)
[[ "$out" == *"Nothing to repair"* ]] && ok "reports a healthy device" || bad "did not report a healthy device"
[[ "$out" == *"RC=0"* ]] && ok "and succeeds" || bad "failed on a healthy device"
rm -rf "$sb"

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

