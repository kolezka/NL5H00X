#!/bin/bash
set -uo pipefail
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$LOCAL_DIR/lifecycle.sh" ]]; then
    echo '[FAIL] owned-child lifecycle is not implemented'
    exit 1
fi
source "$LOCAL_DIR/lifecycle.sh"
if [[ "${1:-}" == --cancellation-fixture ]]; then
    trap child_release_all EXIT
    trap 'exit 143' TERM
    child_spawn nested sleep 30
    printf '%s\n' "$CHILD_PID" > "$2/child"
    child_wait_reap "$CHILD_PID"
    exit 0
fi
control=$(mktemp -d)
PASS=0; FAIL=0
ok() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
witness=
cleanup() {
    child_release_all
    if [[ -n "$witness" ]]; then
        builtin kill "$witness" 2>/dev/null || true
        wait "$witness" 2>/dev/null || true
    fi
    rm -rf "$control"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
child_release_all
[[ -z "$CHILD_PIDS" ]] && ok 'empty registry is a no-op' || bad 'empty registry'
child_spawn normal "$BASH" -c 'exit 0'
pid=$CHILD_PID
child_wait_reap "$pid"; rc=$?
[[ "$rc" == 0 && -z "$CHILD_PIDS" ]] && ok 'normal exit is reaped and removed' || bad 'normal exit'
child_spawn status "$BASH" -c 'exit 7'
pid=$CHILD_PID
child_wait_reap "$pid"; rc=$?
[[ "$rc" == 7 && -z "$CHILD_PIDS" ]] && ok 'child status 7 is preserved' || bad 'exit status lost'
child_spawn exited "$BASH" -c 'exit 0'
pid=$CHILD_PID
wait "$pid"
child_release_all
[[ -z "$CHILD_PIDS" ]] && ok 'already-exited child is removed' || bad 'already-exited child'
sleep 30 & witness=$!
child_spawn cancel sleep 30
pid=$CHILD_PID
child_release_all
if ! builtin kill -0 "$pid" 2>/dev/null && [[ -z "$CHILD_PIDS" ]]; then
    ok 'cancellation terminates and reaps tracked child'
else
    bad 'cancellation left a child'
fi
builtin kill -0 "$witness" 2>/dev/null && ok 'untracked witness survives' || bad 'witness was signalled'
child_wait_reap "$witness"; rc=$?
[[ "$rc" == 127 ]] && ok 'untracked wait is refused' || bad 'untracked wait accepted'
child_spawn cancellation-fixture "$BASH" "$LOCAL_DIR/lifecycle-tests.sh" --cancellation-fixture "$control"
fixture_pid=$CHILD_PID
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$control/child" ]] && break
    sleep 0.05
done
if [[ -s "$control/child" ]]; then
    nested_pid=$(cat "$control/child")
    builtin kill -0 "$nested_pid" 2>/dev/null || bad 'nested child positive control'
    child_release_all
    if ! builtin kill -0 "$fixture_pid" 2>/dev/null && ! builtin kill -0 "$nested_pid" 2>/dev/null; then
        ok 'TERM cancellation trap releases its own child'
    else
        bad 'TERM cancellation left a nested child'
    fi
else
    bad 'cancellation fixture was not ready'
    child_release_all
fi
child_spawn stubborn "$BASH" -c 'trap "" TERM; printf ready > "$1"; while :; do :; done' _ "$control/ready"
stubborn_pid=$CHILD_PID
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$control/ready" ]] && break
    sleep 0.05
done
[[ -s "$control/ready" ]] || bad 'stubborn child positive control'
child_release_all
if ! builtin kill -0 "$stubborn_pid" 2>/dev/null && [[ -z "$CHILD_PIDS" ]]; then
    ok 'TERM-resistant child is killed and reaped after bounded grace'
else
    bad 'TERM-resistant child survived'
fi
for test in reaper-tests.sh fake-ownership-tests.sh sandbox-tests.sh forwarding-tests.sh \
    supervisor-tests.sh runner-tests.sh bypass-audit-tests.sh; do
    if "$BASH" "$LOCAL_DIR/$test"; then
        ok "$test"
    else
        bad "$test"
    fi
done
echo "lifecycle: passed: $PASS   failed: $FAIL"
[[ "$FAIL" == 0 ]]
