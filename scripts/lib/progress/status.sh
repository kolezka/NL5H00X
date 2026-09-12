#!/bin/bash
# Atomic per-run status snapshots, with one writer per run directory.
# Stale writer claims require operator recovery and are never removed here.
# layer: progress
# requires:

[ -n "${PT_PROGRESS_STATUS_SH:-}" ] && return 0
PT_PROGRESS_STATUS_SH=1

status_run_dir_alloc() {
    [[ $# == 1 && -n "$1" ]] || return 2
    local workdir=$1
    case "$workdir" in
        /*) ;;
        *) workdir="$PWD/$workdir" ;;
    esac
    mkdir -p "$workdir/.projector-status" || return 2
    mktemp -d "$workdir/.projector-status/run.XXXXXXXX" || return 2
}

_status_decimal() {
    local value=$1
    case "$value" in
        ''|*[!0-9]*|0?*) return 2 ;;
    esac
    [[ ${#value} -le 16 ]] || return 2
    return 0
}

# A subshell restores the caller's globbing option on every return path.
status_validate() (
    set -f
    [[ $# == 2 ]] || return 2
    local record=$1 expected_run=$2 i value state phase rc artifact backup_dir
    local LC_ALL=C
    local -a fields keys
    fields=()
    keys=(v run state phase rc artifact backup_dir bytes total blocks_done blocks_total stalls)
    case "$record" in
        ''|*$'\n'*|*$'\r'*|*$'\t'*|*'*'*|*'?'*|*'['*) return 2 ;;
    esac
    case "$expected_run" in
        ''|*/*) return 2 ;;
    esac
    IFS=' ' read -r -a fields <<< "$record" || return 2
    [[ ${#fields[@]} -eq ${#keys[@]} ]] || return 2
    for ((i=0; i<${#keys[@]}; i++)); do
        [[ "${fields[$i]}" == "${keys[$i]}="* ]] || return 2
    done
    [[ "${fields[0]}" == v=1 && "${fields[1]}" == "run=$expected_run" ]] || return 2
    state=${fields[2]#*=}
    phase=${fields[3]#*=}
    rc=${fields[4]#*=}
    artifact=${fields[5]#*=}
    backup_dir=${fields[6]#*=}
    case "$state" in
        running|complete|failed|cancelled) ;;
        *) return 2 ;;
    esac
    case "$phase" in
        init|sysinfo|appdata|partitions|image|packaging|verify) ;;
        *) return 2 ;;
    esac
    case "$artifact" in
        none|unverified|verified|truncated|missing) ;;
        *) return 2 ;;
    esac
    if [[ "$rc" != none ]]; then
        _status_decimal "$rc" || return 2
        [[ ${#rc} -le 3 && "$rc" -le 255 ]] || return 2
    fi
    if [[ "$backup_dir" != none ]]; then
        case "$backup_dir" in
            projector-backup-?*) ;;
            *) return 2 ;;
        esac
        case "${backup_dir#projector-backup-}" in
            *[!A-Za-z0-9_.-]*) return 2 ;;
        esac
    fi
    for ((i=7; i<12; i++)); do
        value=${fields[$i]#*=}
        _status_decimal "$value" || return 2
    done
    case "$state" in
        complete)
            [[ "$rc" == 0 && "$artifact" == verified && "$phase" == verify && "$backup_dir" != none ]] || return 2
            ;;
        running) [[ "$rc" == none ]] || return 2 ;;
        failed) [[ "$rc" != none && "$rc" != 0 ]] || return 2 ;;
        cancelled)
            case "$rc" in
                129|130|143) ;;
                *) return 2 ;;
            esac
            ;;
    esac
    return 0
)

status_field() (
    set -f
    [[ $# == 2 && -n "$1" && -n "$2" ]] || return 1
    local record=$1 key=$2 field
    local -a fields
    fields=()
    IFS=' ' read -r -a fields <<< "$record" || return 1
    for field in "${fields[@]}"; do
        if [[ "$field" == "$key="* ]]; then
            printf '%s\n' "${field#*=}"
            return 0
        fi
    done
    return 1
)

_status_claim_writer() {
    local run_dir=$1 writer_pid=$2 writer_key=$3 owner_pid=''
    if mkdir "$run_dir/writer" 2>/dev/null; then
        if [[ -e "$run_dir/status" || -L "$run_dir/status" ]]; then
            printf 'Refusing prior status snapshot: %s\n' "$run_dir" >&2
            return 2
        fi
        printf '%s\n' "$writer_pid" > "$run_dir/writer/pid" || return 2
    else
        case "${_status_written_runs:-}" in
            *":$writer_pid:$writer_key:"*) ;;
            *)
                printf 'Refusing existing writer claim: %s\n' "$run_dir" >&2
                return 2
                ;;
        esac
    fi
    if ! IFS= read -r owner_pid < "$run_dir/writer/pid" || [[ "$owner_pid" != "$writer_pid" ]]; then
        printf 'Refusing another process\047s writer claim: %s\n' "$run_dir" >&2
        return 2
    fi
    return 0
}

status_write() {
    [[ $# -ge 1 && -n "$1" ]] || return 2
    local run_dir=${1%/} run argument key value i found record='' temporary writer_key writer_pid=''
    local -a keys values seen
    shift
    [[ -d "$run_dir" ]] || return 2
    case "$run_dir" in
        /*) ;;
        *) run_dir="$PWD/$run_dir" ;;
    esac
    run=${run_dir##*/}
    keys=(v run state phase rc artifact backup_dir bytes total blocks_done blocks_total stalls)
    values=(1 "$run" '' '' '' '' '' '' '' '' '' '')
    seen=(0 0 0 0 0 0 0 0 0 0 0 0)
    for argument in "$@"; do
        [[ "$argument" == *=* ]] || return 2
        key=${argument%%=*}
        value=${argument#*=}
        found=0
        for ((i=0; i<12; i++)); do
            if [[ "$key" == "${keys[$i]}" ]]; then
                [[ "${seen[$i]}" == 0 ]] || return 2
                seen[i]=1
                values[i]=$value
                found=1
                break
            fi
        done
        [[ "$found" == 1 ]] || return 2
    done
    for ((i=0; i<12; i++)); do
        record="${record}${record:+ }${keys[$i]}=${values[$i]}"
    done
    status_validate "$record" "$run" || return 2

    # Encode separators so full paths with spaces cannot alias list entries.
    writer_key=${run_dir//%/%25}
    writer_key=${writer_key//:/%3A}
    writer_key=${writer_key// /%20}
    writer_key=${writer_key//$'\t'/%09}
    writer_key=${writer_key//$'\n'/%0A}
    writer_key=${writer_key//$'\r'/%0D}
    temporary=$(mktemp "$run_dir/.status.XXXXXXXX") || return 2
    # $$ survives a fork; a direct child's PPID identifies this writer process.
    if ! /bin/sh -c 'printf "%s\n" "$PPID"' > "$temporary" ||
        ! IFS= read -r writer_pid < "$temporary"; then
        rm -f "$temporary"
        return 2
    fi
    case "$writer_pid" in
        ''|0|*[!0-9]*|0?*) rm -f "$temporary"; return 2 ;;
    esac
    if ! _status_claim_writer "$run_dir" "$writer_pid" "$writer_key"; then
        rm -f "$temporary"
        return 2
    fi
    if ! printf '%s\n' "$record" > "$temporary"; then
        rm -f "$temporary"
        return 2
    fi
    if ! mv -f "$temporary" "$run_dir/status"; then
        rm -f "$temporary"
        return 2
    fi
    case "${_status_written_runs:-}" in
        *":$writer_pid:$writer_key:"*) ;;
        *) _status_written_runs="${_status_written_runs:-}:$writer_pid:$writer_key:" ;;
    esac
    return 0
}

status_read() {
    [[ $# == 1 && -n "$1" ]] || return 2
    local run_dir=${1%/} record='' extra=''
    [[ -e "$run_dir/status" || -L "$run_dir/status" ]] || return 1
    [[ -f "$run_dir/status" ]] || return 2
    # Open once so a rename cannot splice lines from different snapshots.
    {
        IFS= read -r record || return 2
        if IFS= read -r extra || [[ -n "$extra" ]]; then
            return 2
        fi
    } < "$run_dir/status" || return 2
    status_validate "$record" "${run_dir##*/}" || return 2
    printf '%s\n' "$record"
}

# The caller must still verify the selected artifact before reporting success.
status_classify() {
    [[ $# == 2 ]] || return 2
    local record=$1 child_rc=$2 run state
    run=$(status_field "$record" run) || run=''
    if ! status_validate "$record" "$run"; then
        printf 'indeterminate\n'
        return 0
    fi
    state=$(status_field "$record" state) || return 2
    case "$state" in
        complete)
            if [[ "$child_rc" == 0 ]]; then
                printf 'complete\n'
            else
                printf 'failed\n'
            fi
            ;;
        failed) printf 'failed\n' ;;
        cancelled) printf 'cancelled\n' ;;
        running) printf 'aborted\n' ;;
    esac
    return 0
}
