#!/bin/bash
# Sourced by run.sh after it selects a fake-only PATH.

decode_control() {
    local encoded="$1" decoded
    case "$encoded" in
        pt-control:*) decoded=$(printf '%s' "${encoded#pt-control:}" | tr '0123456789abcdef' 'fedcba9876543210') ;;
        *) return 1 ;;
    esac
    printf '%s' "$decoded"
}

controls_invalid_fake() {
    local route="$1" mode="$2" invalid_dir invalid output rc
    invalid_dir="$PT_CONTROL_DIR/invalid-$route-$mode"
    invalid="$invalid_dir/adb"
    output="$PT_CONTROL_DIR/invalid-$route-$mode.output"
    mkdir -p "$invalid_dir"
    if [[ "$mode" == non-executable ]]; then
        cp "$PT_FAKE_ADB_CANONICAL" "$invalid" || return 1
        chmod -x "$invalid"
    fi
    (
        PATH="$PT_CONTROL_DIR/sentinel:$PATH"
        export PATH
        if [[ "$route" == adapter ]]; then
            PT_ADB_BIN="$invalid"
            PT_FAKE_ADB_CANONICAL="$PT_FAKE_ADB_CANONICAL"
            export PT_ADB_BIN PT_FAKE_ADB_CANONICAL
        else
            unset PT_ADB_BIN
            PT_FAKE_ADB_CANONICAL="$invalid"
            export PT_FAKE_ADB_CANONICAL
        fi
        PT_TEST_PREFLIGHT_ONLY=1 "$PT_TEST_BASH" "$LOCAL_DIR/run.sh"
    ) > "$output" 2>&1
    rc=$?
    if [[ "$rc" != 2 ]] \
       || ! grep -q 'fake must be an absolute executable file named adb' "$output" \
       || grep -q '^SUITE ' "$output" \
       || [[ -s "$PT_SENTINEL_LOG" ]]; then
        echo "[FAIL] $route $mode fake did not abort before suites and sentinel" >&2
        cat "$output" >&2
        return 1
    fi
    echo "[PASS] $route $mode fake aborted with status 2 before suites and sentinel"
}

controls_run() {
    local seed encoded decoded expected count route mode
    printf -v seed '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
    printf '%s\n' "$seed" > "$FAKE_ADB_STATE/control-seed"

    "$PT_CONTROL_DIR/sentinel/adb" __pt_detector "$seed" || return 1
    expected=$'PT_SENTINEL\t__pt_detector\t'"$seed"
    if ! grep -Fxq "$expected" "$PT_SENTINEL_LOG"; then
        echo '[FAIL] sentinel detector positive control did not record' >&2
        return 1
    fi
    echo '[PASS] sentinel explicit call recorded the seeded marker'
    : > "$PT_SENTINEL_LOG"

    encoded=$(adb __pt_control) || {
        echo '[FAIL] legacy PATH route did not answer the control verb' >&2
        return 1
    }
    decoded=$(decode_control "$encoded") || {
        echo '[FAIL] legacy PATH route returned an invalid control response' >&2
        return 1
    }
    if [[ "$decoded" != "$seed" ]] || ! grep -Fxq $'adb\t__pt_control' "$FAKE_ADB_STATE/invocations.log"; then
        echo '[FAIL] legacy PATH decoded token or invocation record did not match' >&2
        return 1
    fi
    printf '[PASS] legacy PATH route decoded token %s; invocation adb __pt_control recorded\n' "$decoded"

    PT_TRANSPORT=fake
    PT_ADB_BIN="$PT_FAKE_ADB_CANONICAL"
    export PT_TRANSPORT PT_ADB_BIN
    source "$WT/scripts/lib/transport/adb.sh" || return 1
    encoded=$(adb_t_run __pt_control) || {
        echo '[FAIL] adapter route did not answer through adb_t_run' >&2
        return 1
    }
    decoded=$(decode_control "$encoded") || {
        echo '[FAIL] adapter route returned an invalid control response' >&2
        return 1
    }
    count=$(grep -Fxc $'adb\t__pt_control' "$FAKE_ADB_STATE/invocations.log")
    if [[ "$decoded" != "$seed" || "$count" != 2 ]]; then
        echo '[FAIL] adapter decoded token or invocation count did not match' >&2
        return 1
    fi
    printf '[PASS] adapter route decoded token %s through adb_t_run; canonical invocation count=2\n' "$decoded"

    for route in adapter legacy; do
        for mode in missing non-executable; do
            controls_invalid_fake "$route" "$mode" || return 1
        done
    done
    [[ ! -s "$PT_SENTINEL_LOG" ]] || return 1
}
