#!/bin/bash
# Common functions for Android Projector Toolkit scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

# Prevent multiple inclusion. The :- default is required: every entry script
# enables `set -u` before sourcing this file, so a bare $_COMMON_SH_LOADED
# aborts the script here on first load, before anything runs.
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# ============================================================================
# COLORS
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ============================================================================
# PRINT FUNCTIONS
# ============================================================================
# Progress goes to stdout; diagnostics go to stderr. The split matters:
# helpers like adb_root_exec return their payload on stdout and are called as
# out=$(adb_root_exec ...), so a diagnostic written to stdout is captured into
# the caller's variable and never reaches the operator.
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

print_header() {
    local title="$1"
    local width=50
    echo -e "${CYAN}"
    printf '=%.0s' $(seq 1 $width)
    echo
    printf "%*s\n" $(( (${#title} + width) / 2 )) "$title"
    printf '=%.0s' $(seq 1 $width)
    echo -e "${NC}"
    echo
}

print_section() {
    echo
    echo -e "${BOLD}=== $1 ===${NC}"
    echo
}

# ============================================================================
# DEVICE FUNCTIONS
# ============================================================================

# Check if ADB is installed
check_adb() {
    if ! command -v adb &>/dev/null; then
        print_error "ADB is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Check if device is connected via ADB
check_device_connected() {
    if ! adb devices 2>/dev/null | grep -q "device$"; then
        print_error "No Android device connected or not authorized"
        print_warning "Make sure USB debugging is enabled"
        return 1
    fi
    return 0
}

# Which su invocation this device accepts: "direct" (su -c 'cmd') or
# "piped" (echo cmd | su). Probed by check_root_access, consumed by
# adb_root_exec. Empty means root has not been established yet.
SU_MODE=""

# Check if device has root access, and remember which su form worked.
check_root_access() {
    local result

    result=$(adb shell "su -c 'whoami'" 2>/dev/null | tr -d '\r\n')
    if [[ "$result" == "root" ]]; then
        SU_MODE="direct"
        return 0
    fi

    result=$(adb shell "echo 'whoami' | su" 2>/dev/null | tr -d '\r\n')
    if [[ "$result" == "root" ]]; then
        SU_MODE="piped"
        return 0
    fi

    SU_MODE=""
    return 1
}

# Full device check (ADB + connection + optional root)
require_device() {
    local need_root="${1:-false}"

    check_adb || exit 1
    check_device_connected || exit 1

    if [[ "$need_root" == "true" ]]; then
        print_status "Checking root access..."
        if check_root_access; then
            print_success "Root access confirmed"
        else
            print_error "Root access required but not available"
            exit 1
        fi
    fi
}

# ============================================================================
# ADB HELPER FUNCTIONS
# ============================================================================

# Execute a command via ADB with error handling
# Usage: adb_exec "description" "adb shell command"
adb_exec() {
    local desc="$1"
    local cmd="$2"
    local show_cmd="${3:-false}"

    [[ "$show_cmd" == "true" ]] && echo -e "${YELLOW}> $cmd${NC}"

    if eval "$cmd" 2>/dev/null; then
        print_success "$desc"
        return 0
    else
        print_error "$desc failed"
        return 1
    fi
}

# Execute a command as root via ADB, returning its TRUE remote exit status.
#
# `adb shell` cannot be trusted to propagate the far-side status: on older shell
# protocols it exits 0 no matter what happened, and `su -c` does not always pass
# the child's status through either. So the remote status is smuggled back on
# stdout as a sentinel line and parsed here. Without this, a failed dd looks
# exactly like a successful one.
#
# Usage: output=$(adb_root_exec "command"); rc=$?
adb_root_exec() {
    local cmd="$1"
    local raw status

    # The command is embedded in a single-quoted string on the far side; a
    # literal quote would silently truncate it into something else entirely.
    if [[ "$cmd" == *"'"* ]]; then
        print_error "adb_root_exec: command contains a single quote: $cmd"
        return 125
    fi

    case "${SU_MODE:-}" in
        direct) raw=$(adb shell "su -c '$cmd' 2>&1; echo __RC__=\$?" 2>/dev/null) ;;
        piped)  raw=$(adb shell "echo '$cmd' | su 2>&1; echo __RC__=\$?" 2>/dev/null) ;;
        *)
            print_error "adb_root_exec: root not established (require_device true first)"
            return 125
            ;;
    esac

    raw=$(printf '%s' "$raw" | tr -d '\r')

    if [[ "$raw" != *__RC__=* ]]; then
        print_error "adb_root_exec: device returned no exit status for: $cmd"
        return 125
    fi

    status="${raw##*__RC__=}"
    status="${status%%[!0-9]*}"
    [[ -n "$status" ]] || return 125

    # Everything ahead of the sentinel is the command's own output.
    printf '%s' "${raw%__RC__=*}"
    return "$status"
}

# Stream a root command's raw stdout to our stdout, for bulk binary data.
# Usage: adb_root_stream "dd if=/dev/block/mmcblk0 bs=1048576" > image.img
#
# Two things here are not stylistic:
#
#   exec-out, not shell -- `adb shell` runs the far side on a pty on some
#   builds, which translates line endings and silently corrupts binary.
#
#   2>/dev/null is appended HERE, not left to the caller. This device's `su`
#   merges the child's stderr into stdout, so an unsuppressed `dd` appends its
#   ~95-byte "N+0 records in" summary directly into the image. Measured on
#   hardware 2026-07-28: 67108959 bytes back for a 67108864-byte read. A call
#   site can forget the redirect; this cannot.
adb_root_stream() {
    local cmd="$1"

    if [[ "$cmd" == *"'"* ]]; then
        print_error "adb_root_stream: command contains a single quote: $cmd"
        return 125
    fi

    case "${SU_MODE:-}" in
        direct) adb exec-out "su -c '$cmd 2>/dev/null'" ;;
        piped)  adb exec-out "echo '$cmd 2>/dev/null' | su" ;;
        *)
            print_error "adb_root_stream: root not established (require_device true first)"
            return 125
            ;;
    esac
}

