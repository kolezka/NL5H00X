#!/bin/bash
# Controller-authorized discrimination: the edited suite runs outside run.sh.
set -uo pipefail
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$(cd "$LOCAL_DIR/../.." && pwd)"
PT_TEST_BASH=/opt/homebrew/bin/bash
PT_TEST_RG=$(command -v rg)
PT_TEST_PYTHON=/usr/bin/python3
[[ -x "$PT_TEST_PYTHON" && -f "$LOCAL_DIR/supervise.py" ]] || exit 2
PT_CONTROL_DIR=$(mktemp -d)
PT_SENTINEL_LOG="$PT_CONTROL_DIR/sentinel.log"
PT_FAKE_ADB_CANONICAL="$WT/tests/fake-adb/adb"
FAKE_ADB_STATE="$PT_CONTROL_DIR/state"
bash_real=$(/usr/bin/python3 -c 'import os; print(os.path.realpath("/opt/homebrew/bin/bash"))')
mkdir -p "$FAKE_ADB_STATE" "$PT_CONTROL_DIR/sentinel"
cp "$LOCAL_DIR/sentinel-adb" "$PT_CONTROL_DIR/sentinel/adb"
chmod +x "$PT_CONTROL_DIR/sentinel/adb"
: > "$PT_SENTINEL_LOG"
PATH="$WT/tests/fake-adb:$PT_CONTROL_DIR/sentinel:${bash_real%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PT_TEST_BASH PT_TEST_RG PT_TEST_PYTHON PT_CONTROL_DIR PT_SENTINEL_LOG PT_FAKE_ADB_CANONICAL FAKE_ADB_STATE PATH
source "$LOCAL_DIR/lifecycle.sh"
trap child_release_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source "$LOCAL_DIR/controls.sh"
controls_run || exit 1
printf 'direct suite evidence: %s\n' "$PT_CONTROL_DIR"
child_spawn direct-suite "$PT_TEST_PYTHON" "$LOCAL_DIR/supervise.py" \
    --timeout 120 --grace 0.5 --state "$PT_CONTROL_DIR/direct-suite.supervisor.log" -- \
    "$PT_TEST_BASH" "$WT/tests/run-tests.sh" > "$PT_CONTROL_DIR/direct-suite.log" 2>&1
pid=$CHILD_PID
attempt=0
while child_active "$pid"; do
    attempt=$((attempt + 1))
    if [[ "$attempt" == 20 ]]; then
        "$PT_TEST_BASH" "$LOCAL_DIR/capture-tree.sh" "$pid" "$PT_CONTROL_DIR/stall"
    fi
    sleep 1
done
child_wait_reap "$pid"; rc=$?
cat "$PT_CONTROL_DIR/direct-suite.log"
printf 'direct suite exit=%s\n' "$rc"
[[ ! -s "$PT_SENTINEL_LOG" ]] || { echo '[FAIL] sentinel was reached'; exit 1; }
exit "$rc"
