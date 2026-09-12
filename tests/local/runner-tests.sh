#!/bin/bash
set -uo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LOCAL_DIR/../.." && pwd)"
SUBJECT_ROOT=${PT_RUNNER_SUBJECT_ROOT:-$ROOT}
TEST_BASH=${PT_TEST_BASH:-$BASH}
RG=${PT_TEST_RG:-$(command -v rg)}
control=$(mktemp -d "${TMPDIR:-/tmp}/pt-runner.XXXXXX") || exit 2
PASS=0
FAIL=0
active_runner=
active_signal_ready=
active_witness=
active_witness_ready=

ok() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

is_active_child() {
    local child
    for child in $(jobs -pr); do
        [[ "$child" == "$1" ]] && return 0
    done
    return 1
}

cleanup() {
    local status=$? fixture_pid descendant_pid ready_token fixture_pgid descendant_pgid child_parent
    trap - EXIT INT TERM
    if [[ -n "$active_runner" ]] && is_active_child "$active_runner"; then
        builtin kill -TERM "$active_runner"
        wait "$active_runner" 2>/dev/null || true
    fi
    if [[ -n "$active_signal_ready" && -s "$active_signal_ready" ]]; then
        set -- $(cat "$active_signal_ready")
        fixture_pid="$1"
        descendant_pid="$2"
        ready_token="$3"
        fixture_pgid=$(ps -o pgid= -p "$fixture_pid" 2>/dev/null | tr -d ' ')
        descendant_pgid=$(ps -o pgid= -p "$descendant_pid" 2>/dev/null | tr -d ' ')
        child_parent=$(ps -o ppid= -p "$descendant_pid" 2>/dev/null | tr -d ' ')
        if [[ "$ready_token" == signal-token && -n "$fixture_pgid" && "$descendant_pgid" == "$fixture_pgid" && "$child_parent" == "$fixture_pid" ]]; then
            if builtin kill -0 "$descendant_pid" 2>/dev/null; then builtin kill -KILL "$descendant_pid"; fi
            if builtin kill -0 "$fixture_pid" 2>/dev/null; then builtin kill -KILL "$fixture_pid"; fi
        fi
    fi
    if [[ -n "$active_witness" && -s "$active_witness_ready" ]]; then
        set -- $(cat "$active_witness_ready")
        if [[ "$1" == "$active_witness" && "$2" == runner-witness ]] && builtin kill -0 "$active_witness" 2>/dev/null; then
            builtin kill -TERM "$active_witness"
            wait "$active_witness" 2>/dev/null || true
        fi
    fi
    if [[ "$status" != 0 || "$FAIL" != 0 || "${PT_KEEP_TEST_EVIDENCE:-0}" == 1 ]]; then
        printf '[KEEP] runner-test evidence: %s\n' "$control"
    else
        rm -rf "$control"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

copy_if_present() {
    [[ -e "$1" ]] && cp "$1" "$2"
}

make_suite() {
    local path="$1" summary="$2" status="$3" body="${4:-}"
    cat > "$path" <<EOF_SUITE
#!/bin/bash
$body
printf '%s\\n' '$summary'
exit $status
EOF_SUITE
    chmod +x "$path"
}

make_fixture() {
    local name="$1" repo file
    repo="$control/$name"
    mkdir -p "$repo/tests/local" "$repo/tests/fake-adb" "$repo/tests/contracts" "$repo/scripts/lib/transport"
    for file in run.sh lifecycle.sh controls.sh bypass-audit.sh sentinel-adb capture-tree.sh; do
        cp "$SUBJECT_ROOT/tests/local/$file" "$repo/tests/local/$file" || return 1
    done
    copy_if_present "$SUBJECT_ROOT/tests/local/supervise.py" "$repo/tests/local/supervise.py"
    cp "$SUBJECT_ROOT/tests/fake-adb/adb" "$repo/tests/fake-adb/adb" || return 1
    cp "$ROOT/scripts/lib/transport/select.sh" "$repo/scripts/lib/transport/select.sh" || return 1
    cp "$ROOT/scripts/lib/transport/adb.sh" "$repo/scripts/lib/transport/adb.sh" || return 1
    chmod +x "$repo/tests/local/run.sh" "$repo/tests/local/bypass-audit.sh" "$repo/tests/local/sentinel-adb" "$repo/tests/fake-adb/adb"
    [[ ! -e "$repo/tests/local/supervise.py" ]] || chmod +x "$repo/tests/local/supervise.py"
    make_suite "$repo/tests/local/lifecycle-tests.sh" 'lifecycle: passed: 1   failed: 0' 0 \
        'nested=$(bash -c '\''printf "%s" "$BASH"'\''); printf "nested-bash=%s\\n" "$nested"'
    make_suite "$repo/tests/run-tests.sh" '  passed: 1   failed: 0' 0
    make_suite "$repo/tests/unlock-tests.sh" '  passed: 1   failed: 0' 0
    make_suite "$repo/tests/ui-tests.sh" '  passed: 1   failed: 0' 0
    make_suite "$repo/tests/contracts/a-colon.sh" 'a-colon: passed: 2   failed: 0' 0
    make_suite "$repo/tests/contracts/b-equals.sh" 'b-equals: passed=3 failed=0' 0
    make_suite "$repo/tests/contracts/c-words.sh" 'Summary: 4 passed, 0 failed' 0
    make_suite "$repo/tests/contracts/characterize-d-summary-exit.sh" \
        'SUMMARY d-summary-exit passed=5 failed=0 exit=0' 0
    rm -f "$repo/tests/local/bypass-baseline.txt"
    PT_TEST_RG="$RG" "$TEST_BASH" "$repo/tests/local/bypass-audit.sh" --record > "$repo/baseline-record.log" 2>&1 || return 1
    printf '%s\n' "$repo"
}

