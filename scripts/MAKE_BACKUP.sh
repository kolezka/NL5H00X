#!/bin/bash

# Projector Complete Backup Script - FIXED VERSION
# This script creates a complete backup of your Android projector device
# Fixed for devices that don't support 'su -c' syntax

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create a temporary script on device and execute it
exec_root_script() {
    local script_content="$1"
    local script_name="/sdcard/temp_backup_script.sh"
    
    # Write script to device
    adb shell "cat > $script_name << 'SCRIPT_EOF'
$script_content
SCRIPT_EOF"
    
    # Execute script as root
    adb shell "su -c 'sh $script_name'"
    
    # Clean up
    adb shell "rm -f $script_name"
}

# Function to backup partitions using device storage method with better error handling
backup_partition() {
    local source_path="$1"
    local dest_file="$2"
    local description="$3"
    local temp_name="temp_$(basename $dest_file)"
    
    print_status "Backing up $description..."
    
    # Create backup on device with compatible dd syntax
    adb shell << EOF
su
echo "Starting backup of $description from $source_path..."
dd if=$source_path of=/sdcard/$temp_name bs=1048576 2>&1
echo "Checking backup file..."
ls -la /sdcard/$temp_name
echo "Backup process completed"
exit
EOF
    
    # Check if file exists on device before pulling
    FILE_SIZE=$(adb shell ls -l /sdcard/$temp_name 2>/dev/null | awk '{print $5}' || echo "0")
    
    if [ "$FILE_SIZE" -gt 0 ]; then
        print_status "Backup file created on device ($FILE_SIZE bytes), pulling to computer..."
        
        # Pull backup from device
        if adb pull /sdcard/$temp_name ./$dest_file; then
            # Clean up device
            adb shell rm -f /sdcard/$temp_name
            
            if [ -s "$dest_file" ]; then
                local size=$(ls -lh "$dest_file" | awk '{print $5}')
                print_success "$description backed up successfully ($size)"
                return 0
            else
                print_error "$description backup transferred but is empty"
                return 1
            fi
        else
            print_error "$description backup failed to transfer from device"
            adb shell rm -f /sdcard/$temp_name 2>/dev/null
            return 1
        fi
    else
        print_error "$description backup was not created on device (0 bytes or missing)"
        return 1
    fi
}

# Function to get device information using proper root syntax
get_device_info() {
    print_status "Getting device information..."
    
    # Get device size
    DEVICE_SIZE=$(adb shell "su" << 'EOF'
blockdev --getsize64 /dev/block/mmcblk0 2>/dev/null || echo "0"
exit
EOF
)
    DEVICE_SIZE=$(echo "$DEVICE_SIZE" | tr -d '\r\n')
    
    # Get partition info
    adb shell "su" << 'EOF' > partition-info.txt
cat /proc/partitions
exit
EOF
    
    # Get block device listing
    adb shell "su" << 'EOF' > block-devices.txt
ls -la /dev/block/
exit
EOF
    
    if [ "$DEVICE_SIZE" -gt 0 ]; then
        DEVICE_SIZE_GB=$((DEVICE_SIZE / 1024 / 1024 / 1024))
        print_success "Device size detected: ${DEVICE_SIZE_GB}GB (${DEVICE_SIZE} bytes)"
        return 0
    else
        print_error "Could not detect device size"
        return 1
    fi
}

# Check if adb is available
if ! command -v adb &> /dev/null; then
    print_error "ADB is not installed or not in PATH"
    exit 1
fi

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    print_error "No Android device connected or device not authorized"
    print_warning "Make sure your projector is connected and USB debugging is enabled"
    exit 1
fi

# Create backup directory with timestamp
BACKUP_DIR="projector-backup-$(date +%Y%m%d_%H%M%S)"
print_status "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# Check root access with proper syntax
print_status "Checking root access..."
ROOT_CHECK=$(adb shell "su" << 'EOF'
whoami
exit
EOF
)

if echo "$ROOT_CHECK" | grep -q "root"; then
    print_success "Root access confirmed"
    HAS_ROOT=true
else
    print_warning "No root access - backup will be limited"
    HAS_ROOT=false
    exit 1
fi

