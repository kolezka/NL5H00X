#!/bin/bash
set -uo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERVISOR=${PT_SUPERVISOR_UNDER_TEST:-"$LOCAL_DIR/supervise.py"}
PYTHON=${PT_TEST_PYTHON:-/usr/bin/python3}

if [[ "${1:-}" == --fixture ]]; then
    mode="$2"
    evidence="$3"
    token="$4"
    on_int() { printf 'INT %s\n' "$token" >> "$evidence/signals"; }
    on_term() { printf 'TERM %s\n' "$token" >> "$evidence/signals"; }
    trap on_int INT
    trap on_term TERM
    if [[ "$mode" == status ]]; then
        exit 7
    fi
    "$BASH" -c 'trap "" INT TERM; while :; do sleep 1; done' &
    descendant=$!
    printf '%s %s %s\n' "$$" "$descendant" "$token" > "$evidence/ready"
    case "$mode" in
        leader-zero) sleep 0.2; exit 0 ;;
        leader-nine) sleep 0.2; exit 9 ;;
    esac
    while :; do sleep 1; done
fi

control=$(mktemp -d "${TMPDIR:-/tmp}/pt-supervisor.XXXXXX") || exit 2
PASS=0
FAIL=0
witness_pid=
witness_ready=
active_supervisor=
active_state=

ok() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

wait_for_file() {
    local path="$1" attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
        [[ -s "$path" ]] && return 0
        sleep 0.05
    done
    return 1
}

state_leader() {
    awk -F'[ =]' '/^spawn supervisor=/ { for (i = 1; i <= NF; i++) if ($i == "leader") { print $(i + 1); exit } }' "$1"
}

start_witness() {
    local evidence="$1" token="$2"
    witness_ready="$evidence/witness-ready"
    "$BASH" -c 'printf "%s %s\n" "$$" "$1" > "$2"; sleep 30' _ "$token" "$witness_ready" &
    witness_pid=$!
    wait_for_file "$witness_ready" || return 1
    set -- $(cat "$witness_ready")
    [[ "$1" == "$witness_pid" && "$2" == "$token" ]] || return 1
    builtin kill -0 "$witness_pid" 2>/dev/null
}

stop_witness() {
    local recorded_pid recorded_token
    [[ -n "$witness_pid" && -s "$witness_ready" ]] || return 0
    set -- $(cat "$witness_ready")
    recorded_pid="$1"
    recorded_token="$2"
    if [[ "$recorded_pid" == "$witness_pid" && -n "$recorded_token" ]] && builtin kill -0 "$witness_pid" 2>/dev/null; then
        builtin kill -TERM "$witness_pid"
        wait "$witness_pid" 2>/dev/null || true
    fi
    witness_pid=
    witness_ready=
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "$active_supervisor" && -s "$active_state" ]] \
       && grep -q "^spawn supervisor=$active_supervisor " "$active_state" \
       && builtin kill -0 "$active_supervisor" 2>/dev/null; then
        builtin kill -TERM "$active_supervisor"
        wait "$active_supervisor" 2>/dev/null || true
    fi
    stop_witness
    if [[ "$status" != 0 || "$FAIL" != 0 || "${PT_KEEP_TEST_EVIDENCE:-0}" == 1 ]]; then
        printf '[KEEP] supervisor evidence: %s\n' "$control"
    else
        rm -rf "$control"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -f "$SUPERVISOR" ]]; then
    bad "bounded Python supervisor exists at $SUPERVISOR"
    printf 'supervisor: passed: %s   failed: %s\n' "$PASS" "$FAIL"
    exit 1
fi

run_status_control() {
    local evidence="$control/status" rc
    mkdir -p "$evidence"
    "$PYTHON" "$SUPERVISOR" --timeout 5 --grace 0.2 --state "$evidence/state" -- \
        "$BASH" "$0" --fixture status "$evidence" status-token > "$evidence/output" 2>&1
    rc=$?
    if [[ "$rc" == 7 ]] && grep -q '^exit status=7$' "$evidence/state"; then
        ok 'supervisor preserves child exit status 7'
    else
        bad "supervisor status control returned $rc"
    fi
}

