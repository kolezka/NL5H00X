#!/bin/bash
# Complete Device Backup Script
# Creates forensic-level backup of Android projector

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================
# Overridable so the test harness can drive a small stand-in device.
CHUNK_SIZE_MB=${CHUNK_SIZE_MB:-3000}          # Size of backup chunks in MB
DEVICE_BLOCK=${DEVICE_BLOCK:-/dev/block/mmcblk0}
DD_BLOCK_SIZE=${DD_BLOCK_SIZE:-1048576}       # 1MB - compatible with busybox dd
BACKUP_METHOD=unknown                         # set to chunked/direct at runtime

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

get_device_size() {
    local size
    size=$(adb_root_exec "blockdev --getsize64 $DEVICE_BLOCK") || return 1
    size=$(printf '%s' "$size" | tr -d ' \r\n')
    [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 ]] || return 1
    echo "$size"
}

get_device_free_space() {
    adb shell df /sdcard/ 2>/dev/null | tail -1 | awk '{print $4 * 1024}'
}

backup_system_info() {
    print_section "SYSTEM INFORMATION"

    print_status "Saving system properties..."
    adb shell getprop > system-properties.txt
    print_success "system-properties.txt"

    print_status "Saving package lists..."
    adb shell pm list packages -f > installed-packages.txt
    adb shell pm list packages -e > enabled-packages.txt
    adb shell pm list packages -d > disabled-packages.txt
    print_success "Package lists saved"

    print_status "Saving partition info..."
    adb shell "su -c 'cat /proc/partitions'" > partition-info.txt 2>/dev/null || \
        adb shell "echo 'cat /proc/partitions' | su" > partition-info.txt 2>/dev/null
    print_success "partition-info.txt"

    print_status "Saving current launcher..."
    adb shell cmd package get-home-activity > current-home-activity.txt 2>/dev/null || \
        echo "com.newlink.hisilauncher" > current-home-activity.txt
    print_success "current-home-activity.txt"
}

backup_app_data() {
    print_section "APPLICATION DATA"

    print_status "Creating app backup (this may take 10-20 minutes)..."
    print_warning "You may need to confirm on device screen"

    if adb backup -all -f complete-app-backup.ab 2>/dev/null; then
        if [[ -s "complete-app-backup.ab" ]]; then
            local size
            size=$(du -h complete-app-backup.ab | cut -f1)
            print_success "App backup complete ($size)"
        else
            print_warning "App backup was cancelled or empty"
        fi
    else
        print_warning "App backup failed"
    fi
}

backup_partition() {
    local partition="$1"
    local output_file="$2"
    local description="$3"

    print_status "Backing up $description..."

    local expected
    expected=$(adb_root_exec "blockdev --getsize64 $partition" | tr -d ' \r\n')
    if ! [[ "$expected" =~ ^[0-9]+$ ]] || [[ "$expected" -eq 0 ]]; then
        print_error "$description: could not determine partition size"
        return 1
    fi

    local dd_out
    if ! dd_out=$(adb_root_exec "dd if=$partition of=/sdcard/temp_backup.img bs=$DD_BLOCK_SIZE"); then
        print_error "$description: dd failed on device"
        [[ -n "$dd_out" ]] && echo "$dd_out" >&2
        adb shell "rm -f /sdcard/temp_backup.img" >/dev/null 2>&1
        return 1
    fi

    local remote_size
    remote_size=$(adb_remote_size /sdcard/temp_backup.img)
    if [[ "$remote_size" -ne "$expected" ]]; then
        print_error "$description: device copy is $remote_size bytes, expected $expected"
        adb shell "rm -f /sdcard/temp_backup.img" >/dev/null 2>&1
        return 1
    fi

    print_status "Pulling from device ($remote_size bytes)..."
    if ! adb pull /sdcard/temp_backup.img "$output_file" >/dev/null 2>&1; then
        print_error "$description: pull failed"
        adb shell "rm -f /sdcard/temp_backup.img" >/dev/null 2>&1
        return 1
    fi

    local pulled
    pulled=$(local_size "$output_file")
    if [[ "$pulled" -ne "$expected" ]]; then
        print_error "$description: pulled $pulled bytes, expected $expected"
        adb shell "rm -f /sdcard/temp_backup.img" >/dev/null 2>&1
        return 1
    fi

    adb shell "rm -f /sdcard/temp_backup.img" >/dev/null 2>&1
    print_success "$description backed up ($(human_size "$pulled"))"
    return 0
}

