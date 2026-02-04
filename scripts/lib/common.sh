#!/bin/bash
# Common functions for Android Projector Toolkit scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

# Prevent multiple inclusion
[[ -n "$_COMMON_SH_LOADED" ]] && return 0
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
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
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

# Check if device has root access
check_root_access() {
    local result
    result=$(adb shell "su -c 'whoami'" 2>/dev/null | tr -d '\r\n')

    # Try alternative method if first fails
    if [[ "$result" != "root" ]]; then
        result=$(adb shell "echo 'whoami' | su" 2>/dev/null | tr -d '\r\n')
    fi

    if [[ "$result" == "root" ]]; then
        return 0
    fi
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

# Execute command as root via ADB
# Usage: adb_root_exec "command to run as root"
adb_root_exec() {
    local cmd="$1"
    adb shell "su -c '$cmd'" 2>/dev/null || adb shell "echo '$cmd' | su" 2>/dev/null
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

# Check if a backup directory exists with valid backup
find_backup_dir() {
    local backup_dir
    for backup_dir in projector-backup-*; do
        if [[ -d "$backup_dir" && -f "$backup_dir/full-system-backup.img" ]]; then
            local size
            size=$(stat -f%z "$backup_dir/full-system-backup.img" 2>/dev/null || \
                   stat -c%s "$backup_dir/full-system-backup.img" 2>/dev/null || echo 0)
            if [[ "$size" -gt 1000000000 ]]; then  # At least 1GB
                echo "$backup_dir"
                return 0
            fi
        fi
    done
    return 1
}

# Require backup before proceeding
require_backup() {
    print_step "Verifying backup exists..."

    local backup_dir
    if backup_dir=$(find_backup_dir); then
        local size_gb
        size_gb=$(du -h "$backup_dir/full-system-backup.img" | cut -f1)
        print_success "Found backup: $backup_dir ($size_gb)"
        return 0
    fi

    print_error "No complete backup found!"
    echo
    echo -e "${RED}This script requires a complete device backup.${NC}"
    echo "Run ./MAKE_BACKUP.sh first, then try again."
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

# Human readable file size
human_size() {
    local bytes="$1"
    if [[ "$bytes" -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ "$bytes" -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ "$bytes" -ge 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}
