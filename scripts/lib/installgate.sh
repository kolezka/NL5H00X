#!/bin/bash
# The install policy is separate from unlocking the launcher.
[[ -n "${_INSTALLGATE_SH_LOADED:-}" ]] && return 0
_INSTALLGATE_SH_LOADED=1

INSTALL_GATE_PROP="/system/build.prop"
INSTALL_GATE_BACKUP="/data/local/tmp/build.prop.orig"
INSTALL_GATE_BACKUP_SHA="/data/local/tmp/build.prop.orig.sha256"
INSTALL_GATE_STAGED="/data/local/tmp/build.prop.install-gate.new"
INSTALL_GATE_STAGED_SHA="/data/local/tmp/build.prop.orig.sha256.new"

install_gate_describe() { echo "Allow every app on the projector to install other apps"; }

install_gate_state() {
    if adb_root_exec "cat $INSTALL_GATE_PROP" 2>/dev/null | tr -d '\r' \
        | grep -qx 'zyzys.install.whitelist=0'; then
        echo applied
    else
        echo not-applied
    fi
}

install_gate_require_file() {
    if ! adb_root_exec "test -f $INSTALL_GATE_PROP" >/dev/null 2>&1 \
        || [[ -z "$(remote_sha256 "$INSTALL_GATE_PROP")" ]]; then
        print_error "$INSTALL_GATE_PROP is missing or unreadable; refusing to create it"
        return 1
    fi
}

install_gate_backup_hash() {
    local actual recorded
    actual=$(remote_sha256 "$INSTALL_GATE_BACKUP")
    [[ -n "$actual" ]] || return 1
    recorded=$(adb_root_exec "cat $INSTALL_GATE_BACKUP_SHA" 2>/dev/null | tr -d '\r\n ')
    [[ "$recorded" == "$actual" ]]
}

install_gate_backup_record() {
    local hash="$1" tmp
    tmp=$(mktemp) || return 1
    printf '%s\n' "$hash" > "$tmp"
    if ! adb push "$tmp" "$INSTALL_GATE_STAGED_SHA" >/dev/null 2>&1 \
        || [[ "$(remote_sha256 "$INSTALL_GATE_STAGED_SHA")" != "$(local_sha256 "$tmp")" ]]; then
        rm -f "$tmp"
        print_error "Could not stage the backup sha256; nothing was written to /system"
        return 1
    fi
    rm -f "$tmp"
    if ! adb_root_exec "sh -c \"cat $INSTALL_GATE_STAGED_SHA > $INSTALL_GATE_BACKUP_SHA\"" >/dev/null 2>&1 \
        || [[ "$(adb_root_exec "cat $INSTALL_GATE_BACKUP_SHA" 2>/dev/null | tr -d '\r\n ')" != "$hash" ]]; then
        print_error "Could not record the backup sha256; nothing was written to /system"
        return 1
    fi
}

install_gate_backup() {
    local current existing
    install_gate_require_file || return 1
    current=$(remote_sha256 "$INSTALL_GATE_PROP")
    existing=$(remote_sha256 "$INSTALL_GATE_BACKUP")
    if [[ -n "$existing" ]]; then
        if ! install_gate_backup_hash; then
            print_error "The existing backup at $INSTALL_GATE_BACKUP has no matching sha256 sidecar; refusing to replace or use it"
            return 1
        fi
        print_status "Keeping the verified backup at $INSTALL_GATE_BACKUP"
        return 0
    fi
    if adb_root_exec "test -f $INSTALL_GATE_BACKUP" >/dev/null 2>&1; then
        print_error "The existing backup at $INSTALL_GATE_BACKUP cannot be hashed; refusing to replace it"
        return 1
    fi
    if ! adb_root_exec "sh -c \"cat $INSTALL_GATE_PROP > $INSTALL_GATE_BACKUP\"" >/dev/null 2>&1 \
        || [[ "$(remote_sha256 "$INSTALL_GATE_BACKUP")" != "$current" ]]; then
        print_error "Could not verify the backup at $INSTALL_GATE_BACKUP; nothing was written to /system"
        return 1
    fi
    install_gate_backup_record "$current" || return 1
    print_status "Backed up $INSTALL_GATE_PROP to $INSTALL_GATE_BACKUP"
}

