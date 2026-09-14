#!/bin/bash
# Tests for the two interactive front ends, TOOLS.sh and PROJECTOR.sh.
# No hardware. Run: bash tests/ui-tests.sh

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

STOCK=com.newlink.hisilauncher
NOVA=com.teslacoilsw.launcher
PROJECTIVY=com.spocky.projengmenu

new_sandbox() {
    sb=$(mktemp -d)
    sandbox_register "$sb"
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run" "$sb/apks"
    echo "not a real apk" > "$sb/apks/projectivy-launcher-4.71.apk"
    cat > "$sb/apks/projectivy-launcher-4.71.apk.meta" <<EOF
pkg=$PROJECTIVY
home=$PROJECTIVY/com.spocky.projengmenu.ui.home.MainActivity
EOF
}
add_backup() {
    local sb="$1" d="$1/run/projector-backup-20260101_000000"
    mkdir -p "$d"
    cp "$sb/state/blockdev" "$d/full-system-backup.img"
    echo "device_size=$(stat -f%z "$sb/state/blockdev" 2>/dev/null || stat -c%s "$sb/state/blockdev")" \
        > "$d/backup-manifest.txt"
}
# Runs a front end through the *system* bash, which is what the shebang picks.
ui() {
    local sb="$1" script="$2" input="$3"; shift 3
    ( cd "$sb/run" || exit 1
      PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" APK_DIR="$sb/apks" "$@" \
        /bin/bash "$SCRIPTS/$script" <<<"$input" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' )
}
home_now() { tr -d '\r\n' < "$1/state/home_activity"; }
dev() { PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$1/state" adb shell "$2" 2>/dev/null | tr -d '\r'; }

# A device where ROOT.sh has already run: daemon, init service, empty
# allow-list, and sud up. Written straight into the emulated device rather than
# through ROOT.sh, because what is under test here is TOOLS.sh reading it.
install_fake_root() {
    local sb="$1"
    printf 'SUD-DAEMON placeholder\n' > "$sb/state/system/xbin/sud"
    printf 'service sud /system/xbin/sud\n    class late_start\n    user root\n    seclabel u:r:su:s0\n' \
        > "$sb/state/system/etc/init/sud.rc"
    mkdir -p "$sb/state/data/adb"
    : > "$sb/state/data/adb/su-allow"
    echo sud >> "$sb/state/running"
}
allow_list_now() { cat "$1/state/data/adb/su-allow" 2>/dev/null; }

# ---------------------------------------------------------------------------
head_ "every entry script runs under the system bash"
# TOOLS.sh used `local -n`, which needs bash 4.3. macOS ships 3.2, so
# ./scripts/TOOLS.sh died on its first menu draw for every Mac user -- while
# testing with `bash` from PATH (Homebrew 5.x) showed nothing wrong. The
# shebang picks /bin/bash, so that is what the tests have to use.

sysbash=$(/bin/bash --version | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')
echo "  (system bash: $sysbash)"
for s in TOOLS.sh UNLOCK.sh PROJECTOR.sh MAKE_BACKUP.sh; do
    if out=$(/bin/bash -n "$SCRIPTS/$s" 2>&1); then
        ok "$s parses under /bin/bash"
    else
        bad "$s does not parse: $(echo "$out" | head -1)"
    fi
done

new_sandbox
for s in TOOLS.sh PROJECTOR.sh; do
    out=$(ui "$sb" "$s" $'q\n')
    if echo "$out" | grep -qiE 'invalid option|unbound variable|syntax error|command not found'; then
        bad "$s fails at runtime under /bin/bash: $(echo "$out" | grep -iE 'invalid option|unbound|syntax' | head -1 | cut -c1-60)"
    else
        ok "$s runs under /bin/bash"
    fi
done
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh menu is complete and numbered"

new_sandbox
out=$(ui "$sb" TOOLS.sh $'q\n')
count=$(echo "$out" | grep -cE '^ *[0-9]+\. ')
if [[ "$count" -ge 19 ]]; then
    ok "all $count entries render"
else
    bad "only $count entries rendered, expected 19"
fi
echo "$out" | grep -q '19\. Reset to Default Launcher' \
    && ok "numbering runs continuously across sections" \
    || bad "numbering is wrong across sections"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh does not silently fail to reset the launcher"
# The stock launcher cannot be set as home while it is disabled. The unlock no
# longer leaves it that way -- it disables nothing -- but devices disabled by
# older versions of this toolkit are out there, so the guard still matters.
# The disabled state is set up directly now rather than produced by the unlock.

new_sandbox; add_backup "$sb"
echo "$STOCK" >> "$sb/state/packages_disabled"

out=$(ui "$sb" TOOLS.sh $'19\n\nq\n')
if echo "$out" | grep -qi 'currently disabled'; then
    ok "says why it cannot reset the launcher"
else
    bad "no explanation when the stock launcher is disabled"
fi
echo "$out" | grep -q 'UNLOCK.sh --revert' \
    && ok "points at the command that actually works" \
    || bad "does not say what to do instead"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "resetting the launcher works after an unlock, because nothing was disabled"
# The counterpart to the guard above. The unlock reaches its goal with a
# preference alone, so the stock launcher stays enabled and TOOLS.sh can hand
# the home screen straight back without anyone running --revert first.

new_sandbox; add_backup "$sb"
( cd "$sb/run" && PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" APK_DIR="$sb/apks" \
    bash "$SCRIPTS/UNLOCK.sh" --apply-all --yes >/dev/null 2>&1 )

grep -qx "$STOCK" "$sb/state/packages_disabled" 2>/dev/null \
    && bad "the unlock disabled the stock launcher" \
    || ok "the unlock left the stock launcher enabled"

out=$(ui "$sb" TOOLS.sh $'19\n\nq\n')
echo "$out" | grep -qi 'currently disabled' \
    && bad "claimed the stock launcher is disabled when it is not" \
    || ok "no bogus 'disabled' excuse"
[[ "$(home_now "$sb")" == "$STOCK"* ]] \
    && ok "home screen handed back to the stock launcher" \
    || bad "home is '$(home_now "$sb")' after a reset"

( cd "$sb/run" && PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" APK_DIR="$sb/apks" \
    bash "$SCRIPTS/UNLOCK.sh" --revert --yes >/dev/null 2>&1 )
out=$(ui "$sb" TOOLS.sh $'19\n\nq\n')
[[ "$(home_now "$sb")" == "$STOCK"* ]] \
    && ok "works normally once the stock launcher is enabled" \
    || bad "could not reset the launcher even when enabled"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh reports the state it is actually in"

new_sandbox
out=$(ui "$sb" PROJECTOR.sh $'q\n' env FAKE_ADB_NO_DEVICE=1)
echo "$out" | grep -qi 'not connected' \
    && ok "says so when nothing is connected" || bad "did not report a missing device"

out=$(ui "$sb" PROJECTOR.sh $'q\n')
echo "$out" | grep -q 'NL5H00X_TP' && ok "names the device" || bad "device not shown"
echo "$out" | grep -qi 'backup .*none' && ok "flags the missing backup" || bad "missing backup not flagged"
echo "$out" | grep -qi 'needs a backup first' \
    && ok "unlock is offered as unavailable" || bad "offered unlock without a backup"

add_backup "$sb"
out=$(ui "$sb" PROJECTOR.sh $'q\n')
echo "$out" | grep -qi 'backup .*verified' && ok "sees a verified backup" || bad "verified backup not recognised"
echo "$out" | grep -qi 'launcher .*locked' && ok "reports the launcher as locked" || bad "launcher state wrong"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh refuses to unlock without a backup"

new_sandbox
out=$(ui "$sb" PROJECTOR.sh $'2\n\nq\n')
if echo "$out" | grep -qi 'verified backup is required'; then
    ok "refuses and says why"
else
    bad "did not refuse"
fi
[[ "$(home_now "$sb")" == "$STOCK"* ]] \
    && ok "device untouched" || bad "device changed despite refusal"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh drives a real unlock and reflects it afterwards"

new_sandbox; add_backup "$sb"
out=$(ui "$sb" PROJECTOR.sh $'2\ny\n\nq\n')
echo "$out" | grep -q 'All steps applied and verified' \
    && ok "runs the unlock through to the end" || bad "unlock did not complete"
[[ "$(home_now "$sb")" == "$PROJECTIVY"* ]] \
    && ok "home screen is Projectivy" || bad "home screen not changed"

out=$(ui "$sb" PROJECTOR.sh $'q\n')
echo "$out" | grep -qi 'launcher .*unlocked' && ok "header shows unlocked" || bad "header still says locked"
echo "$out" | grep -qi 'already unlocked' && ok "menu stops offering it" || bad "menu still offers the unlock"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh runs a backup to a verified result"

new_sandbox
out=$(ui "$sb" PROJECTOR.sh $'1\n\nq\n' env STREAM_CHUNK_MB=8)
echo "$out" | grep -qi 'Backup complete and verified' \
    && ok "reports a verified backup" || bad "backup did not complete"
img=$(find "$sb/run" -name full-system-backup.img -print -quit)
if [[ -n "$img" ]] && cmp -s "$img" "$sb/state/blockdev"; then
    ok "image is byte-identical to the device"
else
    bad "image differs from the device"
fi
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh reports the root state it is actually in"

new_sandbox
out=$(ui "$sb" TOOLS.sh $'20\n\nq\n')
echo "$out" | grep -qE 'sud binary +missing' \
    && ok "says the daemon is not installed yet" || bad "did not report the missing daemon"
echo "$out" | grep -qiE 'allow-list +not created' \
    && ok "says the allow-list does not exist yet" || bad "allow-list state not reported"
echo "$out" | grep -q 'uid 0' \
    && ok "names the su form this device takes" || bad "su form not shown"

install_fake_root "$sb"
out=$(ui "$sb" TOOLS.sh $'20\n\nq\n')
echo "$out" | grep -qE 'sud daemon +running' \
    && ok "sees the daemon once it runs" || bad "running daemon not detected"
echo "$out" | grep -qi 'fails closed' \
    && ok "explains that an empty allow-list grants nobody root" \
    || bad "empty allow-list not explained"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh grants and revokes app root through the allow-list"

new_sandbox; install_fake_root "$sb"
out=$(ui "$sb" TOOLS.sh $'22\nnot a package name\n\nq\n')
echo "$out" | grep -qi 'not a package name' \
    && ok "rejects something that is not a package name" || bad "took a bad package name"

out=$(ui "$sb" TOOLS.sh "22"$'\n'"$PROJECTIVY"$'\ny\n\nq\n')
grep -qx "$PROJECTIVY" "$sb/state/data/adb/su-allow" \
    && ok "writes the package into /data/adb/su-allow" || bad "allow-list not written"
echo "$out" | grep -qi 'is on the allow-list' \
    && ok "confirms the grant after reading the file back" || bad "grant not confirmed"

out=$(ui "$sb" TOOLS.sh "23"$'\n'"$PROJECTIVY"$'\n\nq\n')
grep -qx "$PROJECTIVY" "$sb/state/data/adb/su-allow" \
    && bad "the package is still in the allow-list after a revoke" \
    || ok "revoke removes the package"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh runs commands as root and refuses what it cannot quote"
# adb_root_exec wraps the command in single quotes, so a command that contains
# one would be cut in half and part of it would run unquoted. Refusing is the
# only safe answer; silently mangling it is not.

new_sandbox; install_fake_root "$sb"
out=$(ui "$sb" TOOLS.sh $'24\necho \'hi\'\n\nq\n')
echo "$out" | grep -qi 'single quote' \
    && ok "refuses a command containing a single quote" || bad "accepted an unquotable command"

out=$(ui "$sb" TOOLS.sh $'24\ngetprop ro.product.model\ny\n\nq\n')
echo "$out" | grep -q 'NL5H00X_TP' \
    && ok "runs a command and shows its output" || bad "command output missing"
echo "$out" | grep -qi 'exit 0' \
    && ok "reports the exit code from the device" || bad "exit code not reported"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh copies a root-only file off the device and verifies it"
# /data/system/packages.list is unreadable as shell. That is the whole point of
# the tool, so the test proves the emulated device refuses it first.

new_sandbox; install_fake_root "$sb"
[[ -z "$(dev "$sb" "cat /data/system/packages.list")" ]] \
    && ok "the device refuses that file to a plain shell" \
    || bad "the emulated device handed /data out without root"

out=$(ui "$sb" TOOLS.sh $'25\n\n\nq\n')
pulled=$(find "$sb/run" -name 'packages.list*' -print -quit)
if [[ -n "$pulled" ]] && cmp -s "$pulled" "$sb/state/data/system/packages.list"; then
    ok "the copy is byte-identical to the file on the device"
else
    bad "no matching copy was written"
fi
echo "$out" | grep -qi 'matches the device' \
    && ok "verifies the copy by hash" || bad "copy not hash-verified"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh turns ADB over Wi-Fi on and off"
# setprop on a service property fails as shell and succeeds as root, which is
# why this tool exists. The emulated device enforces that difference.

new_sandbox; install_fake_root "$sb"
dev "$sb" "setprop service.adb.tcp.port 5555" >/dev/null 2>&1
grep -q '^service.adb.tcp.port=' "$sb/state/props" \
    && bad "the emulated device let shell set a service property" \
    || ok "setprop needs root on the device"

out=$(ui "$sb" TOOLS.sh $'26\ny\n\nq\n')
grep -qx 'service.adb.tcp.port=5555' "$sb/state/props" \
    && ok "turns the port on" || bad "port not set"
echo "$out" | grep -q 'adb connect' \
    && ok "prints the command to connect with" || bad "connect command missing"

out=$(ui "$sb" TOOLS.sh $'26\ny\n\nq\n')
grep -qx 'service.adb.tcp.port=-1' "$sb/state/props" \
    && ok "turns it off again" || bad "port not cleared"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh freezes apps but refuses the ones that stop the boot"
# com.newlink.wtprovision owns MAIN + HOME + SETUP_WIZARD on its own. Freezing
# it stops the boot before adb and Wi-Fi come up, which needs a USB recovery.

new_sandbox; install_fake_root "$sb"
out=$(ui "$sb" TOOLS.sh $'27\ncom.newlink.wtprovision\n\nq\n')
echo "$out" | grep -qi 'wtprovision' \
    && ok "names the package it refuses" || bad "no refusal message"
grep -qx 'com.newlink.wtprovision' "$sb/state/packages_disabled" \
    && bad "froze the package that stops the boot" || ok "left the boot path alone"

out=$(ui "$sb" TOOLS.sh $'27\ncom.apkpure.aegon\ny\n\nq\n')
grep -qx 'com.apkpure.aegon' "$sb/state/packages_disabled" \
    && ok "freezes an ordinary app" || bad "freeze did nothing"

out=$(ui "$sb" TOOLS.sh $'27\ncom.apkpure.aegon\ny\n\nq\n')
grep -qx 'com.apkpure.aegon' "$sb/state/packages_disabled" \
    && bad "still frozen after an unfreeze" || ok "unfreezes it again"
sandbox_finish "$sb"

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]]