backup_full_device_chunked() {
    local device_size="$1"
    local chunk_size_bytes=$((CHUNK_SIZE_MB * 1024 * 1024))
    local total_chunks=$(( (device_size + chunk_size_bytes - 1) / chunk_size_bytes ))

    print_status "Using chunked backup ($total_chunks chunks of ${CHUNK_SIZE_MB}MB)"

    local chunk
    for ((chunk=0; chunk<total_chunks; chunk++)); do
        local skip_mb=$((chunk * CHUNK_SIZE_MB))
        local offset=$((chunk * chunk_size_bytes))
        local chunk_file="backup_chunk_$(printf "%03d" $chunk).img"

        # The final chunk is legitimately short -- dd runs off the end of the
        # device and stops. Every other chunk must be exactly full.
        local remaining=$((device_size - offset))
        local expected=$chunk_size_bytes
        [[ "$remaining" -lt "$expected" ]] && expected=$remaining

        print_status "Chunk $((chunk + 1))/$total_chunks (offset ${skip_mb}MB, expect $(human_size "$expected"))..."

        local dd_out
        if ! dd_out=$(adb_root_exec "dd if=$DEVICE_BLOCK of=/sdcard/chunk.img bs=$DD_BLOCK_SIZE skip=$skip_mb count=$CHUNK_SIZE_MB"); then
            print_error "Chunk $((chunk + 1)): dd failed on device"
            [[ -n "$dd_out" ]] && echo "$dd_out" >&2
            adb shell "rm -f /sdcard/chunk.img" >/dev/null 2>&1
            return 1
        fi

        local chunk_size
        chunk_size=$(adb_remote_size /sdcard/chunk.img)
        if [[ "$chunk_size" -ne "$expected" ]]; then
            print_error "Chunk $((chunk + 1)): device wrote $chunk_size bytes, expected $expected"
            print_error "dd reported success -- this is a silent short write, not a warning"
            adb shell "rm -f /sdcard/chunk.img" >/dev/null 2>&1
            return 1
        fi

        if ! adb pull /sdcard/chunk.img "$chunk_file" >/dev/null 2>&1; then
            print_error "Failed to pull chunk $((chunk + 1))"
            adb shell "rm -f /sdcard/chunk.img" >/dev/null 2>&1
            return 1
        fi

        local pulled
        pulled=$(local_size "$chunk_file")
        if [[ "$pulled" -ne "$expected" ]]; then
            print_error "Chunk $((chunk + 1)): pulled $pulled bytes, expected $expected"
            adb shell "rm -f /sdcard/chunk.img" >/dev/null 2>&1
            return 1
        fi

        adb shell "rm -f /sdcard/chunk.img" >/dev/null 2>&1
        print_success "Chunk $((chunk + 1)) complete ($(human_size "$pulled"))"
    done

    # Combine chunks
    print_status "Combining chunks..."
    cat backup_chunk_*.img > full-system-backup.img

    # Only now is it safe to drop the chunks. Deleting them before this check
    # destroys the only evidence of what actually came off the device.
    local final_size
    final_size=$(local_size full-system-backup.img)
    if [[ "$final_size" -ne "$device_size" ]]; then
        print_error "Combined image is $final_size bytes, device is $device_size bytes"
        print_error "Chunk files kept for inspection: backup_chunk_*.img"
        return 1
    fi

    print_success "Combined backup: $(human_size "$final_size")"
    rm -f backup_chunk_*.img
    return 0
}

