#!/bin/bash

# Android Projector Complete Unlock Script
# For Newlink NL5H00X and similar locked Android projectors
# This script bypasses all security restrictions and installs full functionality

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
APK_DIR="./apks"
TEMP_DIR="/sdcard/unlock_temp"

# Function to print colored output
print_header() {
    echo -e "${CYAN}================================================"
    echo -e "   ANDROID PROJECTOR COMPLETE UNLOCK SCRIPT"
    echo -e "================================================${NC}"
    echo ""
}

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

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check ADB
    if ! command -v adb &> /dev/null; then
        print_error "ADB is not installed or not in PATH"
        exit 1
    fi
    
    # Check device connection
    if ! adb devices | grep -q "device$"; then
        print_error "No Android device connected or device not authorized"
        print_warning "Make sure your projector is connected and USB debugging is enabled"
        exit 1
    fi
    
    # Check root access
    print_status "Checking root access..."
    ROOT_CHECK=$(adb shell "su" << 'EOF'
whoami 2>/dev/null || echo "no_root"
exit
EOF
)
    
    if echo "$ROOT_CHECK" | grep -q "root"; then
        print_success "Root access confirmed"
    else
        print_error "Root access required but not available"
        print_warning "This script requires a rooted device"
        exit 1
    fi
    
    # Create APK directory if it doesn't exist
    mkdir -p "$APK_DIR"
    
    print_success "All prerequisites met"
}

# Function to verify backup exists
verify_backup_exists() {
    print_step "Verifying backup exists before proceeding..."
    
    # Look for backup directories
    BACKUP_FOUND=false
    
    # Check for backup directories
    for backup_dir in projector-backup-*; do
        if [ -d "$backup_dir" ] && [ -f "$backup_dir/full-system-backup.img" ]; then
            BACKUP_SIZE=$(ls -l "$backup_dir/full-system-backup.img" | awk '{print $5}')
            BACKUP_SIZE_GB=$((BACKUP_SIZE / 1024 / 1024 / 1024))
            print_success "Found backup: $backup_dir (${BACKUP_SIZE_GB}GB)"
            BACKUP_FOUND=true
            break
        fi
    done
    
    if [ "$BACKUP_FOUND" = false ]; then
        print_error "❌ NO COMPLETE BACKUP FOUND!"
        echo ""
        echo -e "${RED}CRITICAL ERROR:${NC} This script requires a complete device backup"
        echo "before proceeding with system modifications."
        echo ""
        echo "Please run the backup script first:"
        echo -e "${YELLOW}./MAKE_BACKUP.sh${NC}"
        echo ""
        echo "Then run this unlock script again."
        exit 1
    fi
    
    print_success "✅ Backup verified - safe to proceed"
}

# Function to verify backup exists
verify_backup_exists() {
    print_step "Verifying backup exists before proceeding..."
    
    # Look for backup directories
    BACKUP_FOUND=false
    
    # Check for backup directories
    for backup_dir in projector-backup-*; do
        if [ -d "$backup_dir" ] && [ -f "$backup_dir/full-system-backup.img" ]; then
            BACKUP_SIZE=$(ls -l "$backup_dir/full-system-backup.img" | awk '{print $5}')
            BACKUP_SIZE_GB=$((BACKUP_SIZE / 1024 / 1024 / 1024))
            print_success "Found backup: $backup_dir (${BACKUP_SIZE_GB}GB)"
            BACKUP_FOUND=true
            break
        fi
    done
    
    if [ "$BACKUP_FOUND" = false ]; then
        print_error "❌ NO COMPLETE BACKUP FOUND!"
        echo ""
        echo -e "${RED}CRITICAL ERROR:${NC} This script requires a complete device backup"
        echo "before proceeding with system modifications."
        echo ""
        echo "Please run the backup script first:"
        echo -e "${YELLOW}./MAKE_BACKUP.sh${NC}"
        echo ""
        echo "Then run this unlock script again."
        exit 1
    fi
    
    print_success "✅ Backup verified - safe to proceed"
}

# Function to unlock developer options and hidden settings
unlock_developer_options() {
    print_step "Unlocking developer options and hidden settings..."
    
    # Enable developer options
    adb shell settings put global development_settings_enabled 1
    adb shell settings put global adb_enabled 1
    adb shell settings put global stay_on_while_plugged_in 3
    
    # Enable unknown sources (multiple methods)
    adb shell settings put secure install_non_market_apps 1
    adb shell settings put global install_non_market_apps 1
    
    # Disable package verification
    adb shell settings put global package_verifier_enable 0
    adb shell settings put global verifier_verify_adb_installs 0
    
    # Enable USB debugging options
    adb shell settings put global adb_enabled 1
    adb shell settings put global development_settings_enabled 1
    
    print_success "Developer options unlocked"
}

# Function to disable security restrictions
disable_security_restrictions() {
    print_step "Disabling security restrictions..."
    
    # Create temporary script on device
    adb shell "cat > /sdcard/disable_security.sh << 'SCRIPT_EOF'
#!/system/bin/sh

# Disable SELinux enforcement (if possible)
setenforce 0 2>/dev/null || echo 'SELinux enforcement unchanged'

# Remount system as writable
mount -o remount,rw /system 2>/dev/null || echo 'System remount failed'

# Modify package manager restrictions
if [ -f /system/etc/permissions/platform.xml ]; then
    cp /system/etc/permissions/platform.xml /system/etc/permissions/platform.xml.backup
    # Add installation permissions
    sed -i 's/<\/permissions>/<permission name=\"android.permission.INSTALL_PACKAGES\" \/>\n<\/permissions>/' /system/etc/permissions/platform.xml 2>/dev/null || echo 'Permissions modification failed'
fi

# Main execution function
main() {
    print_header
    
    echo -e "${YELLOW}⚠️  WARNING: This script will make significant system modifications${NC}"
    echo "Make sure you have completed a backup using ./MAKE_BACKUP.sh first!"
    echo ""
    read -p "Continue with unlock? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Unlock cancelled"
        exit 0
    fi
    
    check_prerequisites
    verify_backup_exists
    
    print_status "Starting unlock process..."
    
    unlock_developer_options
    disable_security_restrictions
    prepare_system_directories
    install_essential_apks
    install_custom_launcher
    enable_hidden_features
    create_unlock_tools
    
    print_success "🎉 PROJECTOR UNLOCK COMPLETED!"
    echo ""
    echo -e "${GREEN}Your projector is now fully unlocked with:${NC}"
    echo "✅ Custom launcher support"
    echo "✅ APK installation capability"
    echo "✅ Hidden features access"
    echo "✅ Developer options enabled"
    echo "✅ Security restrictions bypassed"
    echo ""
    echo -e "${YELLOW}Restart your projector to ensure all changes take effect${NC}"
    echo ""
    echo "Use ./TOOLS.sh to access additional hidden features"
}

# Run the script
main "$@"