run_runner() {
    local repo="$1" output="$2" scope="${3:-default}" selected_bash="${4:-$TEST_BASH}" timeout_bin="${5:-}"
    local rc
    if [[ "$scope" == default ]]; then
        (
            unset PT_TEST_SCOPE PT_TEST_PREFLIGHT_ONLY
            if [[ -n "$timeout_bin" ]]; then
                PT_TEST_BASH="$selected_bash" PT_TEST_RG="$RG" PT_TEST_TIMEOUT_BIN="$timeout_bin" PT_KEEP_RUNNER_EVIDENCE=1 \
                    "$selected_bash" "$repo/tests/local/run.sh" > "$output" 2>&1
            else
                PT_TEST_BASH="$selected_bash" PT_TEST_RG="$RG" PT_KEEP_RUNNER_EVIDENCE=1 \
                    "$selected_bash" "$repo/tests/local/run.sh" > "$output" 2>&1
            fi
        )
    else
        if [[ -n "$timeout_bin" ]]; then
            PT_TEST_BASH="$selected_bash" PT_TEST_RG="$RG" PT_TEST_TIMEOUT_BIN="$timeout_bin" PT_TEST_SCOPE="$scope" PT_KEEP_RUNNER_EVIDENCE=1 \
                "$selected_bash" "$repo/tests/local/run.sh" > "$output" 2>&1
        else
            PT_TEST_BASH="$selected_bash" PT_TEST_RG="$RG" PT_TEST_SCOPE="$scope" PT_KEEP_RUNNER_EVIDENCE=1 \
                "$selected_bash" "$repo/tests/local/run.sh" > "$output" 2>&1
        fi
    fi
    rc=$?
    return "$rc"
}

