#!/bin/bash
# Tests for the two interactive front ends, TOOLS.sh and PROJECTOR.sh.
# No hardware. Run: bash tests/ui-tests.sh

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
SCRIPTS="${TOOLKIT_SCRIPTS:-$REPO_ROOT/scripts}"

PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()   { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "=== $1 ==="; }

STOCK=com.newlink.hisilauncher
NOVA=com.teslacoilsw.launcher

new_sandbox() {
    local sb; sb=$(mktemp -d)
    bash "$TEST_DIR/device-emu/seed.sh" "$sb/state" >/dev/null
    mkdir -p "$sb/run"
    echo "$sb"
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
      PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" "$@" \
        /bin/bash "$SCRIPTS/$script" <<<"$input" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' )
}
dev() { PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$1/state" adb shell "$2" 2>/dev/null | tr -d '\r'; }

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

sb=$(new_sandbox)
for s in TOOLS.sh PROJECTOR.sh; do
    out=$(ui "$sb" "$s" $'q\n')
    if echo "$out" | grep -qiE 'invalid option|unbound variable|syntax error|command not found'; then
        bad "$s fails at runtime under /bin/bash: $(echo "$out" | grep -iE 'invalid option|unbound|syntax' | head -1 | cut -c1-60)"
    else
        ok "$s runs under /bin/bash"
    fi
done
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh menu is complete and numbered"

sb=$(new_sandbox)
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
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "TOOLS.sh does not silently fail to reset the launcher"
# The stock launcher cannot be set as home while it is disabled -- the state
# the unlock leaves it in. This used to fire the command and report nothing.

sb=$(new_sandbox); add_backup "$sb"
( cd "$sb/run" && PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" \
    bash "$SCRIPTS/UNLOCK.sh" --apply-all --yes >/dev/null 2>&1 )

out=$(ui "$sb" TOOLS.sh $'19\n\nq\n')
if echo "$out" | grep -qi 'currently disabled'; then
    ok "says why it cannot reset the launcher"
else
    bad "no explanation when the stock launcher is disabled"
fi
echo "$out" | grep -q 'UNLOCK.sh --revert' \
    && ok "points at the command that actually works" \
    || bad "does not say what to do instead"
[[ "$(dev "$sb" 'cmd package get-home-activity')" == "$NOVA"* ]] \
    && ok "home screen left alone" || bad "home screen changed unexpectedly"

( cd "$sb/run" && PATH="$TEST_DIR/fake-adb:$PATH" FAKE_ADB_STATE="$sb/state" \
    bash "$SCRIPTS/UNLOCK.sh" --revert --yes >/dev/null 2>&1 )
out=$(ui "$sb" TOOLS.sh $'19\n\nq\n')
[[ "$(dev "$sb" 'cmd package get-home-activity')" == "$STOCK"* ]] \
    && ok "works normally once the stock launcher is enabled" \
    || bad "could not reset the launcher even when enabled"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh reports the state it is actually in"

sb=$(new_sandbox)
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
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh refuses to unlock without a backup"

sb=$(new_sandbox)
out=$(ui "$sb" PROJECTOR.sh $'2\n\nq\n')
if echo "$out" | grep -qi 'verified backup is required'; then
    ok "refuses and says why"
else
    bad "did not refuse"
fi
[[ "$(dev "$sb" 'cmd package get-home-activity')" == "$STOCK"* ]] \
    && ok "device untouched" || bad "device changed despite refusal"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh drives a real unlock and reflects it afterwards"

sb=$(new_sandbox); add_backup "$sb"
out=$(ui "$sb" PROJECTOR.sh $'2\ny\n\nq\n')
echo "$out" | grep -q 'All steps applied and verified' \
    && ok "runs the unlock through to the end" || bad "unlock did not complete"
[[ "$(dev "$sb" 'cmd package get-home-activity')" == "$NOVA"* ]] \
    && ok "home screen is Nova" || bad "home screen not changed"

out=$(ui "$sb" PROJECTOR.sh $'q\n')
echo "$out" | grep -qi 'launcher .*unlocked' && ok "header shows unlocked" || bad "header still says locked"
echo "$out" | grep -qi 'already unlocked' && ok "menu stops offering it" || bad "menu still offers the unlock"
rm -rf "$sb"

# ---------------------------------------------------------------------------
head_ "PROJECTOR.sh runs a backup to a verified result"

sb=$(new_sandbox)
out=$(ui "$sb" PROJECTOR.sh $'1\n\nq\n' env STREAM_CHUNK_MB=8)
echo "$out" | grep -qi 'Backup complete and verified' \
    && ok "reports a verified backup" || bad "backup did not complete"
img=$(find "$sb/run" -name full-system-backup.img -print -quit)
if [[ -n "$img" ]] && cmp -s "$img" "$sb/state/blockdev"; then
    ok "image is byte-identical to the device"
else
    bad "image differs from the device"
fi
rm -rf "$sb"

# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]]
