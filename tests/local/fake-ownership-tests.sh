#!/bin/bash
set -uo pipefail
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LOCAL_DIR/lifecycle.sh"
fake=${PT_FAKE_ADB_CANONICAL:-"$LOCAL_DIR/../fake-adb/adb"}
state=$(mktemp -d)
legacy=0
if [[ "${1:-}" == --legacy ]]; then
    legacy=1
    # Bound the old foreground sleep in a disposable copy, never the real fake.
    git show HEAD:tests/fake-adb/adb | sed 's/sleep 600/sleep 2/' > "$state/adb"
    chmod +x "$state/adb"
    fake="$state/adb"
fi
witness=
cleanup() {
    child_release_all
    if [[ -n "$witness" ]]; then
        builtin kill "$witness" 2>/dev/null || true
        wait "$witness" 2>/dev/null || true
    fi
    # The old fixture has no trap; let its shortened sleep expire without signalling it.
    if [[ "${legacy:-0}" == 1 ]]; then sleep 2; fi
    rm -rf "$state"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
dd if=/dev/zero of="$state/blockdev" bs=1024 count=4 2>/dev/null
sleep 30 & witness=$!
child_spawn fake env FAKE_ADB_STATE="$state" FAKE_ADB_HANG_STREAM_ONCE=1 \
    "$fake" exec-out 'dd if=/dev/block/mmcblk0 bs=1024 count=4' > "$state/output"
fake_pid=$CHILD_PID
sleep_pid=
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    sleep_pid=$(ps -axo pid=,ppid=,comm= | awk -v parent="$fake_pid" '$2 == parent && $3 ~ /(^|\/)sleep$/ { print $1 }')
    [[ -n "$sleep_pid" ]] && break
    sleep 0.05
done
if [[ -z "$sleep_pid" ]] || ! builtin kill -0 "$fake_pid" 2>/dev/null || ! builtin kill -0 "$sleep_pid" 2>/dev/null; then
    echo '[FAIL] positive control did not observe the fake and its live sleep child'
    exit 1
fi
echo "ownership control: fake=$fake_pid sleep=$sleep_pid witness=$witness all alive"
child_release_all
if builtin kill -0 "$fake_pid" 2>/dev/null || builtin kill -0 "$sleep_pid" 2>/dev/null; then
    echo '[FAIL] releasing the fake left its sleep alive'
    exit 1
fi
if ! builtin kill -0 "$witness" 2>/dev/null; then
    echo '[FAIL] unrelated witness did not survive'
    exit 1
fi
echo '[PASS] fake and its sleep exited; unrelated witness survives'