repo=$(make_fixture no-timeout) || { bad 'create no-timeout fixture'; exit 1; }
run_runner "$repo" "$repo/output" default "$TEST_BASH" /definitely/missing-timeout
rc=$?
if [[ "$rc" == 0 ]] \
   && grep -q '^\[PASS\] adapter route decoded token ' "$repo/output" \
   && grep -q '^\[PASS\] legacy PATH route decoded token ' "$repo/output" \
   && grep -q '^\[PASS\] adapter missing fake aborted with status 2 before suites and sentinel$' "$repo/output" \
   && grep -q '^\[PASS\] legacy non-executable fake aborted with status 2 before suites and sentinel$' "$repo/output"; then
    ok 'runner has no GNU timeout dependency and validates both fake routes'
else
    bad "runner timeout or route controls rc=$rc"
fi

repo=$(make_fixture discovery) || { bad 'create discovery fixture'; exit 1; }
run_runner "$repo" "$repo/output"
rc=$?
actual=$(awk '/^SUITE / { print $2 }' "$repo/output" | paste -sd ' ' -)
expected='local/lifecycle-tests.sh contracts/a-colon.sh contracts/b-equals.sh contracts/c-words.sh contracts/characterize-d-summary-exit.sh run-tests.sh unlock-tests.sh ui-tests.sh'
if [[ "$rc" == 0 && "$actual" == "$expected" ]]; then
    ok 'default discovery runs contract shell files in lexical order plus fixed suites'
else
    bad "default discovery rc=$rc order=<$actual>"
fi

repo=$(make_fixture failed-contract) || { bad 'create failing contract fixture'; exit 1; }
make_suite "$repo/tests/contracts/b-equals.sh" 'b-equals: passed=0 failed=1' 9
run_runner "$repo" "$repo/output" contracts
rc=$?
if [[ "$rc" == 1 ]] \
   && grep -q '^SUMMARY contracts/b-equals.sh passed: 0   failed: 1 exit=9 ' "$repo/output" \
   && grep -q '^RUN SUMMARY failed suites/checks: 1$' "$repo/output"; then
    ok 'a discovered failing suite fails the runner and preserves exit 9'
else
    bad "failing discovered suite rc=$rc"
fi

repo=$(make_fixture missing-summary) || { bad 'create missing-summary fixture'; exit 1; }
make_suite "$repo/tests/contracts/b-equals.sh" 'no numeric result here' 0
run_runner "$repo" "$repo/output" contracts
rc=$?
if [[ "$rc" == 1 ]] && grep -q '^SUMMARY contracts/b-equals.sh missing meaningful summary exit=0 ' "$repo/output"; then
    ok 'a zero-exit suite without a meaningful summary cannot pass'
else
    bad "missing summary rc=$rc"
fi

repo=$(make_fixture nested-summary-only) || { bad 'create nested-summary-only fixture'; exit 1; }
make_suite "$repo/tests/local/nested-suite.sh" 'runner-regressions: passed: 5   failed: 0' 0
cat > "$repo/tests/local/lifecycle-tests.sh" <<'EOF_NESTED_SUMMARY'
#!/bin/bash
"$BASH" "$(dirname "$0")/nested-suite.sh"
exit 0
EOF_NESTED_SUMMARY
chmod +x "$repo/tests/local/lifecycle-tests.sh"
run_runner "$repo" "$repo/output" local
rc=$?
if [[ "$rc" == 1 ]] \
   && grep -q '^SUMMARY local/lifecycle-tests.sh missing meaningful summary exit=0 ' "$repo/output" \
   && ! grep -q '^SUMMARY local/lifecycle-tests.sh passed:' "$repo/output"; then
    ok 'lifecycle cannot pass on a nested suite summary without its own footer'
else
    bad "nested summary without lifecycle footer rc=$rc"
fi

repo=$(make_fixture terminal-summary-trailer) || { bad 'create terminal-summary-trailer fixture'; exit 1; }
cat > "$repo/tests/local/lifecycle-tests.sh" <<'EOF_SUMMARY_TRAILER'
#!/bin/bash
printf 'lifecycle: passed: 1   failed: 0\n'
printf '%s\n' '======================================'
exit 0
EOF_SUMMARY_TRAILER
chmod +x "$repo/tests/local/lifecycle-tests.sh"
run_runner "$repo" "$repo/output" local
rc=$?
if [[ "$rc" == 0 ]] \
   && grep -q '^SUMMARY local/lifecycle-tests.sh passed: 1   failed: 0 exit=0 ' "$repo/output"; then
    ok 'a lifecycle footer remains valid before its separator trailer'