backup_full_device_direct() {
    local device_size="$1"

    print_status "Creating full backup on device storage..."
    print_warning "This will take 20-60 minutes"

    # Report progress from a side process while dd runs in the foreground, so
    # the dd's own exit status stays reachable.
    (
        while true; do
            sleep 30
            cur=$(adb_remote_size /sdcard/full_backup.img)
            if [[ "$cur" -gt 0 ]]; then
                print_status "Progress: $(human_size "$cur") / $(human_size "$device_size") ($((cur * 100 / device_size))%)"
            fi
        done
    ) &
    local monitor_pid=$!

    local dd_out rc=0
    dd_out=$(adb_root_exec "dd if=$DEVICE_BLOCK of=/sdcard/full_backup.img bs=$DD_BLOCK_SIZE") || rc=$?

    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true

    if [[ "$rc" -ne 0 ]]; then
        print_error "Full backup: dd failed on device"
        [[ -n "$dd_out" ]] && echo "$dd_out" >&2
        adb shell "rm -f /sdcard/full_backup.img" >/dev/null 2>&1
        return 1
    fi

    local remote_size
    remote_size=$(adb_remote_size /sdcard/full_backup.img)
    if [[ "$remote_size" -ne "$device_size" ]]; then
        print_error "Device copy is $remote_size bytes, expected $device_size"
        adb shell "rm -f /sdcard/full_backup.img" >/dev/null 2>&1
        return 1
    fi

    print_status "Pulling backup from device..."
    if ! adb pull /sdcard/full_backup.img full-system-backup.img >/dev/null 2>&1; then
        print_error "Failed to pull backup from device"
        return 1
    fi

    local pulled
    pulled=$(local_size full-system-backup.img)
    if [[ "$pulled" -ne "$device_size" ]]; then
        print_error "Pulled image is $pulled bytes, expected $device_size"
        return 1
    fi

    adb shell "rm -f /sdcard/full_backup.img" >/dev/null 2>&1
    print_success "Full backup complete: $(human_size "$pulled")"
    return 0
}

create_restore_scripts() {
    print_section "RESTORE SCRIPTS"

    cat > RESTORE.sh << 'RESTORE_EOF'
#!/bin/bash
# Emergency Restore Script

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== EMERGENCY RESTORE ===${NC}"
echo
echo "Options:"
echo "  1. Reset launcher only (safe)"
echo "  2. Restore app data (safe)"
echo "  3. Restore system partition (moderate risk)"
echo "  4. Full device restore (high risk)"
echo "  q. Quit"
echo
read -p "Select option: " choice

case "$choice" in
    1)
        echo "Resetting launcher..."
        HOME=$(cat current-home-activity.txt 2>/dev/null | tr -d '\r\n')
        adb shell cmd package set-home-activity "${HOME:-com.newlink.hisilauncher}"
        echo -e "${GREEN}Launcher reset${NC}"
        ;;
    2)
        [[ -f complete-app-backup.ab ]] && adb restore complete-app-backup.ab || echo "No app backup found"
        ;;
    3)
        if [[ -f system.img ]]; then
            echo "Restoring system partition..."
            adb push system.img /sdcard/
            adb shell "su -c 'dd if=/sdcard/system.img of=/dev/block/mmcblk0p20 bs=1048576'"
            adb shell rm -f /sdcard/system.img
            echo -e "${GREEN}System partition restored${NC}"
        else
            echo "No system backup found"
        fi
        ;;
    4)
        echo -e "${RED}WARNING: This will overwrite EVERYTHING${NC}"

        # Refuse to write a short image over the whole device -- that is the
        # one action that turns a bad backup into a dead projector.
        if [[ ! -f full-system-backup.img ]]; then
            echo -e "${RED}No full-system-backup.img here${NC}"
            exit 1
        fi
        expected=$(grep '^device_size=' backup-manifest.txt 2>/dev/null | cut -d= -f2)
        actual=$(stat -f%z full-system-backup.img 2>/dev/null || stat -c%s full-system-backup.img 2>/dev/null)
        if [[ -z "$expected" ]]; then
            echo -e "${RED}No backup-manifest.txt - cannot confirm this image is complete.${NC}"
            echo "Refusing to restore. Verify the image by hand first."
            exit 1
        fi
        if [[ "$actual" != "$expected" ]]; then
            echo -e "${RED}Image is $actual bytes, manifest says $expected - TRUNCATED.${NC}"
            echo "Restoring it would overwrite the device with an incomplete copy."
            exit 1
        fi
        echo -e "${GREEN}Image verified: $actual bytes${NC}"

        read -p "Type RESTORE to confirm: " confirm
        if [[ "$confirm" == "RESTORE" ]]; then
            echo "Starting full restore..."
            adb push full-system-backup.img /sdcard/ || {
                echo "Streaming restore..."
                cat full-system-backup.img | adb shell "su -c 'dd of=/dev/block/mmcblk0 bs=1048576'"
            }
            adb reboot
        fi
        ;;
