#!/bin/bash
# End-to-end tests for UNLOCK.sh against the emulated NL5H00X.
# No hardware involved. Run: bash tests/unlock-tests.sh

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

# A sandbox is an emulated device plus a working directory that already holds a
# verified backup, since UNLOCK.sh refuses to run without one.
new_sandbox() {
    sb=$(mktemp -d)
    sandbox_register "$sb"
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
}

# Run UNLOCK.sh in a sandbox. Extra env goes before the command.
# Guard empty env arrays: Bash 3.2 treats them as unset under set -u.
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
        PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" APK_DIR="$sb/apks" \
            env HOME_SETTLE_SECS=0 LAUNCHER_SETTLE_SECS=0 WTPROV_RESTART_TIMEOUT=2 \
            ${envs[@]+"${envs[@]}"} \
            bash "$SCRIPTS/UNLOCK.sh" "$@" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
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
home_now() { tr -d '\r\n' < "$1/state/home_activity"; }
reboot_dev() { PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$1/state" adb reboot >/dev/null 2>&1; }

STOCK=com.newlink.hisilauncher
NOVA=com.teslacoilsw.launcher
PROJECTIVY=com.spocky.projengmenu

# ---------------------------------------------------------------------------
head_ "the device starts locked, exactly as the real one does"

new_sandbox
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
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--status changes nothing and needs no backup"

new_sandbox
rm -rf "$sb"/run/projector-backup-*          # no backup at all
before=$(cat "$sb/state/settings" "$sb/state/home_activity")
out=$(unlock "$sb" --status)
after=$(cat "$sb/state/settings" "$sb/state/home_activity")

[[ "$out" == *"RC=0"* ]] && ok "--status succeeds without a backup" || bad "--status failed without a backup"
[[ "$before" == "$after" ]] && ok "--status left the device untouched" || bad "--status modified device state"
[[ "$out" == *"CURRENT STATE"* ]] && ok "--status reports the state" || bad "no state in output"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "applying without a backup is refused"

new_sandbox
rm -rf "$sb"/run/projector-backup-*
out=$(unlock "$sb" --apply-all --yes)
if [[ "$out" != *"RC=0"* ]] && [[ "$out" == *"backup"* ]]; then
    ok "refuses to modify anything without a verified backup"
else
    bad "ran without a backup"
fi
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "device untouched after refusal" || bad "device changed despite refusal"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a different projector model is refused"

new_sandbox
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
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "the full unlock works and survives a restart"

new_sandbox
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
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a launcher that does not actually run is never trusted"
# "Installed" and "usable" are different things. A launcher that starts and
# dies still appears in pm list packages, and disabling the stock launcher on
# that basis leaves the projector with no home screen at all.

new_sandbox
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
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "running it twice changes nothing the second time"

new_sandbox
unlock "$sb" --apply-all --yes >/dev/null
snap1=$(cat "$sb/state/settings" "$sb/state/home_activity" "$sb/state/packages_disabled")
out=$(unlock "$sb" --apply-all --yes)
snap2=$(cat "$sb/state/settings" "$sb/state/home_activity" "$sb/state/packages_disabled")

[[ "$out" == *"RC=0"* ]] && ok "second run succeeds" || bad "second run failed"
[[ "$snap1" == "$snap2" ]] && ok "second run left the device identical" || bad "second run changed state"
[[ "$out" == *"already"* ]] && ok "says it had nothing to do" || bad "did not report a no-op"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "undo puts the stock launcher back"

new_sandbox
unlock "$sb" --apply-all --yes >/dev/null
out=$(unlock "$sb" --revert --yes)

home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen is the stock launcher again" || bad "home is '$home'"
dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "stock launcher left disabled" || ok "stock launcher re-enabled"
reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "still stock after a restart" || bad "home drifted to '$home'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a device that refuses to disable its launcher is no longer a special case"
# This scenario used to check that the unlock backed itself out when
# `pm disable-user` did not take. There is no disable left to fail: the unlock
# reaches its goal with a preference alone. The scenario is kept, pointed at the
# invariant that outlived it -- a device that refuses disables must reach the
# same end state as one that would allow them, because we never ask.

new_sandbox
unlock "$sb" FAKE_ADB_REFUSE_DISABLE=1 --apply-all --yes >/dev/null 2>&1
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] \
    && ok "reaches Projectivy without ever needing a disable" \
    || bad "home is '$home' on a device that refuses disables"

dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "something disabled the stock launcher" \
    || ok "and the stock launcher is still enabled"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "on the real firmware the unlock writes wtprovision's cache and HOME lands on the launcher"
# The real NL5H00X routes HOME through com.newlink.wtprovision/.MainActivity,
# which starts whatever its own SharedPreferences cache names. No preference
# reaches it, so the unlock rewrites that cache as root and restarts the
# process. Nothing gets disabled on the way: that is the bricking pattern.