# Kill a process and everything beneath it.
#
# `pkill -P` reaches only direct children. When a stalled transfer is killed,
# the subshell's child is `adb`, but anything `adb` itself spawned is a
# grandchild and survives. Measured: repeated stall-kills left dozens of
# orphaned processes behind, which is how a clean test suite starts failing for
# reasons that have nothing to do with the code under test.
kill_tree() {
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child"
    done
    kill -9 "$pid" 2>/dev/null || true
}

# Run a root stream into a file, killing it if the data stops flowing.
#
# This is what makes retrying possible at all. A reaped remote dd does NOT
# close the exec-out stream: the host side sits waiting for bytes that will
# never come, so a retry loop around a bare adb_root_stream never gets control
# back. Measured on hardware 2026-07-28: a 256 MB block stopped at 113 MB and
# the transfer hung indefinitely with the link still healthy.
#
# Usage: adb_root_stream_watched "dd ..." out.tmp [stall_secs]
# Returns 124 if it had to kill a stalled transfer.
adb_root_stream_watched() {
    local cmd="$1" out="$2" stall_secs="${3:-30}"

    : > "$out"
    ( adb_root_stream "$cmd" > "$out" ) &
    local pid=$! last=0 quiet=0 cur

    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        cur=$(local_size "$out")
        if [[ "$cur" -gt "$last" ]]; then
            last=$cur
            quiet=0
        else
            quiet=$((quiet + 2))
            if [[ "$quiet" -ge "$stall_secs" ]]; then
                print_warning "Transfer stalled ${stall_secs}s at $(human_size "$cur") - killing it"
                kill_tree "$pid"
                wait "$pid" 2>/dev/null || true
                return 124
            fi
        fi
    done

    wait "$pid" 2>/dev/null || true
    return 0
}

# Size of a file on the device, or 0 if absent. Never fails the caller.
adb_remote_size() {
    local path="$1"
    local out
    out=$(adb shell "ls -l $path" 2>/dev/null | tr -d '\r' | awk 'NR==1 {print $5}')
    [[ "$out" =~ ^[0-9]+$ ]] && echo "$out" || echo 0
}

# Size of a local file, or 0 if absent. Portable across BSD and GNU stat.
local_size() {
    local path="$1"
    [[ -f "$path" ]] || { echo 0; return; }
    stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0
}

# MD5 of a local file. Portable across BSD (md5) and GNU (md5sum).
local_md5() {
    md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'
}

# Start an Android activity
# Usage: adb_start_activity "com.package/.Activity" "description"
adb_start_activity() {
    local activity="$1"
    local desc="${2:-$activity}"

    print_status "Opening $desc..."
    if adb shell am start -n "$activity" 2>/dev/null | grep -q "Error"; then
        print_warning "$desc may not be available"
        return 1
    fi
    print_success "$desc opened"
    return 0
}

# Start an Android intent action
# Usage: adb_start_action "android.settings.WIFI_SETTINGS" "WiFi Settings"
adb_start_action() {
    local action="$1"
    local desc="${2:-$action}"

    print_status "Opening $desc..."
    adb shell am start -a "$action" 2>/dev/null
    print_success "$desc opened"
}

# ============================================================================
# BACKUP HELPER FUNCTIONS
# ============================================================================

MANIFEST_NAME="backup-manifest.txt"