else
    bad "lifecycle summary trailer rc=$rc"
fi

repo=$(make_fixture nonzero-summary) || { bad 'create nonzero-summary fixture'; exit 1; }
cat > "$repo/tests/contracts/b-equals.sh" <<'EOF_NONZERO_SUMMARY'
#!/bin/bash
printf 'b-equals: passed=3 failed=0\n'
printf 'Retained sandbox: /tmp/runner-contract\n'
exit 7
EOF_NONZERO_SUMMARY
chmod +x "$repo/tests/contracts/b-equals.sh"
run_runner "$repo" "$repo/output" contracts
rc=$?
if [[ "$rc" == 1 ]] \
   && grep -q '^SUMMARY contracts/b-equals.sh passed: 3   failed: 0 exit=7 ' "$repo/output" \
   && grep -q '^Retained sandbox: /tmp/runner-contract$' "$repo/output"; then
    ok 'a nonzero suite exit cannot pass despite its summary and diagnostic trailer'
else
    bad "nonzero passing summary rc=$rc"
fi

repo=$(make_fixture empty-glob) || { bad 'create empty-glob fixture'; exit 1; }
rm -f "$repo/tests/contracts/"*.sh
run_runner "$repo" "$repo/output"
rc=$?
if [[ "$rc" == 0 ]] && ! grep -q '^SUITE contracts/' "$repo/output"; then
    ok 'empty contract glob is harmless under nounset'
else
    bad "empty contract glob rc=$rc"
fi

repo=$(make_fixture bash-shim) || { bad 'create bash-shim fixture'; exit 1; }
mkdir -p "$repo/interpreters"
cat > "$repo/interpreters/bash-5.2" <<'EOF_SELECTED'
#!/bin/sh
exec /bin/bash "$@"
EOF_SELECTED
cat > "$repo/interpreters/bash" <<EOF_WRONG
#!/bin/sh
printf 'wrong sibling bash invoked\\n' >> '$repo/wrong-bash.log'
exit 97
EOF_WRONG
chmod +x "$repo/interpreters/bash-5.2" "$repo/interpreters/bash"
run_runner "$repo" "$repo/output" default "$repo/interpreters/bash-5.2"
rc=$?
if [[ "$rc" == 0 ]] \
   && grep -q '^\[PASS\] nested bash uses the exact selected interpreter$' "$repo/output" \
   && [[ ! -e "$repo/wrong-bash.log" ]]; then
    ok 'controlled bash shim ignores a different sibling named bash'
else
    bad "selected interpreter shim rc=$rc"
fi

repo=$(make_fixture sentinel-repeated-signal) || { bad 'create sentinel-repeated-signal fixture'; exit 1; }
rm -f "$repo/tests/contracts/"*.sh
signal_evidence="$repo/signal-fixture"
mkdir -p "$signal_evidence"
cat > "$repo/tests/run-tests.sh" <<'EOF_HANG'
#!/bin/bash
trap 'printf "TERM signal-token\\n" >> "$PT_RUNNER_SIGNAL_EVIDENCE/suite-signals"' TERM
trap 'printf "INT signal-token\\n" >> "$PT_RUNNER_SIGNAL_EVIDENCE/suite-signals"' INT
"$BASH" -c 'trap "" INT TERM; while :; do sleep 1; done' &
descendant=$!
printf 'sentinel signal-token\n' >> "$PT_SENTINEL_LOG"
printf '%s %s %s\n' "$$" "$descendant" signal-token > "$PT_RUNNER_SIGNAL_EVIDENCE/ready"
while :; do sleep 1; done
EOF_HANG
chmod +x "$repo/tests/run-tests.sh"
witness_ready="$repo/witness-ready"
"$TEST_BASH" -c 'printf "%s %s\n" "$$" runner-witness > "$1"; sleep 30' _ "$witness_ready" &
witness=$!
active_witness=$witness
active_witness_ready=$witness_ready
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -s "$witness_ready" ]] && break
    sleep 0.05
