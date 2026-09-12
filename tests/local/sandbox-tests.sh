#!/bin/bash
set -uo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJECT_DIR=${PT_SANDBOX_SUBJECT_DIR:-$LOCAL_DIR}
TEST_BASH=${PT_TEST_BASH:-$BASH}

if [[ "${1:-}" == --fixture ]]; then
    mode="$2"
    evidence="$3"
    token="$4"
    source "$SUBJECT_DIR/lifecycle.sh"
    source "$SUBJECT_DIR/sandboxes.sh"
    SCENARIO="$mode"
    PASS=0
    FAIL=0
    bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); sandbox_fail; }
    mkdir -p "$evidence/sandbox"
    printf 'evidence %s\n' "$token" > "$evidence/sandbox/evidence.txt"
    sandbox_register "$evidence/sandbox"
    case "$mode" in
        success)
            sandbox_finish "$evidence/sandbox"
            exit 0
            ;;
        assertion)
            PT_TEST_FAIL_SCENARIO=assertion
            export PT_TEST_FAIL_SCENARIO
            sandbox_finish "$evidence/sandbox"
            exit 1
            ;;
        unexpected)
            exit 7
            ;;
        unbound)
            printf '%s\n' "$PT_INTENTIONALLY_UNBOUND"
            ;;
        signal)
            child_spawn stubborn "$BASH" -c 'trap "" INT TERM; while :; do sleep 1; done'
            printf '%s %s %s\n' "$$" "$CHILD_PID" "$token" > "$evidence/ready"
            while :; do sleep 1; done
            ;;
        *)
            exit 2
            ;;
    esac
fi

control=$(mktemp -d "${TMPDIR:-/tmp}/pt-sandboxes.XXXXXX") || exit 2
PASS=0
FAIL=0
active_fixture=
active_ready=

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

cleanup_active_fixture() {
    local fixture_pid child_pid token child_parent
    [[ -n "$active_fixture" && -s "$active_ready" ]] || return 0
    set -- $(cat "$active_ready")
    fixture_pid="$1"
    child_pid="$2"
    token="$3"
    child_parent=$(ps -o ppid= -p "$child_pid" 2>/dev/null | tr -d ' ')
    if [[ "$fixture_pid" == "$active_fixture" && -n "$token" && "$child_parent" == "$fixture_pid" ]] \
       && builtin kill -0 "$active_fixture" 2>/dev/null; then
        builtin kill -TERM "$active_fixture"
        wait "$active_fixture" 2>/dev/null || true
    fi
    active_fixture=
    active_ready=
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    cleanup_active_fixture
    if [[ "$status" != 0 || "$FAIL" != 0 || "${PT_KEEP_TEST_EVIDENCE:-0}" == 1 ]]; then
        printf '[KEEP] sandbox-test evidence: %s\n' "$control"
    else
        rm -rf "$control"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_fixture() {
    local mode="$1" expected="$2" evidence rc
    evidence="$control/$mode"
    mkdir -p "$evidence"
    PT_SANDBOX_SUBJECT_DIR="$SUBJECT_DIR" PT_TEST_BASH="$TEST_BASH" \
        "$TEST_BASH" "$0" --fixture "$mode" "$evidence" "$mode-token" > "$evidence/output" 2>&1
    rc=$?
    printf '%s\n' "$rc" > "$evidence/rc"
    if [[ "$rc" != "$expected" ]]; then
        bad "$mode fixture returned $rc instead of $expected"
        return 1
    fi
    return 0
}

if run_fixture success 0 && [[ ! -d "$control/success/sandbox" ]]; then
    ok 'successful scenario removes its sandbox'
else
    bad 'successful scenario retained its sandbox'
fi

if run_fixture assertion 1 \
   && [[ -f "$control/assertion/sandbox/evidence.txt" ]] \
   && grep -Fq "[KEEP] sandbox: $control/assertion/sandbox" "$control/assertion/output"; then
    ok 'expected assertion failure keeps its sandbox and prints the path'
else
    bad 'expected assertion failure lost its evidence'
fi

if run_fixture unexpected 7 \
   && [[ -f "$control/unexpected/sandbox/evidence.txt" ]] \
   && grep -Fq "[KEEP] sandbox: $control/unexpected/sandbox" "$control/unexpected/output"; then
    ok 'unexpected exit 7 keeps evidence and preserves exit 7'
else
    bad 'unexpected nonzero exit lost evidence or status'
fi

PT_SANDBOX_SUBJECT_DIR="$SUBJECT_DIR" PT_TEST_BASH="$TEST_BASH" \
    "$TEST_BASH" "$0" --fixture unbound "$control/unbound" unbound-token > "$control/unbound-output" 2>&1
rc=$?
if [[ "$rc" != 0 ]] \
   && [[ -f "$control/unbound/sandbox/evidence.txt" ]] \
   && grep -Fq "[KEEP] sandbox: $control/unbound/sandbox" "$control/unbound-output"; then
    ok "unbound-variable exit $rc keeps unfinished evidence"
else
    bad "unbound-variable cleanup rc=$rc"
fi

signal_evidence="$control/signal"
mkdir -p "$signal_evidence"
PT_SANDBOX_SUBJECT_DIR="$SUBJECT_DIR" PT_TEST_BASH="$TEST_BASH" \
    "$TEST_BASH" "$0" --fixture signal "$signal_evidence" signal-token > "$signal_evidence/output" 2>&1 &
active_fixture=$!
active_ready="$signal_evidence/ready"
if wait_for_file "$active_ready"; then
    set -- $(cat "$active_ready")
    fixture_pid="$1"
    child_pid="$2"
    ready_token="$3"
    child_parent=$(ps -o ppid= -p "$child_pid" | tr -d ' ')
    if [[ "$fixture_pid" == "$active_fixture" && "$ready_token" == signal-token && "$child_parent" == "$fixture_pid" ]] \
       && builtin kill -0 "$active_fixture" 2>/dev/null \
       && builtin kill -0 "$child_pid" 2>/dev/null; then
        builtin kill -TERM "$active_fixture"
        sleep 0.05
        child_parent=$(ps -o ppid= -p "$child_pid" 2>/dev/null | tr -d ' ')
        if [[ "$child_parent" == "$fixture_pid" ]] && builtin kill -0 "$active_fixture" 2>/dev/null; then
            builtin kill -TERM "$active_fixture"
        else
            bad 'signal fixture did not remain owned during cleanup'
        fi
        wait "$active_fixture" 2>/dev/null
        rc=$?
        active_fixture=
        active_ready=
        if [[ "$rc" == 143 ]] \
           && ! builtin kill -0 "$child_pid" 2>/dev/null \
           && [[ -f "$signal_evidence/sandbox/evidence.txt" ]] \
           && grep -Fq "[KEEP] sandbox: $signal_evidence/sandbox" "$signal_evidence/output"; then
            ok 'repeated TERM preserves 143, reaps owned child, and keeps evidence'
        else
            bad "signal cleanup rc=$rc child=$child_pid"
        fi
    else
        bad 'signal fixture ownership positive control'
    fi
else
    bad 'signal fixture readiness'
fi

printf 'sandboxes: passed: %s   failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