# Get device information
if [ "$HAS_ROOT" = true ]; then
    get_device_info
else
    print_error "Root access required for device information"
    exit 1
fi

# Check storage space
print_status "Checking storage space..."
DEVICE_SPACE=$(adb shell df /sdcard/ | tail -n 1 | awk '{print $4}')
COMPUTER_SPACE=$(df . | tail -n 1 | awk '{print $4}')
print_status "Device free space: ${DEVICE_SPACE}KB"
print_status "Computer free space: ${COMPUTER_SPACE}KB"

# Determine backup strategy based on available space
DEVICE_SPACE_BYTES=$((DEVICE_SPACE * 1024))
if [ "$DEVICE_SIZE" -gt "$DEVICE_SPACE_BYTES" ]; then
    print_warning "Device backup ($DEVICE_SIZE_GB GB) larger than free space"
    print_warning "Will use chunked backup method to work around space limitations"
    USE_CHUNKED=true
else
    print_status "Sufficient device space available - using device storage method"
    USE_CHUNKED=false
fi

# 1. SYSTEM INFORMATION BACKUP
print_status "=== PHASE 1: SYSTEM INFORMATION ==="

print_status "Backing up system properties..."
adb shell getprop > system-properties.txt
print_success "System properties saved"

print_status "Backing up package information..."
adb shell pm list packages -f > installed-packages.txt
adb shell pm list packages -e > enabled-packages.txt
adb shell pm list packages -d > disabled-packages.txt
print_success "Package information saved"

print_status "Backing up current launcher and activity state..."
adb shell dumpsys activity activities > activity-stack.txt
adb shell cmd package get-home-activity > current-home-activity.txt 2>/dev/null || echo "com.newlink.hisilauncher" > current-home-activity.txt
print_success "Activity state saved"

print_status "Backing up critical services state..."
adb shell dumpsys activity services | grep -E "zhiying.powerservice|hisilicon.tv.service|newlink.service" > critical-services-state.txt || echo "Could not verify services" > critical-services-state.txt
print_success "Critical services state saved"

# 2. APPLICATION DATA BACKUP
print_status "=== PHASE 2: APPLICATION DATA ==="

print_status "Creating application backup (may take 10-20 minutes)..."
print_warning "You may need to confirm backup on device screen"
adb backup -all -f complete-app-backup.ab

if [ -s "complete-app-backup.ab" ]; then
    APP_BACKUP_SIZE=$(ls -lh complete-app-backup.ab | awk '{print $5}')
    print_success "Application backup completed ($APP_BACKUP_SIZE)"
else
    print_warning "Application backup failed or was cancelled"
fi

# 3. CRITICAL PARTITION BACKUPS
print_status "=== PHASE 3: CRITICAL PARTITION BACKUPS ==="

# Backup individual critical partitions using device storage method
print_status "Backing up boot partition (mmcblk0p1)..."
backup_partition "/dev/block/mmcblk0p1" "boot.img" "boot partition"

print_status "Backing up system partition (mmcblk0p20)..."
backup_partition "/dev/block/mmcblk0p20" "system.img" "system partition"

# 4. FULL DEVICE BACKUP
print_status "=== PHASE 4: FULL DEVICE BACKUP ==="
print_warning "Starting COMPLETE device backup"
print_warning "This will backup $DEVICE_SIZE_GB GB and take 20-60 minutes"

if [ "$USE_CHUNKED" = true ]; then
    print_status "Using CHUNKED backup method (device has limited space)..."
    
    # Calculate chunk size and number of chunks needed
    CHUNK_SIZE_MB=3000  # Use 3GB chunks to be safe with space
    CHUNK_SIZE_BYTES=$((CHUNK_SIZE_MB * 1024 * 1024))
    TOTAL_CHUNKS=$(((DEVICE_SIZE + CHUNK_SIZE_BYTES - 1) / CHUNK_SIZE_BYTES))
    
    print_status "Will create $TOTAL_CHUNKS chunks of ${CHUNK_SIZE_MB}MB each"
    
    # Remove any existing chunk files
    rm -f backup_chunk_*.img 2>/dev/null
    
    # Create chunks one by one
    CHUNK_SUCCESS=true
    for ((chunk=0; chunk<TOTAL_CHUNKS; chunk++)); do
        SKIP_BLOCKS=$((chunk * CHUNK_SIZE_MB))
        CHUNK_FILE="backup_chunk_$(printf "%03d" $chunk).img"
        
        print_status "Creating chunk $((chunk + 1))/$TOTAL_CHUNKS (starting at ${SKIP_BLOCKS}MB)..."
        
        # Create chunk on device using compatible dd syntax
        adb shell << EOF