run_signal_control() {
    local signal="$1" expected="$2" name="$3"
    local evidence="$control/$name" token="$name-token" supervisor_pid fixture_pid descendant_pid ready_token leader_pid
    local fixture_pgid descendant_pgid rc
    mkdir -p "$evidence"
    : > "$evidence/signals"
    start_witness "$evidence" "$token-witness" || { bad "$name witness positive control"; return; }
    "$PYTHON" "$SUPERVISOR" --timeout 20 --grace 0.2 --state "$evidence/state" -- \
        "$BASH" "$0" --fixture signal "$evidence" "$token" > "$evidence/output" 2>&1 &
    supervisor_pid=$!
    active_supervisor=$supervisor_pid
    active_state="$evidence/state"
    if ! wait_for_file "$evidence/ready" || ! wait_for_file "$evidence/state"; then
        bad "$name fixture readiness"
        return
    fi
    set -- $(cat "$evidence/ready")
    fixture_pid="$1"
    descendant_pid="$2"
    ready_token="$3"
    fixture_pgid=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
    descendant_pgid=$(ps -o pgid= -p "$descendant_pid" | tr -d ' ')
    leader_pid=$(state_leader "$evidence/state")
    if [[ "$ready_token" != "$token" ]] \
       || ! grep -q "^spawn supervisor=$supervisor_pid leader=$leader_pid pgid=$leader_pid$" "$evidence/state" \
       || [[ -z "$leader_pid" || "$fixture_pgid" != "$leader_pid" || "$descendant_pgid" != "$leader_pid" ]] \
       || ! builtin kill -0 "$supervisor_pid" 2>/dev/null \
       || ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       || ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       || ! builtin kill -0 "$witness_pid" 2>/dev/null; then
        bad "$name ownership positive control"
        return
    fi
    builtin kill -"$signal" "$supervisor_pid"
    sleep 0.05
    if grep -q "^signal received=$signal$" "$evidence/state" && builtin kill -0 "$supervisor_pid" 2>/dev/null; then
        builtin kill -"$signal" "$supervisor_pid"
    else
        bad "$name repeated signal was not exercised during cleanup"
    fi
    wait "$supervisor_pid" 2>/dev/null
    rc=$?
    active_supervisor=
    active_state=
    if [[ "$rc" == "$expected" ]] \
       && grep -q "^$signal $token$" "$evidence/signals" \
       && ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       && ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       && builtin kill -0 "$witness_pid" 2>/dev/null; then
        ok "$name forwards $signal, preserves $expected, and reaps its group"
    else
        bad "$name cleanup rc=$rc fixture=$fixture_pid descendant=$descendant_pid"
    fi
    stop_witness
}

run_timeout_control() {
    local evidence="$control/timeout" token=timeout-token supervisor_pid fixture_pid descendant_pid ready_token leader_pid rc
    local fixture_pgid descendant_pgid
    mkdir -p "$evidence"
    : > "$evidence/signals"
    start_witness "$evidence" "$token-witness" || { bad 'timeout witness positive control'; return; }
    "$PYTHON" "$SUPERVISOR" --timeout 1 --grace 0.2 --state "$evidence/state" -- \
        "$BASH" "$0" --fixture hung "$evidence" "$token" > "$evidence/output" 2>&1 &
    supervisor_pid=$!
    active_supervisor=$supervisor_pid
    active_state="$evidence/state"
    if ! wait_for_file "$evidence/ready" || ! wait_for_file "$evidence/state"; then
        bad 'timeout fixture readiness'
        return
    fi
    set -- $(cat "$evidence/ready")
    fixture_pid="$1"
    descendant_pid="$2"
    ready_token="$3"
    fixture_pgid=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
    descendant_pgid=$(ps -o pgid= -p "$descendant_pid" | tr -d ' ')
    leader_pid=$(state_leader "$evidence/state")
    if [[ "$ready_token" != "$token" ]] \
       || ! grep -q "^spawn supervisor=$supervisor_pid leader=$leader_pid pgid=$leader_pid$" "$evidence/state" \
       || [[ -z "$leader_pid" || "$fixture_pgid" != "$leader_pid" || "$descendant_pgid" != "$leader_pid" ]] \
       || ! builtin kill -0 "$supervisor_pid" 2>/dev/null \
       || ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       || ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       || ! builtin kill -0 "$witness_pid" 2>/dev/null; then
        bad 'timeout ownership positive control'
        return
    fi
    wait "$supervisor_pid" 2>/dev/null
    rc=$?
    active_supervisor=
    active_state=
    if [[ "$rc" == 124 ]] \
       && grep -q '^timeout expired=1' "$evidence/state" \
       && ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       && ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       && builtin kill -0 "$witness_pid" 2>/dev/null; then
        ok 'timeout returns 124 and reaps TERM-resistant descendants only'
    else
        bad "timeout cleanup rc=$rc fixture=$fixture_pid descendant=$descendant_pid"
    fi
    stop_witness
}