done
PT_RUNNER_SIGNAL_EVIDENCE="$signal_evidence" PT_TEST_BASH="$TEST_BASH" PT_TEST_RG="$RG" \
    PT_TEST_SCOPE=local-legacy PT_KEEP_RUNNER_EVIDENCE=1 "$TEST_BASH" "$repo/tests/local/run.sh" > "$repo/output" 2>&1 &
runner_pid=$!
active_runner=$runner_pid
active_signal_ready="$signal_evidence/ready"
ready=
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
    if [[ -s "$signal_evidence/ready" ]]; then ready=1; break; fi
    sleep 0.05
done
if [[ -n "$ready" ]]; then
    set -- $(cat "$signal_evidence/ready")
    fixture_pid="$1"
    descendant_pid="$2"
    ready_token="$3"
    fixture_pgid=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
    descendant_pgid=$(ps -o pgid= -p "$descendant_pid" | tr -d ' ')
    set -- $(cat "$witness_ready")
    witness_recorded_pid="$1"
    witness_token="$2"
    if [[ "$ready_token" == signal-token ]] \
       && [[ -n "$fixture_pgid" && "$descendant_pgid" == "$fixture_pgid" ]] \
       && [[ "$witness_recorded_pid" == "$witness" && "$witness_token" == runner-witness ]] \
       && builtin kill -0 "$runner_pid" 2>/dev/null \
       && builtin kill -0 "$fixture_pid" 2>/dev/null \
       && builtin kill -0 "$descendant_pid" 2>/dev/null \
       && builtin kill -0 "$witness" 2>/dev/null; then
        builtin kill -TERM "$runner_pid"
        cleanup_started=
        for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            if grep -q '^TERM signal-token$' "$signal_evidence/suite-signals" 2>/dev/null; then cleanup_started=1; break; fi
            sleep 0.05
        done
        child_parent=$(ps -o ppid= -p "$descendant_pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$cleanup_started" && "$child_parent" == "$fixture_pid" ]] \
           && builtin kill -0 "$runner_pid" 2>/dev/null; then
            builtin kill -TERM "$runner_pid"
        else
            bad 'runner was not still owned after cleanup reached its suite group'
        fi
        wait "$runner_pid" 2>/dev/null
        rc=$?
        printf '%s\n' "$rc" > "$signal_evidence/runner-exit-status"
        active_runner=
        if [[ "$rc" == 143 ]] \
           && ! builtin kill -0 "$fixture_pid" 2>/dev/null \
           && ! builtin kill -0 "$descendant_pid" 2>/dev/null \
           && builtin kill -0 "$witness" 2>/dev/null \
           && grep -q '^\[FAIL\] sentinel was reached during the run$' "$repo/output" \
           && grep -q '^sentinel signal-token$' "$repo/output" \
           && grep -q '^\[KEEP\] runner evidence: ' "$repo/output"; then
            ok 'runner records sentinel failure and preserves exit 143 across repeated TERM cleanup'
        else
            bad "runner sentinel repeated-signal cleanup rc=$rc"
        fi
    else
        bad 'runner signal ownership positive control'
    fi
else
    bad 'runner signal fixture readiness'
fi
if [[ -s "$witness_ready" ]]; then
    set -- $(cat "$witness_ready")
    if [[ "$1" == "$witness" && "$2" == runner-witness ]] && builtin kill -0 "$witness" 2>/dev/null; then
        builtin kill -TERM "$witness"
        wait "$witness" 2>/dev/null || true
    fi
fi
active_witness=
active_witness_ready=
active_signal_ready=

printf 'runner-regressions: passed: %s   failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