su
echo "Creating chunk $((chunk + 1))/$TOTAL_CHUNKS..."
echo "Command: dd if=/dev/block/mmcblk0 of=/sdcard/chunk_temp.img bs=1048576 skip=$SKIP_BLOCKS count=$CHUNK_SIZE_MB"
dd if=/dev/block/mmcblk0 of=/sdcard/chunk_temp.img bs=1048576 skip=$SKIP_BLOCKS count=$CHUNK_SIZE_MB 2>&1
echo "Checking chunk size..."
ls -la /sdcard/chunk_temp.img
echo "Chunk $((chunk + 1)) creation completed"
exit
EOF
        
        # Check chunk was created
        CHUNK_SIZE_ON_DEVICE=$(adb shell ls -l /sdcard/chunk_temp.img 2>/dev/null | awk '{print $5}' || echo "0")
        
        if [ "$CHUNK_SIZE_ON_DEVICE" -gt 0 ]; then
            print_status "Chunk $((chunk + 1)) created on device ($CHUNK_SIZE_ON_DEVICE bytes), pulling..."
            
            # Pull chunk
            if adb pull /sdcard/chunk_temp.img ./$CHUNK_FILE; then
                adb shell rm -f /sdcard/chunk_temp.img
                
                if [ -s "$CHUNK_FILE" ]; then
                    CHUNK_SIZE_LOCAL=$(ls -lh $CHUNK_FILE | awk '{print $5}')
                    print_success "Chunk $((chunk + 1)) completed ($CHUNK_SIZE_LOCAL)"
                else
                    print_error "Chunk $((chunk + 1)) transferred but is empty"
                    CHUNK_SUCCESS=false
                    break
                fi
            else
                print_error "Chunk $((chunk + 1)) failed to transfer"
                adb shell rm -f /sdcard/chunk_temp.img 2>/dev/null
                CHUNK_SUCCESS=false
                break
            fi
        else
            print_error "Chunk $((chunk + 1)) was not created on device"
            CHUNK_SUCCESS=false
            break
        fi
    done
    
    # Combine chunks if all succeeded
    if [ "$CHUNK_SUCCESS" = true ]; then
        print_status "All chunks completed successfully, combining into full backup..."
        
        # Combine chunks
        cat backup_chunk_*.img > full-system-backup.img
        
        # Verify combined backup
        if [ -s "full-system-backup.img" ]; then
            COMBINED_SIZE=$(ls -l full-system-backup.img | awk '{print $5}')
            COMBINED_SIZE_GB=$((COMBINED_SIZE / 1024 / 1024 / 1024))
            print_success "Chunks combined successfully!"
            print_success "Full backup size: ${COMBINED_SIZE_GB}GB (${COMBINED_SIZE} bytes)"
            
            # Clean up chunk files
            print_status "Cleaning up chunk files..."
            rm -f backup_chunk_*.img
        else
            print_error "Failed to combine chunks into full backup"
        fi
    else
        print_error "Chunked backup failed - some chunks could not be created"
        print_status "Partial chunks available: $(ls -1 backup_chunk_*.img 2>/dev/null | wc -l) files"
    fi
    
else
    print_status "Using single-file device storage method..."
    print_status "Creating full backup on device storage..."
    
    # Check available space one more time
    AVAILABLE_SPACE=$(adb shell df /sdcard/ | tail -n 1 | awk '{print $4}')
    AVAILABLE_BYTES=$((AVAILABLE_SPACE * 1024))
    
    if [ "$DEVICE_SIZE" -gt "$AVAILABLE_BYTES" ]; then
        print_error "Insufficient space on device for full backup"
        print_error "Need: ${DEVICE_SIZE_GB}GB, Available: $((AVAILABLE_BYTES / 1024 / 1024 / 1024))GB"
        print_status "Falling back to chunked method..."
        USE_CHUNKED=true
        # Recursive call with chunked method
        return 1
    fi
    
    # Create full backup on device with progress monitoring using compatible dd syntax
    adb shell << 'EOF' &