esac
RESTORE_EOF

    chmod +x RESTORE.sh
    print_success "RESTORE.sh created"

    # Quick launcher reset script
    cat > reset-launcher.sh << 'EOF'
#!/bin/bash
adb shell cmd package set-home-activity com.newlink.hisilauncher
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
echo "Launcher reset to default"
EOF
    chmod +x reset-launcher.sh
    print_success "reset-launcher.sh created"
}

verify_backup() {
    local device_size="$1"

    print_section "VERIFICATION"

    local backup_ok=true

    # Size against the device, not merely "non-empty". A third of an image is
    # non-empty and will happily brick the projector on restore.
    local size
    size=$(local_size full-system-backup.img)
    if [[ "$size" -eq 0 ]]; then
        print_error "Full backup: MISSING"
        backup_ok=false
    elif [[ "$size" -ne "$device_size" ]]; then
        print_error "Full backup: $(human_size "$size") but device is $(human_size "$device_size") - TRUNCATED"
        print_error "  got      $size bytes"
        print_error "  expected $device_size bytes"
        backup_ok=false
    else
        print_success "Full backup: $(human_size "$size") (matches device exactly)"
    fi

    [[ -s system.img ]] && print_success "System partition: $(du -h system.img | cut -f1)" || print_warning "System partition: not available"
    [[ -s boot.img ]] && print_success "Boot partition: $(du -h boot.img | cut -f1)" || print_warning "Boot partition: not available"
    [[ -s complete-app-backup.ab ]] && print_success "App backup: $(du -h complete-app-backup.ab | cut -f1)" || print_warning "App backup: not available"

    echo
    if [[ "$backup_ok" == true ]]; then
        # The manifest is what UNLOCK.sh's require_backup checks. Writing it
        # only here means a failed run can never vouch for its own output.
        write_backup_manifest "$device_size" "$DEVICE_BLOCK" "$BACKUP_METHOD"
        echo -e "${GREEN}BACKUP COMPLETE - Safe to proceed with modifications${NC}"
        return 0
    fi

    rm -f "$MANIFEST_NAME"
    echo -e "${RED}BACKUP INCOMPLETE - Do NOT modify system${NC}"
    return 1
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "PROJECTOR BACKUP"

    # Check requirements
    require_device true

    # Create backup directory
    local backup_dir="projector-backup-$(date +%Y%m%d_%H%M%S)"
    print_status "Creating backup directory: $backup_dir"
    mkdir -p "$backup_dir"
    cd "$backup_dir"

    # Get device info
    print_status "Getting device information..."
    local device_size
    if ! device_size=$(get_device_size); then
        print_error "Could not determine device size"
        exit 1
    fi

    print_success "Device size: $(human_size "$device_size")"

    # Phase 1: System information
    backup_system_info

    # Phase 2: App data
    backup_app_data

    # Phase 3: Critical partitions
    print_section "PARTITION BACKUPS"
    backup_partition "/dev/block/mmcblk0p1" "boot.img" "boot partition" || true
    backup_partition "/dev/block/mmcblk0p20" "system.img" "system partition" || true

    # Phase 4: Full device backup
    print_section "FULL DEVICE BACKUP"
    print_warning "Backing up $(human_size "$device_size") - this takes 20-60 minutes"

    local free_space
    free_space=$(get_device_free_space)
    [[ "$free_space" =~ ^[0-9]+$ ]] || free_space=0

    # Recorded in the manifest so a restore knows how the image was assembled.
    if [[ "$device_size" -gt "$free_space" ]]; then
        print_warning "Device space limited - using chunked backup"
        BACKUP_METHOD=chunked
        backup_full_device_chunked "$device_size" || true
    else
        BACKUP_METHOD=direct
        backup_full_device_direct "$device_size" || true
    fi

    # Phase 5: Create restore scripts
    create_restore_scripts

    # Phase 6: Verification -- the single place that decides pass/fail
    local verdict=0
    verify_backup "$device_size" || verdict=1

    echo
    print_status "Backup location: $(pwd)"
    echo
    return "$verdict"
}

main "$@"
