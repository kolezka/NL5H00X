#!/bin/bash
# Source in the shell that launches children, never through $(child_spawn ...).
CHILD_PIDS=
CHILD_PID=
CHILD_RELEASING=0

child_spawn() {
    local label="$1"
    shift
    [[ "$#" -gt 0 && -n "$label" ]] || return 2
    "$@" &
    CHILD_PID=$!
    CHILD_PIDS="$CHILD_PIDS $CHILD_PID"
}

child_registered() {
    case " $CHILD_PIDS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

child_active() {
    local active
    # A registry entry alone cannot prove a PID still belongs to this shell.
    for active in $(jobs -pr; jobs -ps); do
        [[ "$active" == "$1" ]] && return 0
    done
    return 1
}

child_forget() {
    local pid kept=
    for pid in $CHILD_PIDS; do
        [[ "$pid" == "$1" ]] || kept="$kept $pid"
    done
    CHILD_PIDS=$kept
    [[ "$CHILD_PID" == "$1" ]] && CHILD_PID=
}

child_wait_reap() {
    local pid="$1" status=0
    child_registered "$pid" || return 127
    wait "$pid" || status=$?
    child_forget "$pid"
    return "$status"
}

child_release_all() {
    local pid attempt active pending
    [[ "$CHILD_RELEASING" == 0 ]] || return 0
    CHILD_RELEASING=1
    pending=$CHILD_PIDS
    for pid in $pending; do
        if child_active "$pid"; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    # Give cooperative children one second to run their own cancellation traps.
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        active=0
        for pid in $pending; do
            child_active "$pid" && active=1
        done
        [[ "$active" == 1 ]] || break
        sleep 0.05
    done
    for pid in $pending; do
        if child_active "$pid"; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
        child_registered "$pid" && child_wait_reap "$pid" >/dev/null 2>&1 || true
    done
    CHILD_PIDS=
    CHILD_PID=
    CHILD_RELEASING=0
}
