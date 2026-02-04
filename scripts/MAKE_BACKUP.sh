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
CHUNK_SIZE_MB=3000          # Size of backup chunks in MB
DEVICE_BLOCK="/dev/block/mmcblk0"
DD_BLOCK_SIZE=1048576       # 1MB - compatible with busybox dd

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

get_device_size() {
    local size
    size=$(adb shell "su -c 'blockdev --getsize64 $DEVICE_BLOCK'" 2>/dev/null | tr -d '\r\n')
    [[ -z "$size" || "$size" == "0" ]] && size=$(adb shell "echo 'blockdev --getsize64 $DEVICE_BLOCK' | su" 2>/dev/null | tr -d '\r\n')
    echo "${size:-0}"
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

    # Create backup on device
    adb shell "su -c 'dd if=$partition of=/sdcard/temp_backup.img bs=$DD_BLOCK_SIZE'" 2>/dev/null || \
        adb shell "echo 'dd if=$partition of=/sdcard/temp_backup.img bs=$DD_BLOCK_SIZE' | su" 2>/dev/null

    # Check if created
    local remote_size
    remote_size=$(adb shell ls -l /sdcard/temp_backup.img 2>/dev/null | awk '{print $5}')

    if [[ "${remote_size:-0}" -gt 0 ]]; then
        print_status "Pulling from device ($remote_size bytes)..."
        if adb pull /sdcard/temp_backup.img "$output_file" 2>/dev/null; then
            adb shell rm -f /sdcard/temp_backup.img
            local size
            size=$(du -h "$output_file" | cut -f1)
            print_success "$description backed up ($size)"
            return 0
        fi
    fi

    adb shell rm -f /sdcard/temp_backup.img 2>/dev/null
    print_error "$description backup failed"
    return 1
}

backup_full_device_chunked() {
    local device_size="$1"
    local chunk_size_bytes=$((CHUNK_SIZE_MB * 1024 * 1024))
    local total_chunks=$(( (device_size + chunk_size_bytes - 1) / chunk_size_bytes ))

    print_status "Using chunked backup ($total_chunks chunks of ${CHUNK_SIZE_MB}MB)"

    local chunk
    for ((chunk=0; chunk<total_chunks; chunk++)); do
        local skip_mb=$((chunk * CHUNK_SIZE_MB))
        local chunk_file="backup_chunk_$(printf "%03d" $chunk).img"

        print_status "Chunk $((chunk + 1))/$total_chunks (offset ${skip_mb}MB)..."

        # Create chunk on device
        adb shell "su -c 'dd if=$DEVICE_BLOCK of=/sdcard/chunk.img bs=$DD_BLOCK_SIZE skip=$skip_mb count=$CHUNK_SIZE_MB'" 2>/dev/null || \
            adb shell "echo 'dd if=$DEVICE_BLOCK of=/sdcard/chunk.img bs=$DD_BLOCK_SIZE skip=$skip_mb count=$CHUNK_SIZE_MB' | su" 2>/dev/null

        # Pull chunk
        local chunk_size
        chunk_size=$(adb shell ls -l /sdcard/chunk.img 2>/dev/null | awk '{print $5}')

        if [[ "${chunk_size:-0}" -gt 0 ]]; then
            if adb pull /sdcard/chunk.img "$chunk_file" 2>/dev/null; then
                adb shell rm -f /sdcard/chunk.img
                print_success "Chunk $((chunk + 1)) complete"
            else
                print_error "Failed to pull chunk $((chunk + 1))"
                adb shell rm -f /sdcard/chunk.img 2>/dev/null
                return 1
            fi
        else
            print_error "Chunk $((chunk + 1)) not created on device"
            return 1
        fi
    done

    # Combine chunks
    print_status "Combining chunks..."
    cat backup_chunk_*.img > full-system-backup.img

    if [[ -s "full-system-backup.img" ]]; then
        local final_size
        final_size=$(stat -f%z full-system-backup.img 2>/dev/null || stat -c%s full-system-backup.img 2>/dev/null)
        print_success "Combined backup: $(human_size "$final_size")"
        rm -f backup_chunk_*.img
        return 0
    fi

    print_error "Failed to combine chunks"
    return 1
}

backup_full_device_direct() {
    local device_size="$1"

    print_status "Creating full backup on device storage..."
    print_warning "This will take 20-60 minutes"

    # Start backup in background
    adb shell "su -c 'dd if=$DEVICE_BLOCK of=/sdcard/full_backup.img bs=$DD_BLOCK_SIZE'" &
    local pid=$!

    # Monitor progress
    while kill -0 $pid 2>/dev/null; do
        local current
        current=$(adb shell ls -l /sdcard/full_backup.img 2>/dev/null | awk '{print $5}')
        if [[ "${current:-0}" -gt 0 ]]; then
            local pct=$((current * 100 / device_size))
            print_status "Progress: $(human_size "$current") / $(human_size "$device_size") (${pct}%)"
        fi
        sleep 30
    done
    wait $pid

    # Pull the backup
    local final_size
    final_size=$(adb shell ls -l /sdcard/full_backup.img 2>/dev/null | awk '{print $5}')

    if [[ "${final_size:-0}" -gt 0 ]]; then
        print_status "Pulling backup from device..."
        if adb pull /sdcard/full_backup.img full-system-backup.img 2>/dev/null; then
            adb shell rm -f /sdcard/full_backup.img
            print_success "Full backup complete: $(human_size "$final_size")"
            return 0
        fi
    fi

    adb shell rm -f /sdcard/full_backup.img 2>/dev/null
    print_error "Full backup failed"
    return 1
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
        read -p "Type RESTORE to confirm: " confirm
        if [[ "$confirm" == "RESTORE" && -f full-system-backup.img ]]; then
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
    print_section "VERIFICATION"

    local backup_ok=true

    if [[ -s full-system-backup.img ]]; then
        local size
        size=$(stat -f%z full-system-backup.img 2>/dev/null || stat -c%s full-system-backup.img 2>/dev/null)
        print_success "Full backup: $(human_size "$size")"
    else
        print_error "Full backup: MISSING"
        backup_ok=false
    fi

    [[ -s system.img ]] && print_success "System partition: $(du -h system.img | cut -f1)" || print_warning "System partition: not available"
    [[ -s boot.img ]] && print_success "Boot partition: $(du -h boot.img | cut -f1)" || print_warning "Boot partition: not available"
    [[ -s complete-app-backup.ab ]] && print_success "App backup: $(du -h complete-app-backup.ab | cut -f1)" || print_warning "App backup: not available"

    echo
    if [[ "$backup_ok" == true ]]; then
        echo -e "${GREEN}BACKUP COMPLETE - Safe to proceed with modifications${NC}"
    else
        echo -e "${RED}BACKUP INCOMPLETE - Do NOT modify system${NC}"
    fi
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
    device_size=$(get_device_size)

    if [[ "$device_size" -eq 0 ]]; then
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

    if [[ "$device_size" -gt "$free_space" ]]; then
        print_warning "Device space limited - using chunked backup"
        backup_full_device_chunked "$device_size"
    else
        backup_full_device_direct "$device_size"
    fi

    # Phase 5: Create restore scripts
    create_restore_scripts

    # Phase 6: Verification
    verify_backup

    echo
    print_status "Backup location: $(pwd)"
    echo
}

main "$@"