run_leader_exit_control() {
    local mode="$1" expected="$2" evidence token
    local supervisor_pid fixture_pid descendant_pid ready_token leader_pid fixture_pgid descendant_pgid rc
    evidence="$control/$mode"
    token="$mode-token"
    mkdir -p "$evidence"
    : > "$evidence/signals"
    start_witness "$evidence" "$token-witness" || { bad "$mode witness positive control"; return; }
    "$PYTHON" "$SUPERVISOR" --timeout 5 --grace 0.2 --state "$evidence/state" -- \
        "$BASH" "$0" --fixture "$mode" "$evidence" "$token" > "$evidence/output" 2>&1 &
    supervisor_pid=$!
    active_supervisor=$supervisor_pid
    active_state="$evidence/state"
    if ! wait_for_file "$evidence/ready" || ! wait_for_file "$evidence/state"; then
        bad "$mode fixture readiness"
        return
    fi
    set -- $(cat "$evidence/ready")
    fixture_pid="$1"
    descendant_pid="$2"
    ready_token="$3"
    leader_pid=$(state_leader "$evidence/state")
    fixture_pgid=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
    descendant_pgid=$(ps -o pgid= -p "$descendant_pid" | tr -d ' ')
    if [[ "$ready_token" != "$token" || -z "$leader_pid" \
       || "$fixture_pgid" != "$leader_pid" || "$descendant_pgid" != "$leader_pid" ]] \
       || ! builtin kill -0 "$supervisor_pid" 2>/dev/null \
       || ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       || ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       || ! builtin kill -0 "$witness_pid" 2>/dev/null; then
        bad "$mode ownership positive control"
        return
    fi
    wait "$supervisor_pid" 2>/dev/null
    rc=$?
    active_supervisor=
    active_state=
    if [[ "$rc" == "$expected" ]] \
       && grep -q "^exit status=$expected$" "$evidence/state" \
       && ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       && ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       && builtin kill -0 "$witness_pid" 2>/dev/null; then
        ok "$mode keeps child status $expected and reaps its lingering descendant"
    else
        bad "$mode cleanup rc=$rc descendant=$descendant_pid"
    fi
    stop_witness
}

run_timeout_signal_control() {
    local evidence="$control/timeout-signal" token=timeout-signal-token
    local supervisor_pid fixture_pid descendant_pid ready_token leader_pid fixture_pgid descendant_pgid rc marker
    mkdir -p "$evidence"
    : > "$evidence/signals"
    start_witness "$evidence" "$token-witness" || { bad 'timeout-signal witness positive control'; return; }
    "$PYTHON" "$SUPERVISOR" --timeout 1 --grace 0.5 --state "$evidence/state" -- \
        "$BASH" "$0" --fixture hung "$evidence" "$token" > "$evidence/output" 2>&1 &
    supervisor_pid=$!
    active_supervisor=$supervisor_pid
    active_state="$evidence/state"
    if ! wait_for_file "$evidence/ready" || ! wait_for_file "$evidence/state"; then
        bad 'timeout-signal fixture readiness'
        return
    fi
    set -- $(cat "$evidence/ready")
    fixture_pid="$1"
    descendant_pid="$2"
    ready_token="$3"
    leader_pid=$(state_leader "$evidence/state")
    fixture_pgid=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
    descendant_pgid=$(ps -o pgid= -p "$descendant_pid" | tr -d ' ')
    marker=
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
        if grep -q '^grace started signal=TERM$' "$evidence/state" 2>/dev/null; then marker=1; break; fi
        sleep 0.05
    done
    if [[ "$ready_token" != "$token" || -z "$marker" || -z "$leader_pid" \
       || "$fixture_pgid" != "$leader_pid" || "$descendant_pgid" != "$leader_pid" ]] \
       || ! grep -q "^spawn supervisor=$supervisor_pid leader=$leader_pid pgid=$leader_pid$" "$evidence/state" \
       || ! builtin kill -0 "$supervisor_pid" 2>/dev/null \
       || ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       || ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       || ! builtin kill -0 "$witness_pid" 2>/dev/null; then
        bad 'timeout-signal ownership and grace positive control'
        return
    fi
    builtin kill -INT "$supervisor_pid"
    wait "$supervisor_pid" 2>/dev/null
    rc=$?
    active_supervisor=
    active_state=
    if [[ "$rc" == 130 ]] \
       && grep -q '^timeout expired=1$' "$evidence/state" \
       && grep -q '^signal received=INT$' "$evidence/state" \
       && ! builtin kill -0 "$fixture_pid" 2>/dev/null \
       && ! builtin kill -0 "$descendant_pid" 2>/dev/null \
       && builtin kill -0 "$witness_pid" 2>/dev/null; then
        ok 'INT observed during timeout grace overrides timeout status with 130'
    else
        bad "timeout-signal cleanup rc=$rc"
    fi
    stop_witness
}

run_invalid_numeric_controls() {
    local value option evidence rc
    for option in timeout grace; do
        for value in nan inf -inf; do
            evidence="$control/invalid-$option-${value#-}"
            mkdir -p "$evidence"
            if [[ "$option" == timeout ]]; then
                "$PYTHON" "$SUPERVISOR" "--timeout=$value" --grace 0.2 --state "$evidence/state" -- "$BASH" -c 'exit 0' > "$evidence/output" 2>&1
            else
                "$PYTHON" "$SUPERVISOR" --timeout 1 "--grace=$value" --state "$evidence/state" -- "$BASH" -c 'exit 0' > "$evidence/output" 2>&1
            fi
            rc=$?
            if [[ "$rc" == 2 ]] && grep -q 'finite positive' "$evidence/output"; then
                ok "$option rejects $value before spawning"
            else
                bad "$option accepted $value with rc=$rc"
            fi
        done
    done
}

run_status_control
run_leader_exit_control leader-zero 0
run_leader_exit_control leader-nine 9
run_signal_control TERM 143 double-term
run_signal_control INT 130 interrupt
run_timeout_control
run_timeout_signal_control
run_invalid_numeric_controls
printf 'supervisor: passed: %s   failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
