#!/bin/bash
# One active backup per work directory. Never wait or guess whether an owner died.
# A stale lock after SIGKILL requires explicit operator action, never automatic cleanup.
# layer: progress
# requires:

[ -n "${PT_PROGRESS_LOCK_SH:-}" ] && return 0
PT_PROGRESS_LOCK_SH=1

_lock_process_id() {
    local temporary pid=''
    temporary=$(mktemp "$1/.lock-pid.XXXXXXXX") || return 3
    # Do not use command substitution here: its subshell would become the parent.
    if ! /bin/sh -c 'printf "%s\n" "$PPID"' > "$temporary" ||
        ! IFS= read -r pid < "$temporary"; then
        rm -f "$temporary"
        return 3
    fi
    rm -f "$temporary" || return 3
    case "$pid" in
        ''|0|*[!0-9]*|0?*) return 3 ;;
    esac
    printf -v "$2" '%s' "$pid"
}

lock_acquire() {
    [[ $# == 1 && -n "$1" ]] || return 3
    local lock_dir="$1/.projector-status/backup.lock" timestamp current_pid=''
    mkdir -p "$1/.projector-status" || return 3
    if ! mkdir "$lock_dir" 2>/dev/null; then
        printf 'Backup lock is busy: %s\n' "$lock_dir" >&2
        if [[ -f "$lock_dir/owner" ]]; then
            /bin/cat "$lock_dir/owner" >&2
        fi
        return 3
    fi
    if ! _lock_process_id "$1/.projector-status" current_pid; then
        rmdir "$lock_dir"
        return 3
    fi
    if ! timestamp=$(date +%s); then
        rmdir "$lock_dir"
        return 3
    fi
    if ! printf '%s %s\n' "$current_pid" "$timestamp" > "$lock_dir/owner"; then
        rm -f "$lock_dir/owner"
        rmdir "$lock_dir"
        return 3
    fi
    return 0
}

lock_release() {
    [[ $# == 1 && -n "$1" ]] || return 3
    local lock_dir="$1/.projector-status/backup.lock" owner_pid='' timestamp='' extra='' current_pid=''
    if [[ ! -f "$lock_dir/owner" ]] ||
        ! IFS=' ' read -r owner_pid timestamp extra < "$lock_dir/owner"; then
        printf 'Cannot release backup lock without an owner: %s\n' "$lock_dir" >&2
        return 3
    fi
    _lock_process_id "$1/.projector-status" current_pid || return 3
    if [[ "$owner_pid" != "$current_pid" || -z "$timestamp" || -n "$extra" ]]; then
        printf 'Cannot release another owner\047s backup lock: %s\n' "$lock_dir" >&2
        return 3
    fi
    rm -f "$lock_dir/owner" || return 3
    rmdir "$lock_dir" || return 3
    return 0
}