WTPROV_XML=/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml
new_sandbox
f="$sb/state$WTPROV_XML"
out=$(unlock "$sb" --apply-all --yes)

[[ "$out" == *"RC=0"* ]] && ok "unlock completes on the intercepting firmware" \
    || { bad "unlock failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
[[ "$out" != *"owns the home intent"* ]] \
    && ok "no longer refuses the firmware" || bad "still prints the 'owns the home intent' refusal"
grep -q 'name="home_pkg">com.spocky.projengmenu<' "$f" \
    && ok "cache names the Projectivy package" || bad "cache home_pkg is not Projectivy"
grep -q 'name="home_activity">com.spocky.projengmenu.ui.home.MainActivity<' "$f" \
    && ok "cache names the Projectivy activity" || bad "cache home_activity is not Projectivy"
pid=$(cat "$sb/state/wtprov_pid" 2>/dev/null)
[[ -n "$pid" && "$pid" != 2166 ]] && ok "wtprovision was restarted" || bad "wtprovision pid is '$pid'"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "HOME lands on Projectivy" || bad "home is '$home'"

bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
[[ -f "$bk" ]] && grep -q hisilauncher "$bk" \
    && ok "the stock cache was backed up first" || bad "no backup of the stock cache at $bk"
bksha="$sb/state/data/local/tmp/wtprov_prefs.before.sha256"
[[ -f "$bksha" && "$(tr -d '\r\n ' < "$bksha")" == "$(shasum -a 256 "$bk" | cut -d' ' -f1)" ]] \
    && ok "the backup's sha256 was recorded next to it" || bad "no matching sha256 sidecar at $bksha"

disabled=$(dev "$sb" 'pm list packages -d')
[[ "$disabled" != *"$STOCK"* ]] \
    && ok "stock launcher left enabled" || bad "disabled the stock launcher - that is the bricking pattern"
[[ "$disabled" != *"com.newlink.wtprovision"* ]] \
    && ok "wtprovision left enabled" || bad "disabled wtprovision - this is what stops the device booting"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "the cache write survives a restart"
# The cache is what wtprovision reads on boot, so a restart must land on the
# launcher again with nobody touching anything.

new_sandbox
f="$sb/state$WTPROV_XML"
unlock "$sb" --apply-all --yes >/dev/null
reboot_dev "$sb"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "still Projectivy after a restart" || bad "reverted to '$home' after restart"
grep -q 'name="home_pkg">com.spocky.projengmenu<' "$f" \
    && ok "the cache still names Projectivy after a restart" || bad "cache lost Projectivy over a restart"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a cache write that does not take effect is reported as a failure, not success"
# A firmware build that ignores the cache starts stock after the restart. The
# file on disk saying Projectivy proves nothing; only the focused window does.

new_sandbox
out=$(unlock "$sb" FAKE_ADB_WTPROV_IGNORES_CACHE=1 --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock claimed success when HOME stayed stock"
[[ "$out" == *"did not take effect"* ]] \
    && ok "says the cache write did not take effect" || bad "did not report the ineffective cache write"
[[ "$out" != *"All steps applied"* ]] \
    && ok "does not print the success line" || bad "printed 'All steps applied' anyway"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "revert restores the stock pair and restarts wtprovision"
# A cache rewrite is only undone once wtprovision rereads it, so the revert
# has to restart the process too, not just put the file back.

new_sandbox
f="$sb/state$WTPROV_XML"
unlock "$sb" --apply-all --yes >/dev/null
pid1=$(cat "$sb/state/wtprov_pid" 2>/dev/null)
out=$(unlock "$sb" --revert --yes)
pid2=$(cat "$sb/state/wtprov_pid" 2>/dev/null)

[[ "$out" == *"RC=0"* ]] && ok "revert completes" || { bad "revert failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
[[ -n "$pid1" && "$pid1" != 2166 ]] && ok "the unlock restarted wtprovision" || bad "pid after unlock is '$pid1'"
[[ -n "$pid2" && "$pid2" != "$pid1" ]] && ok "the revert restarted it again" || bad "pid after revert is '$pid2' (was '$pid1')"
grep -q 'name="home_pkg">com.newlink.hisilauncher<' "$f" \
    && grep -q 'name="home_activity">com.newlink.hisilauncher.WizardAciticity<' "$f" \
    && ok "cache holds the stock pair again" || bad "cache does not hold the stock pair"
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen is the stock launcher again" || bad "home is '$home'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--status reads the cache, not the preference"
# On this firmware the HOME preference is not what decides the home screen;
# the cache is. A stale preference must not make --status lie.

new_sandbox
unlock "$sb" --apply-all --yes >/dev/null
echo "$STOCK/.WizardAciticity" > "$sb/state/home_activity"
out=$(unlock "$sb" --status)
[[ "$out" == *"home screen now: $PROJECTIVY"* ]] \
    && ok "reports Projectivy from the cache" || bad "home screen line does not name Projectivy"
echo "$out" | grep -qE '\[done\][[:space:]]+launcher_default' \
    && ok "launcher_default shows [done]" || bad "launcher_default is not [done]: $(echo "$out" | grep launcher_default)"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a cache that names the launcher while HOME shows stock is not 'nothing to do'"
# wtprovision reads its cache when it starts. A cache written while it kept
# running leaves HOME on stock until it restarts, and the file alone hides that.

new_sandbox
unlock "$sb" --apply-all --yes >/dev/null
out=$(unlock "$sb" FAKE_ADB_WTPROV_STALE=1 --status)
[[ "$out" == *"RC=0"* && "$out" != *"HOME shows"* ]] \
    && ok "control: no warning while HOME agrees with the cache" || bad "control: warned with HOME on the launcher"
echo "$STOCK/.WizardAciticity" > "$sb/state/home_activity"
out=$(unlock "$sb" FAKE_ADB_WTPROV_STALE=1 --status)
echo "$out" | grep -qE '^\[WARN\] .*HOME shows' \
    && ok "--status warns that HOME disagrees with the cache" || bad "no status warning: $(echo "$out" | tail -4)"
echo "$out" | grep -qE '^  \[(done|todo|blocked)\] +launcher_default +[^[:space:]]' \
    && ok "the step row keeps its format" || bad "row format: $(echo "$out" | grep launcher_default)"
echo "$out" | grep -qE '^[[:space:]]+home screen now: [a-z]' \
    && ok "the home line keeps its format" || bad "home line format changed"
pid1=$(cat "$sb/state/wtprov_pid")
out=$(unlock "$sb" FAKE_ADB_WTPROV_STALE=1 --apply-all --yes)
pid2=$(cat "$sb/state/wtprov_pid")
[[ "$out" == *"RC=0"* ]] && ok "the run completes" || { bad "run failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
[[ "$out" == *"HOME shows $STOCK; restarting wtprovision"* ]] \
    && ok "says HOME disagrees and restarts wtprovision" || bad "no HOME-shows message: $(echo "$out" | tail -4)"
[[ "$pid2" != "$pid1" ]] && ok "wtprovision was restarted" || bad "pid unchanged: $pid1"
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "HOME lands on Projectivy" || bad "home is '$home'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a missing wtprovision process is an error, not a silent skip"
# Without a running process there is nothing to restart, so a cache write
# would sit unread until the next boot. That has to stop the unlock loudly.

new_sandbox
rm "$sb/state/wtprov_pid"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock claimed success with no wtprovision process"
[[ "$out" == *"wtprovision is not running"* ]] \
    && ok "says wtprovision is not running" || bad "did not report the missing process"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a half-written cache is not reported as applied"
# wtprovision needs both keys to agree. An activity that names Projectivy
# while the package still names the stock launcher is not an applied step.
# The full unlock runs first so the launcher is installed and the only thing
# wrong is the cache pair.

new_sandbox
f="$sb/state$WTPROV_XML"
unlock "$sb" --apply-all --yes >/dev/null
out=$(unlock "$sb" --status)
echo "$out" | grep -qE '\[done\][[:space:]]+launcher_default' \
    && ok "control: a full cache shows [done]" || bad "control: launcher_default is not [done] after the unlock"
cat > "$f" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="home_activity">com.spocky.projengmenu.ui.home.MainActivity</string>
    <string name="home_pkg">com.newlink.hisilauncher</string>
</map>
EOF
out=$(unlock "$sb" --status)
echo "$out" | grep -qE '\[todo\][[:space:]]+launcher_default' \
    && ok "launcher_default shows [todo]" || bad "half-written cache: $(echo "$out" | grep launcher_default)"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--status keeps its line format"

new_sandbox
out=$(unlock "$sb" --status)
echo "$out" | grep -qE '^\s+\[(done|todo|blocked)\]\s+launcher_default\s+' \
    && ok "step row format" || bad "step row format changed"
echo "$out" | grep -qE '^\s+home screen now: [a-z]' \
    && ok "home line format" || bad "home line format changed"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "revert never creates a missing cache file"
# A file created by a root redirect is owned by root, not by wtprovision, so
# the revert must refuse rather than recreate it.

new_sandbox
f="$sb/state$WTPROV_XML"
unlock "$sb" --apply-all --yes >/dev/null
[[ -f "$sb/state/data/local/tmp/wtprov_prefs.before.xml" ]] \
    && ok "control: the unlock left a backup" || bad "control: no backup after the unlock"
rm "$f"
out=$(unlock "$sb" --revert --yes)
[[ "$out" != *"RC=0"* ]] && ok "the revert fails" || bad "revert claimed success with no cache file"
[[ "$out" == *"cache is not on the device"* ]] \
    && ok "names the missing cache" || bad "did not name the missing cache: $(echo "$out" | grep -i cache | head -3)"
[[ ! -e "$f" ]] && ok "the cache file is still absent" || bad "the revert created the cache file"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "revert does not trust a backup whose recorded hash does not match"
# The backup is only the original if its sha256 matches the one recorded when
# it was taken. Anything else falls back to writing the stock pair.

for case_ in corrupt nosidecar; do
    new_sandbox
    f="$sb/state$WTPROV_XML"
    bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
    unlock "$sb" --apply-all --yes >/dev/null
    if [[ "$case_" == corrupt ]]; then
        echo '<map>invalid cache</map>' > "$bk"
    else
        rm -f "$sb/state/data/local/tmp/wtprov_prefs.before.sha256"
    fi
    out=$(unlock "$sb" --revert --yes)
    [[ "$out" == *"RC=0"* ]] && ok "$case_: revert completes" \
        || { bad "$case_: revert failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
    grep -q 'name="home_pkg">com.newlink.hisilauncher<' "$f" \
        && grep -q 'name="home_activity">com.newlink.hisilauncher.WizardAciticity<' "$f" \
        && ok "$case_: cache holds the stock pair" || bad "$case_: cache is: $(tr -d '\n' < "$f")"
    [[ "$out" == *"not trusted"* ]] \
        && ok "$case_: says the backup was not trusted" || bad "$case_: did not say the backup was not trusted"
    # The live cache is the only copy of what was there; it is kept first.
    live=$(ls "$sb/state/data/local/tmp/"wtprov_prefs.live.*.xml 2>/dev/null | head -1)
    livesha="${live%.xml}.sha256"
    [[ -n "$live" ]] && grep -q "name=\"home_pkg\">$PROJECTIVY<" "$live" \
        && ok "$case_: the live cache was kept before the revert" || bad "$case_: no wtprov_prefs.live.*.xml naming Projectivy"
    [[ -n "$live" && -f "$livesha" && "$(tr -d '\r\n ' < "$livesha")" == "$(shasum -a 256 "$live" | cut -d' ' -f1)" ]] \
        && ok "$case_: its sha256 is recorded next to it" || bad "$case_: no matching sidecar at '$livesha'"
    sandbox_finish "$sb"
done

# ---------------------------------------------------------------------------
head_ "a cache and an identical backup without the keys are refused"
# Same bytes means recording the hash would be truthful, but a backup without
# the pair can never be restored, so nothing is recorded or written.

new_sandbox
f="$sb/state$WTPROV_XML"
bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
printf '<map></map>\n' > "$f"
cp "$f" "$bk"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock went ahead without the keys"
[[ "$out" == *"no home_pkg/home_activity pair"* ]] \
    && ok "names the missing keys" || bad "no missing-keys message: $(echo "$out" | grep -i error | head -3)"
[[ ! -e "$sb/state/data/local/tmp/wtprov_prefs.before.sha256" ]] \
    && ok "no sidecar was written" || bad "a sidecar was written"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "an interceptor that is not wtprovision blocks the step, even the launcher"
# Only wtprovision's cache is understood. Any other owner of the home intent,
# the launcher included, is reported and left alone.

new_sandbox
f="$sb/state$WTPROV_XML"
before=$(cat "$f")
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$PROJECTIVY/.Main" --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock succeeded with the launcher as interceptor"
[[ "$(cat "$f")" == "$before" ]] && ok "the cache is unchanged" || bad "the cache was written"
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR="$PROJECTIVY/.Main" --status)
echo "$out" | grep -qE "\[blocked\][[:space:]]+launcher_default.*$PROJECTIVY/\.Main" \
    && ok "--status shows [blocked] naming the component" || bad "status: $(echo "$out" | grep launcher_default)"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a cache that is not valid XML stops the unlock before any write"
# The pair can be read out of a broken file with sed, so only a real parse
# tells wtprovision's cache apart from something it would choke on.

new_sandbox
f="$sb/state$WTPROV_XML"
printf '<broken\n' >> "$f"
grep -q 'name="home_pkg">com.newlink.hisilauncher<' "$f" && tail -1 "$f" | grep -q '<broken' \
    && ok "control: the cache holds the pair and trailing junk" || bad "control: seed not built"
before=$(shasum -a 256 "$f" | cut -d' ' -f1)
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock went ahead with an unparseable cache"
[[ "$out" == *"not valid XML"* ]] \
    && ok "names the XML problem" || bad "no XML message: $(echo "$out" | grep -i -e error | head -3)"
[[ "$(shasum -a 256 "$f" | cut -d' ' -f1)" == "$before" ]] \
    && ok "the cache is unchanged" || bad "the cache was written"
[[ ! -e "$sb/state/data/local/tmp/wtprov_prefs.before.sha256" ]] \
    && ok "no backup sidecar was created" || bad "a backup sidecar was written"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "the new cache is built from the trusted backup"
# The backup is the original; keys only it carries must survive the write.

new_sandbox
f="$sb/state$WTPROV_XML"
bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
awk '/<\/map>/ { print "    <string name=\"other\">keep</string>" } { print }' "$f" > "$bk"
shasum -a 256 "$bk" | cut -d' ' -f1 > "$sb/state/data/local/tmp/wtprov_prefs.before.sha256"
grep -q 'name="other"' "$f" && bad "control: the live cache already has the extra key" \
    || ok "control: only the backup carries the extra key"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" == *"RC=0"* ]] && ok "unlock completes" || { bad "unlock failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
grep -q 'name="other">keep<' "$f" && ok "the extra key from the backup survived" || bad "cache lost the backup's extra key"
grep -q 'name="home_pkg">com.spocky.projengmenu<' "$f" && ok "and the cache names Projectivy" || bad "cache home_pkg is not Projectivy"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a foreign file at the backup path stops the unlock before any write"
# Nothing is written without a trusted backup. An unrecorded file that differs
# from the cache is set aside by hand, not overwritten and not ignored.

new_sandbox
f="$sb/state$WTPROV_XML"
bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
seed=$(cat "$f")
echo '<map>foreign</map>' > "$bk"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" =~ wtprov_prefs\.before\.xml\.old\.[0-9]{8}_[0-9]{6}\.[0-9]+ ]] && ok "set-aside name carries a timestamp and pid" || bad "set-aside name lacks the timestamp or pid"
# Freeze the clock so both runs land in the same second; the names must still differ.
frozen="$sb/frozen-date"; mkdir -p "$frozen"
printf '#!/bin/bash\n[[ "$1" == +%%Y%%m%%d_%%H%%M%%S ]] && { echo 20261027_120000; exit 0; }\nexec /bin/date "$@"\n' > "$frozen/date"
chmod +x "$frozen/date"
aside_name() { echo "$1" | grep -o 'wtprov_prefs\.before\.xml\.old\.[0-9_.]*' | head -1; }
name1=$(aside_name "$(PATH="$frozen:$PATH" unlock "$sb" --apply-all --yes)")
name2=$(aside_name "$(PATH="$frozen:$PATH" unlock "$sb" --apply-all --yes)")
[[ "$name1" == *.old.20261027_120000* && "$name2" == *.old.20261027_120000* ]] \
    && ok "control: both runs used the frozen clock" || bad "control: frozen clock not used: '$name1' '$name2'"
[[ -n "$name1" && "$name1" != "$name2" ]] && ok "two runs in one second print different set-aside names" \
    || bad "two runs printed the same set-aside name: '$name1'"
[[ "$out" != *"RC=0"* ]] && ok "the unlock refuses" || bad "unlock went ahead with a foreign file at the backup path"
[[ "$out" == *"/data/local/tmp/wtprov_prefs.before.xml"* && "$out" == *"mv "* ]] \
    && ok "names the file and the mv that sets it aside" || bad "no path or mv command: $(echo "$out" | grep -i backup | head -3)"
[[ "$(cat "$f")" == "$seed" ]] && ok "the cache is unchanged" || bad "the cache was written: $(tr -d '\n' < "$f")"
[[ "$(cat "$bk")" == '<map>foreign</map>' ]] && ok "the foreign file is untouched" || bad "the foreign file changed"
rm "$bk"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" == *"RC=0"* ]] && ok "control: with the file gone the unlock completes" \
    || { bad "control: unlock failed without the foreign file"; echo "$out" | tail -6 | sed 's/^/        /'; }
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "revert writes the stock pair when the backup names another launcher"
# Revert exists to put the stock launcher back. An unrecorded backup equal to a
# live cache naming Nova is recorded, but restoring it would bring Nova back.

new_sandbox
f="$sb/state$WTPROV_XML"
bk="$sb/state/data/local/tmp/wtprov_prefs.before.xml"
sed -e "s|>$STOCK.WizardAciticity<|>$NOVA.NovaLauncher<|" -e "s|>$STOCK<|>$NOVA<|" "$f" > "$bk"
cp "$bk" "$f"
grep -q "name=\"home_pkg\">$NOVA<" "$f" && grep -q "name=\"home_activity\">$NOVA.NovaLauncher<" "$f" \
    && ok "control: the live cache names Nova" || bad "control: Nova cache not built"
out=$(unlock "$sb" --apply-all --yes)
[[ "$out" == *"RC=0"* ]] && ok "unlock completes" || { bad "unlock failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
grep -q "name=\"home_pkg\">$PROJECTIVY<" "$f" && ok "Projectivy is in the cache" || bad "cache home_pkg is not Projectivy"
out=$(unlock "$sb" --revert --yes)
[[ "$out" == *"RC=0"* ]] && ok "revert completes" || { bad "revert failed"; echo "$out" | tail -6 | sed 's/^/        /'; }
grep -q "name=\"home_pkg\">$STOCK<" "$f" \
    && grep -q "name=\"home_activity\">$STOCK.WizardAciticity<" "$f" \
    && ok "cache holds the stock pair" || bad "cache is: $(tr -d '\n' < "$f")"
[[ "$out" == *"names $NOVA, not the stock launcher"* ]] \
    && ok "says the backup names Nova" || bad "did not say the backup names Nova"
home=$(home_now "$sb")
[[ "$home" == "$STOCK"* ]] && ok "home screen is the stock launcher" || bad "home is '$home'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a HOME press that fails is not read as success"

new_sandbox
out=$(unlock "$sb" FAKE_ADB_INPUT_FAILS=1 --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the unlock fails" || bad "unlock claimed success though HOME could not be pressed"
[[ "$out" == *"input keyevent HOME failed"* ]] \
    && ok "says pressing HOME failed" || bad "did not report the failed HOME press"
[[ "$out" != *"All steps applied"* ]] \
    && ok "does not print the success line" || bad "printed 'All steps applied' anyway"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a stock unit reboots once in the middle and the unlock finishes by itself"
# The real projector rejects every pm install with
# INSTALL_FAILED_INVALID_INSTALL_LOCATION, so the launcher goes into /system/app
# and only registers after a restart. One command has to cover that: the runner
# restarts the projector itself, waits, and carries on.

new_sandbox
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 --apply-all --yes)

[[ "$out" == *"INSTALL_FAILED_INVALID_INSTALL_LOCATION"* ]] \
    && ok "reports why the normal install failed" || bad "swallowed the install failure"
[[ -f "$sb/state/system/app/Projectivy/Projectivy.apk" ]] \
    && ok "fell back to /system/app" || bad "no APK in /system/app after the fallback"
apksha=$(shasum -a 256 "$sb/apks/projectivy-launcher-4.71.apk" | cut -d' ' -f1)
destsha=$(shasum -a 256 "$sb/state/system/app/Projectivy/Projectivy.apk" 2>/dev/null | cut -d' ' -f1)
[[ "$destsha" == "$apksha" ]] \
    && ok "the /system/app copy has the APK's sha256" || bad "dest sha256 '$destsha', APK '$apksha'"
[[ "$out" == *"Restarting the projector"* ]] \
    && ok "says it restarts the projector" || bad "did not announce the restart"
[[ "$out" != *"Resuming"* ]] \
    && ok "carries on in the same run" || bad "printed Resuming in a single run"
[[ "$(cat "$sb/state/reboots")" == "1" ]] \
    && ok "restarted exactly once" || bad "reboots: $(cat "$sb/state/reboots")"
[[ "$out" == *"RC=0"* ]] \
    && ok "the one run finishes the unlock" || { bad "unlock did not finish"; echo "$out" | tail -6 | sed 's/^/        /'; }
home=$(home_now "$sb")
[[ "$home" == "$PROJECTIVY"* ]] && ok "home screen is Projectivy" || bad "home is '$home'"
[[ ! -e "$sb/run/.unlock-resume" ]] \
    && ok "no resume marker left behind" || bad "marker left: $(cat "$sb/run/.unlock-resume")"

# and it must not have touched the stock launcher on the way past
dev "$sb" 'pm list packages -d' | grep -q "$STOCK" \
    && bad "disabled the stock launcher" \
    || ok "stock launcher left alone"

# The filesystem holding /system must not be left writable. On this device that
# is / -- it is system-as-root, so /system is never its own mount.
dev "$sb" 'cat /proc/mounts' | awk '$2 == "/" && $4 ~ /^ro(,|$)/ { f = 1 } END { exit !f }' \
    && ok "/ put back read-only" || bad "/ left writable"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a /system/app copy that does not match the APK stops before the restart"
# A partial copy followed by a reboot is the worst case: the next boot scans a
# broken APK. The copy is checked by sha256 and the projector is not restarted.

new_sandbox
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_SYSTEM_CP_CORRUPTS=1 --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "claimed success with a corrupt /system/app copy"
[[ "$out" == *"sha256"*"does not match"* ]] \
    && ok "names the hash mismatch" || bad "no hash mismatch message: $(echo "$out" | grep -i -e sha256 -e error | head -3)"
[[ "$(cat "$sb/state/reboots")" == "0" ]] \
    && ok "did not restart the projector" || bad "restarted after a bad copy: reboots $(cat "$sb/state/reboots")"
dev "$sb" 'cat /proc/mounts' | awk '$2 == "/" && $4 ~ /^ro(,|$)/ { f = 1 } END { exit !f }' \
    && ok "/ put back read-only" || bad "/ left writable"
[[ "$out" != *"All steps applied"* ]] \
    && ok "does not print the success line" || bad "printed 'All steps applied' anyway"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "an interrupted run resumes from the marker instead of starting over"

# The first run is cut off during the restart, then the projector comes up.
new_sandbox
unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_NEVER_BOOTS=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes >/dev/null
reboot_dev "$sb"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "control: the cut-off run left the marker" || bad "control: no launcher_present marker"
out=$(unlock "$sb" --apply-all --yes)

[[ "$out" == *"Resuming after a restart, from launcher_present"* ]] \
    && ok "says it is resuming from the saved step" || bad "no resume notice naming launcher_present"
n=$(echo "$out" | grep -c 'dev_options:')
[[ "$n" == "0" ]] && ok "steps before the marker are skipped" || bad "dev_options ran again ($n lines)"
echo "$out" | grep -q 'launcher_present: already done' \
    && ok "the saved step is checked again and found done" || bad "launcher_present was not rerun"
echo "$out" | grep -q 'launcher_default: done and verified' \
    && ok "the step after the marker is applied" || bad "launcher_default was not applied"
[[ "$out" == *"RC=0"* ]] && ok "the resumed run finishes" || bad "resumed run failed"
[[ ! -e "$sb/run/.unlock-resume" ]] && ok "marker removed on success" || bad "marker still there"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a resumed step that still needs a restart is not restarted a second time"
# The marker says a restart already happened for this step. If the launcher
# still has not registered, another restart will not help; stop and say so.

new_sandbox
log="$sb/state/invocations.log"
unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_REBOOT_IGNORED=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes >/dev/null
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "control: the first run left the marker" || bad "control: no launcher_present marker"
n1=$(grep -c $'^adb\treboot' "$log")
[[ "$n1" == "1" ]] && ok "control: the first run asked for one restart" || bad "control: first run reboot calls: $n1"
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_REBOOT_IGNORED=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes)
n2=$(grep -c $'^adb\treboot' "$log")
[[ "$out" != *"RC=0"* ]] && ok "the second run fails" || bad "claimed success though the launcher never registered"
[[ "$out" == *"did not register"* ]] \
    && ok "says the launcher did not register" || bad "no did-not-register message: $(echo "$out" | tail -3)"
[[ "$n2" == "$n1" ]] && ok "the second run did not restart again" || bad "reboot calls went from $n1 to $n2"
[[ "$(cat "$sb/state/reboots")" == "0" ]] \
    && ok "the projector was never restarted" || bad "reboots: $(cat "$sb/state/reboots")"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "the marker is kept" || bad "marker: '$(cat "$sb/run/.unlock-resume" 2>/dev/null)'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "no restart without the uptime that proves it"
# Only uptime going backwards proves a restart happened. Without the value
# from before, nothing can be proven, so the projector is not restarted.

new_sandbox
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_NO_UPTIME=1 --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "carried on without an uptime"
[[ "$out" == *"Could not read /proc/uptime, so the projector was not restarted"* ]] \
    && ok "says why it did not restart" || bad "no uptime message: $(echo "$out" | tail -3)"
[[ "$(cat "$sb/state/reboots")" == "0" ]] \
    && ok "did not restart the projector" || bad "restarted without an uptime: reboots $(cat "$sb/state/reboots")"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "the marker names the step" || bad "marker: '$(cat "$sb/run/.unlock-resume" 2>/dev/null)'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a failed adb reboot is reported and keeps the place"

new_sandbox
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_REBOOT_FAILS=1 --apply-all --yes)
[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "carried on after a failed reboot"
[[ "$out" == *"adb reboot failed"* ]] \
    && ok "names the failed reboot" || bad "no failed-reboot message: $(echo "$out" | tail -3)"
[[ "$(cat "$sb/state/reboots")" == "0" ]] \
    && ok "the projector was not restarted" || bad "reboots: $(cat "$sb/state/reboots")"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "the marker is kept" || bad "marker: '$(cat "$sb/run/.unlock-resume" 2>/dev/null)'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a projector that never comes back is reported, not waited for forever"

new_sandbox
start=$SECONDS
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_NEVER_BOOTS=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes)
elapsed=$((SECONDS - start))

[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "claimed success with a projector that never booted"
[[ "$out" == *"did not come back"* && "$out" == *".unlock-resume"* ]] \
    && ok "names the marker that keeps the place" || bad "no marker hint: $(echo "$out" | tail -3)"
(( elapsed < 30 )) && ok "gave up within the timeout (${elapsed}s)" || bad "took ${elapsed}s"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "the marker names the step that needed the restart" || bad "marker: '$(cat "$sb/run/.unlock-resume" 2>/dev/null)'"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a marker that cannot be saved stops the run before any restart"
# Without the marker a restart loses the place, so no marker means no restart.

new_sandbox
mkdir "$sb/run/.unlock-resume"
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 --apply-all --yes)

[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "carried on without a marker"
[[ "$out" == *"Could not save"*".unlock-resume"* ]] \
    && ok "names the marker it could not write" || bad "no marker error: $(echo "$out" | tail -3)"
[[ "$(cat "$sb/state/reboots")" == "0" ]] \
    && ok "did not restart the projector" || bad "restarted without a marker: reboots $(cat "$sb/state/reboots")"
rmdir "$sb/run/.unlock-resume"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "a projector that answers without having restarted is not taken as back"
# The old adbd can still answer right after `adb reboot`. Only uptime going
# backwards proves the restart happened.

new_sandbox
out=$(unlock "$sb" FAKE_ADB_REFUSE_INSTALL=1 FAKE_ADB_REBOOT_IGNORED=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes)

[[ "$out" != *"RC=0"* ]] && ok "the run fails" || bad "claimed success without a restart"
[[ "$out" == *"uptime did not reset"* && "$out" == *"did not restart"* ]] \
    && ok "says the projector did not restart" || bad "no did-not-restart message: $(echo "$out" | tail -3)"
[[ "$(cat "$sb/run/.unlock-resume" 2>/dev/null)" == "launcher_present" ]] \
    && ok "the marker still names the step" || bad "marker: '$(cat "$sb/run/.unlock-resume" 2>/dev/null)'"
[[ "$out" != *"All steps applied"* ]] \
    && ok "does not print the success line" || bad "printed 'All steps applied' anyway"
sandbox_finish "$sb"

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

new_sandbox
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
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "--repair says so when there is nothing to repair"

new_sandbox
out=$(unlock "$sb" FAKE_ADB_HOME_INTERCEPTOR=com.newlink.wtprovision/.MainActivity --repair)
[[ "$out" == *"Nothing to repair"* ]] && ok "reports a healthy device" || bad "did not report a healthy device"
[[ "$out" == *"RC=0"* ]] && ok "and succeeds" || bad "failed on a healthy device"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "the emulated device carries wtprovision's launcher cache"
new_sandbox
WTPROV_XML=/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml
f="$sb/state$WTPROV_XML"
[[ -f "$f" ]] && ok "cache file seeded" || bad "no cache file in the seed"
grep -q 'name="home_pkg">com.newlink.hisilauncher<' "$f" && ok "stock pkg" || bad "stock pkg missing"
out=$(dev "$sb" 'pidof com.newlink.wtprovision'); [[ "$out" =~ ^[0-9]+$ ]] && ok "pidof answers" || bad "pidof: '$out'"
PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" adb shell "su -c 'sh -c \"cat /data/local/tmp/x.xml > $(echo /data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml)\"'" >/dev/null 2>&1

# A firmware that ignores the cache starts stock, never a stale earlier pick.
dev "$sb" "cmd package set-home-activity $NOVA/.Launcher" >/dev/null
[[ "$(dev "$sb" 'dumpsys window')" == *"u0 $NOVA/"* ]] && ok "a non-stock home is selected" || bad "set-home-activity did not take"
dev "$sb" FAKE_ADB_WTPROV_IGNORES_CACHE=1 'kill -9 2166' >/dev/null
out=$(dev "$sb" 'dumpsys window')
[[ "$out" == *"u0 $STOCK/"* ]] && ok "ignored cache restarts stock" || bad "ignored cache kept: $out"

# A failed cache write must reach the toolkit as a nonzero status. Same piped
# form adb_root_exec sends.
echo probe > "$sb/state/data/local/tmp/src.xml"
# dev cannot carry this: it reads any argument holding "=" as an env setting.
out=$(PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" \
    adb shell "echo 'sh -c \"cat /data/local/tmp/src.xml > /data/local/tmp\"' | su 2>&1; echo __RC__=\$?" 2>&1 | tr -d '\r')
[[ "$out" == *"__RC__=1"* ]] && ok "root redirect to a directory fails" || bad "root redirect to a directory: '$out'"
before=$(cat "$f")
out=$(PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" \
    adb shell "sh -c \"cat /data/local/tmp/src.xml > $WTPROV_XML\"; echo __RC__=\$?" 2>&1 | tr -d '\r')
[[ "$out" == *"__RC__=1"* && "$(cat "$f")" == "$before" ]] \
    && ok "non-root redirect fails and leaves the cache" || bad "non-root redirect: '$out'"

# An interceptor override set to empty means no interceptor, seed or not.
out=$(dev "$sb" FAKE_ADB_HOME_INTERCEPTOR= 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME -c android.intent.category.SETUP_WIZARD')
[[ "$out" != *wtprovision* ]] && ok "empty interceptor override wins" || bad "empty override still lists: $out"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"

# Pattern reapers can signal unrelated host processes. Release owned jobs only.
child_release_all

[[ "$FAIL" -eq 0 ]]

