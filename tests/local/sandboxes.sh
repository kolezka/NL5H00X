#!/bin/bash
# Suites register in their own shell before populating each sandbox.
SANDBOX_PATHS=()
SANDBOX_FAILED=()
SANDBOX_COUNT=0
SANDBOX_ACTIVE=-1
SANDBOX_CLEANING=0
SANDBOX_SIGNAL_STATUS=

sandbox_register() {
    SANDBOX_PATHS[$SANDBOX_COUNT]="$1"
    SANDBOX_FAILED[$SANDBOX_COUNT]=0
    SANDBOX_ACTIVE=$SANDBOX_COUNT
    SANDBOX_COUNT=$((SANDBOX_COUNT + 1))
}

sandbox_fail() {
    if [[ "$SANDBOX_ACTIVE" -ge 0 ]]; then
        SANDBOX_FAILED[$SANDBOX_ACTIVE]=1
    fi
}

sandbox_dispose() {
    local index="$1" path="${SANDBOX_PATHS[$1]:-}" failed="${SANDBOX_FAILED[$1]:-0}"
    [[ -n "$path" ]] || return 0
    if [[ "${PT_KEEP_SANDBOX:-0}" == 1 || "$failed" == 1 ]]; then
        printf '  [KEEP] sandbox: %s\n' "$path"
    else
        rm -rf "$path"
    fi
    SANDBOX_PATHS[$index]=
}

sandbox_finish() {
    if [[ -n "${PT_TEST_FAIL_SCENARIO:-}" && "${SCENARIO:-}" == "$PT_TEST_FAIL_SCENARIO" ]]; then
        bad "injected assertion failure for retention control: $SCENARIO"
    fi
    if [[ "$SANDBOX_ACTIVE" -lt 0 || "${SANDBOX_PATHS[$SANDBOX_ACTIVE]:-}" != "$1" ]]; then
        echo 'sandbox_finish: sandbox is not registered' >&2
        return 1
    fi
    sandbox_dispose "$SANDBOX_ACTIVE"
    SANDBOX_ACTIVE=-1
}

sandbox_cleanup_all() {
    local index=0
    while [[ "$index" -lt "$SANDBOX_COUNT" ]]; do
        sandbox_dispose "$index"
        index=$((index + 1))
    done
    SANDBOX_ACTIVE=-1
}

suite_cleanup() {
    local status="${1:-0}"
    [[ "$SANDBOX_CLEANING" == 0 ]] || return "$status"
    SANDBOX_CLEANING=1
    [[ "$status" == 0 ]] || sandbox_fail
    child_release_all
    sandbox_cleanup_all
    SANDBOX_CLEANING=0
    return "$status"
}

suite_exit_cleanup() {
    local status=$?
    trap - EXIT
    trap '' INT TERM
    [[ -z "$SANDBOX_SIGNAL_STATUS" ]] || status=$SANDBOX_SIGNAL_STATUS
    suite_cleanup "$status"
    exit "$status"
}

suite_cancel() {
    local status="$1"
    if [[ -z "$SANDBOX_SIGNAL_STATUS" ]]; then
        SANDBOX_SIGNAL_STATUS=$status
        sandbox_fail
        trap '' INT TERM
    fi
    exit "$SANDBOX_SIGNAL_STATUS"
}

trap suite_exit_cleanup EXIT
trap 'suite_cancel 130' INT
trap 'suite_cancel 143' TERM
