#!/bin/bash
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_ADB_DIR=${PT_FAKE_ADB_CANONICAL:-"$TEST_DIR/fake-adb/adb"}
FAKE_ADB_DIR=${FAKE_ADB_DIR%/*}
control=$(mktemp -d)
trap 'rm -rf "$control"' EXIT
SCRIPTS="$control/scripts"
mkdir -p "$SCRIPTS" "$control/state" "$control/run" "$control/apks"
cat > "$SCRIPTS/UNLOCK.sh" <<'STUB'
#!/bin/bash
printf 'probe=%s argc=%s arg=%s\n' "${PT_FORWARD_PROBE:-unset}" "$#" "${1:-missing}"
STUB
# Load the real forwarding helpers, not the suite's scenarios or reaper.
sed -n '/^unlock() {/,/^home_now()/p' "$TEST_DIR/unlock-tests.sh" > "$control/helpers.sh"
source "$control/helpers.sh"
declare -F unlock >/dev/null && declare -F dev >/dev/null || { echo '[FAIL] helper extraction failed'; exit 1; }
PASS=0; FAIL=0
ok() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
out=$(unlock "$control" --status)
if [[ "$out" == *'probe=unset argc=1 arg=--status'* && "$out" == *'RC=0'* ]]; then
    ok 'unlock forwards arguments with an empty environment array'
else
    bad "unlock empty environment: $out"
fi
out=$(unlock "$control" 'PT_FORWARD_PROBE=two words' --status)
if [[ "$out" == *'probe=two words argc=1 arg=--status'* && "$out" == *'RC=0'* ]]; then
    ok 'unlock preserves a spaced environment value'
else
    bad "unlock nonempty environment: $out"
fi
out=$(dev "$control" whoami); rc=$?
[[ "$rc" == 0 && "$out" == root ]] && ok 'dev executes fake with no environment overrides' || bad 'dev empty environment failed'
out=$(dev "$control" FAKE_ADB_PROPAGATE_RC=1 '__pt_invalid_remote'); rc=$?
if [[ "$rc" == 127 ]] && grep -Fxq $'adb\tshell\t__pt_invalid_remote' "$control/state/invocations.log"; then
    ok 'dev propagates logged fake failure with an environment override'
else
    bad 'dev failure was swallowed or did not come from the fake'
fi
echo "forwarding: passed: $PASS   failed: $FAIL"
[[ "$FAIL" == 0 ]]