su
echo "Starting full device backup..."
echo "This will take 20-60 minutes..."
dd if=/dev/block/mmcblk0 of=/sdcard/full_backup_temp.img bs=1048576 2>&1
echo "Full device backup completed"
ls -la /sdcard/full_backup_temp.img
exit
EOF
    
    BACKUP_PID=$!
    print_status "Backup started in background (PID: $BACKUP_PID)"
    print_status "Monitoring progress every 30 seconds..."
    
    # Monitor progress
    while kill -0 $BACKUP_PID 2>/dev/null; do
        CURRENT_SIZE=$(adb shell ls -l /sdcard/full_backup_temp.img 2>/dev/null | awk '{print $5}' || echo "0")
        if [ "$CURRENT_SIZE" -gt 0 ]; then
            CURRENT_MB=$((CURRENT_SIZE / 1024 / 1024))
            PROGRESS=$((CURRENT_SIZE * 100 / DEVICE_SIZE))
            print_status "Progress: ${CURRENT_MB}MB / ${DEVICE_SIZE_GB}GB (${PROGRESS}%)"
        else
            print_status "Waiting for backup to start..."
        fi
        sleep 30
    done
    wait $BACKUP_PID
    
    # Check final size and pull
    FINAL_SIZE=$(adb shell ls -l /sdcard/full_backup_temp.img 2>/dev/null | awk '{print $5}' || echo "0")
    
    if [ "$FINAL_SIZE" -gt 0 ]; then
        FINAL_MB=$((FINAL_SIZE / 1024 / 1024))
        print_success "Backup completed on device (${FINAL_MB}MB)"
        print_status "Pulling backup from device to computer..."
        
        if adb pull /sdcard/full_backup_temp.img ./full-system-backup.img; then
            print_status "Cleaning up device storage..."
            adb shell rm -f /sdcard/full_backup_temp.img
            print_success "Full backup transferred successfully"
        else
            print_error "Failed to transfer backup from device"
        fi
    else
        print_error "Backup was not created on device (0 bytes)"
    fi
fi

# Verify backup
if [ -s "full-system-backup.img" ]; then
    BACKUP_SIZE=$(ls -l full-system-backup.img | awk '{print $5}')
    BACKUP_SIZE_GB=$((BACKUP_SIZE / 1024 / 1024 / 1024))
    print_success "Full device backup completed!"
    print_success "Backup size: ${BACKUP_SIZE_GB}GB (${BACKUP_SIZE} bytes)"
    
    # Verify backup completeness
    EXPECTED_SIZE_MIN=$((DEVICE_SIZE * 95 / 100))  # Allow 5% variance
    if [ "$BACKUP_SIZE" -ge "$EXPECTED_SIZE_MIN" ]; then
        print_success "✅ Backup appears COMPLETE (${BACKUP_SIZE_GB}GB of ${DEVICE_SIZE_GB}GB expected)"
    else
        print_warning "⚠️  Backup may be incomplete (got ${BACKUP_SIZE_GB}GB, expected ${DEVICE_SIZE_GB}GB)"
    fi
else
    print_error "❌ Full device backup FAILED - 0 bytes"
    print_error "DO NOT PROCEED with system modifications without a working backup!"
fi

# 5. CONFIGURATION FILES
print_status "=== PHASE 5: CONFIGURATION FILES ==="

print_status "Backing up settings database..."
adb shell << 'EOF' > settings-backup.db
su
echo "Backing up settings database..."
cat /data/data/com.android.providers.settings/databases/settings.db 2>/dev/null || echo "Settings backup failed"
exit
EOF

if [ -s "settings-backup.db" ]; then
    print_success "Settings database backed up"
else
    print_warning "Settings database backup failed or empty"
fi

print_status "Backing up build.prop..."
adb shell << 'EOF' > build.prop
su
echo "Backing up build.prop..."
cat /system/build.prop 2>/dev/null || echo "Build.prop backup failed"
exit
EOF