# Record what a backup is supposed to contain, so it can be checked later.
write_backup_manifest() {
    local device_size="$1"
    local device_block="$2"
    local method="$3"

    {
        echo "device_size=$device_size"
        echo "device_block=$device_block"
        echo "method=$method"
        echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$MANIFEST_NAME"
}

read_manifest_field() {
    local dir="$1" field="$2"
    [[ -f "$dir/$MANIFEST_NAME" ]] || return 1
    local line
    line=$(grep "^${field}=" "$dir/$MANIFEST_NAME" 2>/dev/null | head -1) || return 1
    [[ -n "$line" ]] || return 1
    echo "${line#*=}"
}

# A backup is usable only if the image is exactly the size the manifest says
# the device was. A size-only heuristic (the old ">1GB") passes a backup that
# stopped a third of the way through, which is the one that bricks the device
# on restore.
verify_backup_dir() {
    local backup_dir="$1"
    local img="$backup_dir/full-system-backup.img"

    [[ -f "$img" ]] || return 1

    local expected actual
    expected=$(read_manifest_field "$backup_dir" device_size) || return 2
    [[ "$expected" =~ ^[0-9]+$ && "$expected" -gt 0 ]] || return 2

    actual=$(local_size "$img")
    [[ "$actual" -eq "$expected" ]] || return 3

    return 0
}

# Newest projector-backup-* holding an image but no manifest -- a run that did
# not finish. Without this the streaming resume is unreachable: every run would
# create a fresh timestamped directory and start from zero.
find_incomplete_backup_dir() {
    local d newest=""
    for d in projector-backup-*; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/full-system-backup.img" ]] || continue
        [[ -f "$d/$MANIFEST_NAME" ]] && continue
        newest="$d"          # glob is lexicographic; timestamps sort chronologically
    done
    [[ -n "$newest" ]] && echo "$newest"
}

# Check if a backup directory exists with a verified-complete backup
find_backup_dir() {
    local backup_dir
    for backup_dir in projector-backup-*; do
        [[ -d "$backup_dir" ]] || continue
        if verify_backup_dir "$backup_dir"; then
            echo "$backup_dir"
            return 0
        fi
    done
    return 1
}

# Require a verified backup before proceeding
require_backup() {
    print_step "Verifying backup exists..."

    local backup_dir
    if backup_dir=$(find_backup_dir); then
        print_success "Found verified backup: $backup_dir ($(du -h "$backup_dir/full-system-backup.img" | cut -f1))"
        return 0
    fi

    # Say which way it failed -- "no backup" and "backup is short" need
    # very different responses from the user.
    print_error "No verified backup found!"
    echo
    for backup_dir in projector-backup-*; do
        [[ -d "$backup_dir" ]] || continue
        verify_backup_dir "$backup_dir"
        case $? in
            1) print_warning "$backup_dir: no full-system-backup.img" ;;
            2) print_warning "$backup_dir: no usable $MANIFEST_NAME - cannot verify completeness" ;;
            3) print_error "$backup_dir: image is $(local_size "$backup_dir/full-system-backup.img") bytes, manifest says $(read_manifest_field "$backup_dir" device_size) - TRUNCATED" ;;
        esac
    done
    echo
    echo -e "${RED}This script requires a complete, verified device backup.${NC}"
    echo "Run ./MAKE_BACKUP.sh first, then try again."
    echo
    echo "A backup made before manifests existed can be vouched for by hand:"
    echo "  echo 'device_size=<blockdev --getsize64 output>' > <dir>/$MANIFEST_NAME"
    echo "Only do that if you have independently confirmed the image is complete."
    echo
    exit 1
}

# ============================================================================
# USER INTERACTION
# ============================================================================

# Confirm action with user
# Usage: confirm "Are you sure?" && do_something
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    local yn_hint="y/N"
    [[ "$default" == "y" ]] && yn_hint="Y/n"

    read -r -p "$prompt ($yn_hint): " response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

# Wait for user to press enter
pause() {
    local msg="${1:-Press Enter to continue...}"
    read -r -p "$msg"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Get script directory (handles symlinks)
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Human readable file size, in decimal units.
#
# Decimal, not binary: `blockdev --getsize64` reports 7650410496 for this
# device, which every document, the manifest and the vendor all call 7.65 GB.
# The previous version divided by 1073741824 and labelled the result "GB", so
# the same device read as "7GB" here -- and 1932525568 came out as "1GB" rather
# than 1.93, because it truncated instead of rounding. Two different numbers
# for one device is how you end up doubting a backup that is actually fine.
human_size() {
    local bytes="${1:-0}"
    if [[ "$bytes" -ge 1000000000 ]]; then
        printf '%d.%02dGB\n' $(( bytes / 1000000000 )) $(( (bytes % 1000000000) / 10000000 ))
    elif [[ "$bytes" -ge 1000000 ]]; then
        echo "$(( bytes / 1000000 ))MB"
    elif [[ "$bytes" -ge 1000 ]]; then
        echo "$(( bytes / 1000 ))KB"
    else
        echo "${bytes}B"
    fi
}
