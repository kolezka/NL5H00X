#!/bin/bash
# A small random image using the same four manifest fields as the toolkit.
set -u

block_fixture() (
    set -u
    local directory="${1:?usage: block-fixture.sh DIRECTORY [BYTES]}"
    local bytes="${2:-4194304}" root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    case "$bytes" in ''|*[!0-9]*) echo 'size must be a positive byte count' >&2; return 1 ;; esac
    [[ "$bytes" -gt 0 ]] || return 1
    mkdir -p "$directory" || return 1
    directory="$(cd "$directory" && pwd)" || return 1
    [[ ! -e "$directory/full-system-backup.img" && ! -e "$directory/backup-manifest.txt" ]] || {
        echo 'refusing to overwrite an existing fixture' >&2
        return 1
    }
    /usr/bin/head -c "$bytes" /dev/urandom > "$directory/full-system-backup.img" || return 1
    printf 'device_size=%s\ndevice_block=/dev/block/mmcblk0\nmethod=fixture\ncreated=%s\n' \
        "$bytes" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$directory/backup-manifest.txt" || return 1
    # Verification is local only; common.sh defines functions without device I/O.
    "$BASH" -c "source \"\$1\"; verify_backup_dir \"\$2\"" bash \
        "$root/scripts/lib/common.sh" "$directory" || return 1
    printf '%s\n' "$directory/full-system-backup.img" "$directory/backup-manifest.txt"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    block_fixture "$@"
fi