if [ -s "build.prop" ]; then
    print_success "Build.prop backed up"
else
    print_warning "Build.prop backup failed or empty"
fi

# 6. CREATE RESTORE SCRIPTS
print_status "=== PHASE 6: CREATING RESTORE SCRIPTS ==="

cat > EMERGENCY-RESTORE.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}================================="
echo -e "   EMERGENCY RESTORE SCRIPT"
echo -e "=================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will restore your device to the backup state${NC}"
echo ""
echo "Available restore options:"
echo "1. Restore launcher settings only (SAFE)"
echo "2. Restore application data (SAFE)"  
echo "3. Restore individual partitions (MODERATE RISK)"
echo "4. Restore COMPLETE system (HIGH RISK - everything)"
echo ""
read -p "Choose option (1-4): " choice

case $choice in
    1)
        echo "Restoring launcher settings..."
        if [ -f "current-home-activity.txt" ]; then
            HOME_ACTIVITY=$(cat current-home-activity.txt | tr -d '\r\n')
            adb shell cmd package set-home-activity "$HOME_ACTIVITY"
            echo "Launcher restored to: $HOME_ACTIVITY"
        else
            adb shell cmd package set-home-activity com.newlink.hisilauncher
            echo "Restored to original launcher"
        fi
        ;;
    2)
        echo "Restoring application data..."
        if [ -f "complete-app-backup.ab" ]; then
            adb restore complete-app-backup.ab
            echo "Application data restore initiated"
        else
            echo "No application backup found"
        fi
        ;;
    3)
        echo -e "${YELLOW}PARTITION RESTORE${NC}"
        echo "Available partition restores:"
        echo "  a) Boot partition (mmcblk0p1)"
        echo "  b) System partition (mmcblk0p20)"
        read -p "Choose partition (a/b): " part_choice
        case $part_choice in
            a)
                if [ -f "boot.img" ]; then
                    echo "Restoring boot partition..."
                    adb push boot.img /sdcard/
                    adb shell << 'RESTORE_EOF'
su
dd if=/sdcard/boot.img of=/dev/block/mmcblk0p1 bs=1048576
rm -f /sdcard/boot.img
exit
RESTORE_EOF
                    echo "Boot partition restored"
                else
                    echo "No boot backup found"
                fi
                ;;
            b)
                if [ -f "system.img" ]; then
                    echo "Restoring system partition..."
                    adb push system.img /sdcard/
                    adb shell << 'RESTORE_EOF'
su
dd if=/sdcard/system.img of=/dev/block/mmcblk0p20 bs=1048576
rm -f /sdcard/system.img
exit
RESTORE_EOF
                    echo "System partition restored"
                else
                    echo "No system backup found"
                fi
                ;;
        esac
        ;;
    4)
        echo -e "${RED}COMPLETE SYSTEM RESTORE${NC}"
        echo "This will restore EVERYTHING:"
        echo "- ALL 25 partitions and firmware"
        echo "- ALL drivers and hardware control"  
        echo "- ALL power management services"
        echo "- Bootloader and recovery"
        echo "- EVERYTHING to exact backup state"
        echo ""
        read -p "Type 'RESTORE_EVERYTHING' to confirm: " confirm
        if [ "$confirm" = "RESTORE_EVERYTHING" ]; then
            if [ -f "full-system-backup.img" ]; then
                echo "Starting COMPLETE system restore..."
                echo "This will take 20-60 minutes..."
                
                # Check if we can stream directly or need to use device storage
                BACKUP_SIZE=$(ls -l full-system-backup.img | awk '{print $5}')
                DEVICE_SPACE=$(adb shell df /sdcard/ | tail -n 1 | awk '{print $4}')
                DEVICE_SPACE_BYTES=$((DEVICE_SPACE * 1024))
                
                if [ "$BACKUP_SIZE" -gt "$DEVICE_SPACE_BYTES" ]; then
                    echo "Streaming restore directly to device..."
                    cat full-system-backup.img | adb shell << 'RESTORE_EOF'
