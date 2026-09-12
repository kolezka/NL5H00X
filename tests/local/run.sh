#!/bin/bash
# Known toolkit invocation paths resolve to the stand-in; an absent fake fails closed.
# This is not an operating-system sandbox or a security boundary.
# The bypass audit covers all of scripts/, including the transport adapter.
set -uo pipefail
LC_ALL=C
export LC_ALL
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$(cd "$LOCAL_DIR/../.." && pwd)"

fail_fake_path() {
    printf '%s fake must be an absolute executable file named adb\n' "$1" >&2
    exit 2
}

if [[ "${PT_TEST_BASH:-}" != /* || ! -f "${PT_TEST_BASH:-}" || ! -x "${PT_TEST_BASH:-}" ]]; then
    echo 'PT_TEST_BASH must be an absolute executable Bash path' >&2
    exit 2
fi
if ! "$PT_TEST_BASH" -c '[[ -n "${BASH_VERSION:-}" ]]' >/dev/null 2>&1; then
    echo 'PT_TEST_BASH did not execute Bash' >&2
    exit 2
fi
PT_FAKE_ADB_CANONICAL=${PT_FAKE_ADB_CANONICAL:-"$WT/tests/fake-adb/adb"}
if [[ "$PT_FAKE_ADB_CANONICAL" != /* || "${PT_FAKE_ADB_CANONICAL##*/}" != adb \
   || ! -f "$PT_FAKE_ADB_CANONICAL" || ! -x "$PT_FAKE_ADB_CANONICAL" ]]; then
    fail_fake_path canonical
fi
fake_dir="$(cd "${PT_FAKE_ADB_CANONICAL%/*}" && pwd -P)" || exit 2
PT_FAKE_ADB_CANONICAL="$fake_dir/adb"
PT_TRANSPORT=${PT_TRANSPORT:-fake}
if [[ "$PT_TRANSPORT" != fake ]]; then
    echo 'test runner requires PT_TRANSPORT=fake' >&2
    exit 2
fi
if [[ "${PT_ADB_BIN+x}" == x ]]; then
    if [[ "$PT_ADB_BIN" != /* || "${PT_ADB_BIN##*/}" != adb || ! -f "$PT_ADB_BIN" || ! -x "$PT_ADB_BIN" ]]; then
        fail_fake_path adapter
    fi
    adb_dir="$(cd "${PT_ADB_BIN%/*}" && pwd -P)" || exit 2
    PT_ADB_BIN="$adb_dir/adb"
    [[ "$PT_ADB_BIN" == "$PT_FAKE_ADB_CANONICAL" ]] || {
        echo 'adapter fake must match the canonical fake' >&2
        exit 2
    }
else
    PT_ADB_BIN="$PT_FAKE_ADB_CANONICAL"
fi
if [[ "${TOOLKIT_SCRIPTS:-$WT/scripts}" != "$WT/scripts" ]]; then
    echo 'TOOLKIT_SCRIPTS must match this runner worktree and bypass baseline' >&2
    exit 2
fi
PT_TEST_RG=${PT_TEST_RG:-$(command -v rg)}
[[ "$PT_TEST_RG" == /* && -x "$PT_TEST_RG" ]] || { echo 'rg is required for the bypass audit' >&2; exit 2; }
PT_TEST_PYTHON=${PT_TEST_PYTHON:-/usr/bin/python3}
[[ "$PT_TEST_PYTHON" == /* && -x "$PT_TEST_PYTHON" ]] || { echo 'Python 3 is required for bounded supervision' >&2; exit 2; }
PT_TEST_SUPERVISOR="$LOCAL_DIR/supervise.py"
[[ -f "$PT_TEST_SUPERVISOR" ]] || { echo 'bounded supervisor is missing' >&2; exit 2; }
PT_TEST_TIMEOUT_SECS=${PT_TEST_TIMEOUT_SECS:-120}
case "$PT_TEST_TIMEOUT_SECS" in
    ''|*[!0-9]*|0) echo 'PT_TEST_TIMEOUT_SECS must be a positive integer' >&2; exit 2 ;;
esac
PT_TEST_TIMEOUT_GRACE=${PT_TEST_TIMEOUT_GRACE:-0.5}
case "$PT_TEST_TIMEOUT_GRACE" in
    ''|*[!0-9.]*|.*|*.*.*|0|0.0) echo 'PT_TEST_TIMEOUT_GRACE must be a positive number' >&2; exit 2 ;;
esac

for directory in /usr/bin /bin /usr/sbin /sbin; do
    if [[ -e "$directory/adb" ]]; then
        echo "refusing PATH directory containing another adb: $directory" >&2
        exit 2
    fi
done
PT_CONTROL_DIR=$(mktemp -d) || exit 2
PT_SENTINEL_LOG="$PT_CONTROL_DIR/sentinel.log"
FAKE_ADB_STATE="$PT_CONTROL_DIR/state"
mkdir -p "$PT_CONTROL_DIR/sentinel" "$PT_CONTROL_DIR/bash-shim" "$FAKE_ADB_STATE"
cp "$LOCAL_DIR/sentinel-adb" "$PT_CONTROL_DIR/sentinel/adb" || exit 2
chmod +x "$PT_CONTROL_DIR/sentinel/adb"
cat > "$PT_CONTROL_DIR/bash-shim/bash" <<'BASH_SHIM'
#!/bin/sh
exec "$PT_TEST_BASH" "$@"
BASH_SHIM
chmod +x "$PT_CONTROL_DIR/bash-shim/bash"
: > "$PT_SENTINEL_LOG"
PATH="$fake_dir:$PT_CONTROL_DIR/sentinel:$PT_CONTROL_DIR/bash-shim:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH PT_TEST_BASH PT_TEST_RG PT_TEST_PYTHON PT_FAKE_ADB_CANONICAL PT_ADB_BIN PT_TRANSPORT
export PT_CONTROL_DIR PT_SENTINEL_LOG FAKE_ADB_STATE
hash -r
source "$LOCAL_DIR/lifecycle.sh"
RUNNER_SIGNAL_STATUS=
RUNNER_CLEANING=0
runner_cleanup() {
    local status=$?
    trap - EXIT
    trap '' INT TERM
    [[ -z "$RUNNER_SIGNAL_STATUS" ]] || status=$RUNNER_SIGNAL_STATUS
    if [[ "$RUNNER_CLEANING" == 0 ]]; then
        RUNNER_CLEANING=1
        child_release_all
        if [[ -s "$PT_SENTINEL_LOG" ]]; then
            echo '[FAIL] sentinel was reached during the run' >&2
            cat "$PT_SENTINEL_LOG" >&2
            [[ "$status" != 0 ]] || status=1
        fi
        if [[ "$status" != 0 || "${PT_KEEP_RUNNER_EVIDENCE:-0}" == 1 ]]; then
            echo "[KEEP] runner evidence: $PT_CONTROL_DIR"
        else
            rm -rf "$PT_CONTROL_DIR"
        fi
        RUNNER_CLEANING=0
    fi
    exit "$status"
}
runner_cancel() {
    local status="$1"
    if [[ -z "$RUNNER_SIGNAL_STATUS" ]]; then
        RUNNER_SIGNAL_STATUS=$status
        trap '' INT TERM
    fi
    exit "$RUNNER_SIGNAL_STATUS"
}
trap runner_cleanup EXIT
trap 'runner_cancel 130' INT
trap 'runner_cancel 143' TERM

selected=$(command -v adb)
if [[ "$selected" != "$PT_FAKE_ADB_CANONICAL" ]]; then
    echo "[FAIL] selected adb is not canonical: $selected" >&2
    exit 2
fi
selected_identity=$("$PT_TEST_BASH" -c 'printf "%s\n" "$BASH:$BASH_VERSION"') || exit 2
nested_identity=$(bash -c 'printf "%s\n" "$BASH:$BASH_VERSION"') || exit 2
if [[ "$selected_identity" != "$nested_identity" || "$(command -v bash)" != "$PT_CONTROL_DIR/bash-shim/bash" ]]; then
    echo '[FAIL] nested bash did not use the exact selected interpreter' >&2
    exit 2
fi
echo '[PASS] nested bash uses the exact selected interpreter'
printf 'selected adb: %s\nrequested suite Bash: %s\nPATH Bash shim: %s\nPATH: %s\n' \
    "$selected" "$PT_TEST_BASH" "$(command -v bash)" "$PATH" | tee "$PT_CONTROL_DIR/routing.log"

if [[ "${PT_TEST_PREFLIGHT_ONLY:-0}" == 1 ]]; then
    echo '[PASS] fake-only runner preflight completed'
    exit 0
fi

source "$LOCAL_DIR/controls.sh"
controls_run || exit 1
"$PT_TEST_BASH" "$LOCAL_DIR/bypass-audit.sh" --check || exit 1

contract_list="$PT_CONTROL_DIR/contracts.list"
: > "$contract_list"
for contract in "$WT"/tests/contracts/*.sh; do
    [[ -f "$contract" ]] || continue
    printf '%s\n' "${contract#$WT/tests/}" >> "$contract_list"
done
LC_ALL=C sort -o "$contract_list" "$contract_list"

suite_plan="$PT_CONTROL_DIR/suites.list"
printf '%s\n' local/lifecycle-tests.sh > "$suite_plan"
PT_TEST_SCOPE=${PT_TEST_SCOPE:-all}
case "$PT_TEST_SCOPE" in
    all)
        cat "$contract_list" >> "$suite_plan"
        printf '%s\n' run-tests.sh unlock-tests.sh ui-tests.sh >> "$suite_plan"
        ;;
    contracts)
        cat "$contract_list" >> "$suite_plan"
        ;;
    local-legacy)
        printf '%s\n' run-tests.sh unlock-tests.sh ui-tests.sh >> "$suite_plan"
        ;;
    local)
        ;;
    *)
        echo 'PT_TEST_SCOPE must be all, contracts, local-legacy, or local' >&2
        exit 2
        ;;
esac

parse_summary() {
    "$PT_TEST_PYTHON" - "$1" "$2" <<'PY'
import re
import sys
from pathlib import Path

suite = sys.argv[1]
stem = Path(suite).stem.casefold()
expected_labels = {stem}
if stem.startswith("characterize-"):
    expected_labels.add(stem[len("characterize-"):])
if stem.endswith("-tests"):
    expected_labels.add(stem[:-len("-tests")])
requires_label = suite == "local/lifecycle-tests.sh"
if requires_label:
    expected_labels = {"lifecycle"}

patterns = (
    (re.compile(r"\s*([a-z0-9][a-z0-9_-]*):\s*passed:\s*(\d+)\s+failed:\s*(\d+)\s*", re.I), 1, 2, 3),
    (re.compile(r"\s*passed:\s*(\d+)\s+failed:\s*(\d+)\s*", re.I), None, 1, 2),
    (re.compile(r"\s*([a-z0-9][a-z0-9_-]*):\s*passed=(\d+)\s+failed=(\d+)\s*", re.I), 1, 2, 3),
    (re.compile(r"\s*SUMMARY\s+([a-z0-9][a-z0-9_-]*)\s+passed=(\d+)\s+failed=(\d+)(?:\s+exit=\d+)?\s*", re.I), 1, 2, 3),
    (re.compile(r"\s*passed=(\d+)\s+failed=(\d+)\s*", re.I), None, 1, 2),
    (re.compile(r"\s*Summary:\s*(\d+)\s+passed,\s*(\d+)\s+failed\s*", re.I), None, 1, 2),
)
trailers = (
    re.compile(r"\s*"),
    re.compile(r"\s*=+\s*"),
    re.compile(r"Retained sandbox:\s+.*"),
    re.compile(r"\[CLEANUP ERROR\]\s+.*"),
)
lines = Path(sys.argv[2]).read_text(errors="replace").splitlines()
for index in range(len(lines) - 1, -1, -1):
    for pattern, label_group, pass_group, fail_group in patterns:
        match = pattern.fullmatch(lines[index])
        if match is None:
            continue
        if label_group is None:
            if requires_label:
                continue
        elif match.group(label_group).casefold() not in expected_labels:
            continue
        if all(any(trailer.fullmatch(line) for trailer in trailers) for line in lines[index + 1:]):
            print(match.group(pass_group), match.group(fail_group))
            raise SystemExit
PY
}

: > "$PT_CONTROL_DIR/summary.log"
run_suite() {
    local suite="$1" rc=0 summary pass fail result log_name state
    log_name=${suite//\//_}
    log="$PT_CONTROL_DIR/$log_name.log"
    state="$PT_CONTROL_DIR/$log_name.supervisor.log"
    printf 'SUITE %s interpreter=%s timeout=%ss\n' "$suite" "$PT_TEST_BASH" "$PT_TEST_TIMEOUT_SECS"
    child_spawn "$suite" "$PT_TEST_PYTHON" "$PT_TEST_SUPERVISOR" \
        --timeout "$PT_TEST_TIMEOUT_SECS" --grace "$PT_TEST_TIMEOUT_GRACE" --state "$state" -- \
        "$PT_TEST_BASH" "$WT/tests/$suite" > "$log" 2>&1
    pid=$CHILD_PID
    child_wait_reap "$pid" || rc=$?
    cat "$log"
    summary=$(parse_summary "$suite" "$log")
    if [[ -n "$summary" ]]; then
        set -- $summary
        pass="$1"
        fail="$2"
        printf 'SUMMARY %s passed: %s   failed: %s exit=%s interpreter=%s\n' \
            "$suite" "$pass" "$fail" "$rc" "$PT_TEST_BASH" | tee -a "$PT_CONTROL_DIR/summary.log"
        result=$rc
        [[ "$result" != 0 || "$fail" == 0 ]] || result=1
    else
        printf 'SUMMARY %s missing meaningful summary exit=%s interpreter=%s\n' \
            "$suite" "$rc" "$PT_TEST_BASH" | tee -a "$PT_CONTROL_DIR/summary.log"
        result=$rc
        [[ "$result" != 0 ]] || result=1
    fi
    if [[ "$rc" == 124 ]]; then
        echo "[FAIL] suite exceeded ${PT_TEST_TIMEOUT_SECS}s: $suite"
    fi
    return "$result"
}

failed=0
while IFS= read -r suite; do
    [[ -n "$suite" ]] || continue
    run_suite "$suite" || failed=$((failed + 1))
done < "$suite_plan"
cat "$PT_CONTROL_DIR/summary.log"
if [[ -s "$PT_SENTINEL_LOG" ]]; then
    echo '[FAIL] sentinel log is not empty'
    failed=$((failed + 1))
else
    echo '[PASS] sentinel not reached after its explicit detector control'
fi
printf 'RUN SUMMARY failed suites/checks: %s\n' "$failed"
[[ "$failed" == 0 ]]
