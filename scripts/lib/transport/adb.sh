#!/bin/bash
# layer: transport
# requires: transport select
# SU_MODE starts empty; only adb_t_root_probe establishes or clears root.
# Source this module before probing. Sourcing never probes the device.
# The watched stream's one rendering change is plain stderr with a byte count.

[ -n "${PT_TRANSPORT_ADB_SH:-}" ] && return 0
PT_TRANSPORT_ADB_SH=1

# shellcheck source-path=SCRIPTDIR
# shellcheck source=select.sh
source "${BASH_SOURCE[0]%/*}/select.sh"

SU_MODE=""

adb_t_run() {
    transport_init || return 2
    local verb="$1"
    shift
    "$PT_ADB_BIN" "$verb" "$@"
}

adb_t_root_probe() {
    transport_init || return 2
    local result

    result=$("$PT_ADB_BIN" shell "su -c 'whoami'" 2>/dev/null | tr -d '\r\n')
    if [[ "$result" == root ]]; then
        SU_MODE=direct
        return 0
    fi

    result=$("$PT_ADB_BIN" shell "echo 'whoami' | su" 2>/dev/null | tr -d '\r\n')
    if [[ "$result" == root ]]; then
        SU_MODE=piped
        return 0
    fi

    SU_MODE=""
    return 1
}

# Old shell protocols hide remote failure, so the sentinel carries the status.
adb_t_root_exec() {
    transport_init || return 2
    local cmd="$1"
    local raw status

    # A quote would truncate the single-quoted command on the far side.
    if [[ "$cmd" == *"'"* ]]; then
        printf 'adb_t_root_exec: command contains a single quote: %s\n' "$cmd" >&2
        return 125
    fi

    case "${SU_MODE:-}" in
        direct) raw=$("$PT_ADB_BIN" shell "su -c '$cmd' 2>&1; echo __RC__=\$?" 2>/dev/null) ;;
        piped) raw=$("$PT_ADB_BIN" shell "echo '$cmd' | su 2>&1; echo __RC__=\$?" 2>/dev/null) ;;
        *)
            printf 'adb_t_root_exec: root not established (adb_t_root_probe first)\n' >&2
            return 125
            ;;
    esac

    raw=$(printf '%s' "$raw" | tr -d '\r')
    if [[ "$raw" != *__RC__=* ]]; then
        printf 'adb_t_root_exec: device returned no exit status for: %s\n' "$cmd" >&2
        return 125
    fi

    status="${raw##*__RC__=}"
    status="${status%%[!0-9]*}"
    [[ -n "$status" ]] || return 125

    printf '%s' "${raw%__RC__=*}"
    return "$status"
}

# exec-out avoids PTY conversion; suppress dd stderr before su can merge it.
adb_t_root_stream() {
    transport_init || return 2
    local cmd="$1"

    if [[ "$cmd" == *"'"* ]]; then
        printf 'adb_t_root_stream: command contains a single quote: %s\n' "$cmd" >&2
        return 125
    fi

    case "${SU_MODE:-}" in
        direct) "$PT_ADB_BIN" exec-out "su -c '$cmd 2>/dev/null'" ;;
        piped) "$PT_ADB_BIN" exec-out "echo '$cmd 2>/dev/null' | su" ;;
        *)
            printf 'adb_t_root_stream: root not established (adb_t_root_probe first)\n' >&2
            return 125
            ;;
    esac
}

# Direct-child killing alone leaves the stalled transfer's grandchildren alive.
adb_t_kill_tree() {
    transport_init || return 2
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        adb_t_kill_tree "$child"
    done
    kill -9 "$pid" 2>/dev/null || true
}

adb_t_root_stream_watched() {
    transport_init || return 2
    local cmd="$1" out="$2" stall_secs="${3:-30}"

    : > "$out"
    ( adb_t_root_stream "$cmd" > "$out" ) &
    local pid=$! last=0 quiet=0 cur

    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        if [[ -f "$out" ]]; then
            cur=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out" 2>/dev/null || echo 0)
        else
            cur=0
        fi
        if [[ "$cur" -gt "$last" ]]; then
            last=$cur
            quiet=0
        else
            quiet=$((quiet + 2))
            if [[ "$quiet" -ge "$stall_secs" ]]; then
                printf 'Transfer stalled %ss at %s bytes - killing it\n' "$stall_secs" "$cur" >&2
                adb_t_kill_tree "$pid"
                wait "$pid" 2>/dev/null || true
                return 124
            fi
        fi
    done

    wait "$pid" 2>/dev/null || true
    return 0
}

adb_t_remote_size() {
    transport_init || return 2
    local path="$1" out size

    out=$("$PT_ADB_BIN" shell "ls -l $path" 2>&1) || return 1
    out=$(printf '%s' "$out" | tr -d '\r')
    case "$out" in
        *'No such file or directory'*) return 1 ;;
    esac
    size=$(printf '%s\n' "$out" | awk 'NR==1 {print $5}')
    [[ "$size" =~ ^[0-9]+$ ]] || return 2
    printf '%s\n' "$size"
}