install_gate_write() {
    local source="$1" expected actual rc=0
    install_gate_require_file || return 1
    expected=$(local_sha256 "$source")
    if ! adb push "$source" "$INSTALL_GATE_STAGED" >/dev/null 2>&1 \
        || [[ "$(remote_sha256 "$INSTALL_GATE_STAGED")" != "$expected" ]]; then
        print_error "The staged build.prop does not match the host copy; nothing was written to /system"
        return 1
    fi

    if system_rw; then
        if ! adb_root_exec "test -f $INSTALL_GATE_PROP" >/dev/null 2>&1; then
            print_error "$INSTALL_GATE_PROP disappeared; refusing to create it"
            rc=1
        elif ! adb_root_exec "sh -c \"cat $INSTALL_GATE_STAGED > $INSTALL_GATE_PROP\"" >/dev/null 2>&1; then
            print_error "Could not write $INSTALL_GATE_PROP"
            rc=1
        fi
        actual=$(remote_sha256 "$INSTALL_GATE_PROP")
        if [[ "$actual" != "$expected" ]]; then
            print_error "$INSTALL_GATE_PROP sha256 ${actual:-unreadable} does not match staged $expected"
            rc=1
        fi
    else
        rc=1
    fi
    if ! system_ro; then
        print_error "The read-only state could not be proven; check /proc/mounts before restarting"
        rc=1
    fi
    return "$rc"
}

install_gate_apply() {
    local tmp rc=0
    install_gate_backup || return 1
    tmp=$(mktemp -d) || return 1
    if ! adb_root_exec "cat $INSTALL_GATE_PROP" > "$tmp/original" 2>/dev/null \
        || [[ "$(local_sha256 "$tmp/original")" != "$(remote_sha256 "$INSTALL_GATE_PROP")" ]]; then
        print_error "Could not read and verify $INSTALL_GATE_PROP; nothing was written"
        rm -rf "$tmp"; return 1
    fi
    awk 'index($0, "zyzys.install.whitelist=") != 1 { print }
         END { print "zyzys.install.whitelist=0" }' "$tmp/original" > "$tmp/new"
    install_gate_write "$tmp/new" || rc=1
    rm -rf "$tmp"
    return "$rc"
}

install_gate_strip() { awk 'index($0, "zyzys.install.whitelist=") != 1 { print }' "$1"; }

install_gate_revert() {
    local tmp rc=0
    install_gate_require_file || return 1
    tmp=$(mktemp -d) || return 1
    if ! adb_root_exec "cat $INSTALL_GATE_PROP" > "$tmp/original" 2>/dev/null \
        || [[ "$(local_sha256 "$tmp/original")" != "$(remote_sha256 "$INSTALL_GATE_PROP")" ]]; then
        print_error "Could not read and verify $INSTALL_GATE_PROP; nothing was written"
        rm -rf "$tmp"; return 1
    fi
    if install_gate_backup_hash; then
        if ! adb_root_exec "cat $INSTALL_GATE_BACKUP" > "$tmp/backup" 2>/dev/null \
            || [[ "$(local_sha256 "$tmp/backup")" != "$(remote_sha256 "$INSTALL_GATE_BACKUP")" ]]; then
            print_error "Could not read and verify $INSTALL_GATE_BACKUP; nothing was written"
            rm -rf "$tmp"; return 1
        fi
    fi
    # A backup older than a later edit would undo that edit, so use it only
    # when it matches the live file everywhere except the whitelist line.
    if [[ -f "$tmp/backup" ]] \
        && cmp -s <(install_gate_strip "$tmp/backup") <(install_gate_strip "$tmp/original"); then
        install_gate_write "$tmp/backup" || rc=1
        [[ "$rc" -ne 0 ]] || print_status "Restored the verified backup verbatim from $INSTALL_GATE_BACKUP"
    else
        if [[ -f "$tmp/backup" ]]; then
            print_warning "The backup at $INSTALL_GATE_BACKUP differs from the live build.prop in other lines; keeping the live file and removing only the whitelist line"
        else
            print_warning "No verified backup; removing the whitelist line from the live build.prop"
        fi
        install_gate_strip "$tmp/original" > "$tmp/restore"
        install_gate_write "$tmp/restore" || rc=1
        [[ "$rc" -ne 0 ]] || print_status "Removed the whitelist line from the live build.prop"
    fi
    rm -rf "$tmp"
    return "$rc"
}