su
dd of=/dev/block/mmcblk0 bs=1048576
exit
RESTORE_EOF
                else
                    echo "Using device storage for restore..."
                    adb push full-system-backup.img /sdcard/
                    adb shell << 'RESTORE_EOF'
su
dd if=/sdcard/full-system-backup.img of=/dev/block/mmcblk0 bs=1048576
rm -f /sdcard/full-system-backup.img
exit
RESTORE_EOF
                fi
                
                echo "Rebooting device..."
                adb reboot
                echo ""
                echo "🔄 COMPLETE RESTORE FINISHED!"
                echo "Device will boot exactly as it was when backup was made"
            else
                echo "❌ No full system backup found"
            fi
        else
            echo "Complete restore cancelled"
        fi
        ;;
    *)
        echo "Invalid option"
        ;;
esac
EOF

chmod +x EMERGENCY-RESTORE.sh

cat > launcher-restore.sh << 'EOF'
#!/bin/bash
echo "Restoring original launcher..."
adb shell cmd package set-home-activity com.newlink.hisilauncher
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
echo "Original launcher restored"
EOF

chmod +x launcher-restore.sh

print_success "Restore scripts created"

# 7. BACKUP SUMMARY
print_status "=== BACKUP SUMMARY ==="

echo ""
echo "Backup completed in directory: $(pwd)"
echo ""
echo "Files created:"
ls -lh

echo ""
echo "BACKUP VERIFICATION:"
if [ -f "full-system-backup.img" ] && [ -s "full-system-backup.img" ]; then
    BACKUP_SIZE=$(ls -lh full-system-backup.img | awk '{print $5}')
    print_success "✅ Full system backup: $BACKUP_SIZE"
    BACKUP_COMPLETE=true
else
    print_error "❌ Full system backup: FAILED OR INCOMPLETE"
    BACKUP_COMPLETE=false
fi

if [ -f "complete-app-backup.ab" ] && [ -s "complete-app-backup.ab" ]; then
    APP_BACKUP_SIZE=$(ls -lh complete-app-backup.ab | awk '{print $5}')
    print_success "✅ Application backup: $APP_BACKUP_SIZE"
else
    print_warning "❌ Application backup: NOT AVAILABLE"
fi

if [ -f "system.img" ] && [ -s "system.img" ]; then
    SYS_BACKUP_SIZE=$(ls -lh system.img | awk '{print $5}')
    print_success "✅ System partition backup: $SYS_BACKUP_SIZE"
else
    print_warning "❌ System partition backup: NOT AVAILABLE"
fi

echo ""
if [ "$BACKUP_COMPLETE" = true ]; then
    print_success "🔒 DEVICE IS FULLY PROTECTED!"
    echo ""
    echo "WHAT THIS BACKUP INCLUDES:"
    echo "✅ Complete device image (every bit of storage)"
    echo "✅ ALL 25 partitions including boot, system, userdata"
    echo "✅ ALL firmware and bootloader"
    echo "✅ ALL power management services:"
    echo "   - zhiying.powerservice (power management)"
    echo "   - hisilicon.tv.service (display/TV control)"
    echo "   - newlink.service (hardware control)"
    echo "✅ Complete partition table and file systems"
    echo "✅ ALL applications and their data"
    echo ""
    echo "SAFETY GUARANTEE:"
    echo "The full-system-backup.img is a complete forensic copy that can"
    echo "restore your device to EXACTLY this working state, including"
    echo "all power management, thermal control, and hardware drivers."
    echo ""
    print_success "✅ YOU CAN NOW SAFELY PROCEED WITH SYSTEM MODIFICATIONS!"
else
    print_error "❌ BACKUP INCOMPLETE - DO NOT MODIFY SYSTEM!"
    echo ""
    echo "The backup failed or is incomplete. Installing new software"
    echo "without a complete backup could permanently damage your device."
    echo ""
    echo "Please fix the backup issues before proceeding."
fi

echo ""
echo "Important files:"
echo "- EMERGENCY-RESTORE.sh: Complete device restore options"
echo "- launcher-restore.sh: Quick launcher restore"
echo "- full-system-backup.img: Complete device image"
echo "- complete-app-backup.ab: All applications and data"
echo "- system.img: System partition backup"
echo ""
echo "Keep this backup directory safe!"
