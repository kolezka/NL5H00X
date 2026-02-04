#!/bin/bash

################################################################################
#                                                                              #
#                         !! WORK IN PROGRESS !!                               #
#                                                                              #
#  This script is under active development. Many functions are stubbed out.   #
#  DO NOT use on devices you care about until this notice is removed.         #
#                                                                              #
################################################################################

# System Unlock Script for Android Projectors
# Bypasses security restrictions and enables full functionality

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================
APK_DIR="$SCRIPT_DIR/../apks"

# ============================================================================
# IMPLEMENTED FUNCTIONS
# ============================================================================

unlock_developer_options() {
    print_step "Unlocking developer options..."

    local settings=(
        "global development_settings_enabled 1"
        "global adb_enabled 1"
        "global stay_on_while_plugged_in 3"
        "secure install_non_market_apps 1"
        "global install_non_market_apps 1"
        "global package_verifier_enable 0"
        "global verifier_verify_adb_installs 0"
    )

    for setting in "${settings[@]}"; do
        adb shell settings put $setting 2>/dev/null || true
    done

    print_success "Developer options unlocked"
}

disable_security_restrictions() {
    print_step "Disabling security restrictions..."

    # Try to disable SELinux (may fail without full root)
    adb shell "su -c 'setenforce 0'" 2>/dev/null || true

    # Try to remount system as writable
    adb shell "su -c 'mount -o remount,rw /system'" 2>/dev/null || true

    print_success "Security restrictions modified (where possible)"
}

# ============================================================================
# STUB FUNCTIONS - Not yet implemented
# ============================================================================

prepare_system_directories() {
    print_step "Preparing system directories..."
    print_warning "NOT YET IMPLEMENTED"
    # TODO: Create /system/app directories for custom apps
    # TODO: Set proper ownership and permissions
    return 1
}

install_essential_apks() {
    print_step "Installing essential APKs..."
    print_warning "NOT YET IMPLEMENTED"
    # TODO: Install file manager, settings shortcuts
    # TODO: Use pm install or copy to /system/app
    return 1
}

install_custom_launcher() {
    print_step "Installing custom launcher..."
    print_warning "NOT YET IMPLEMENTED"

    local nova_apk="$APK_DIR/nova-launcher-7.0.57.apk"
    if [[ -f "$nova_apk" ]]; then
        print_status "Found: $nova_apk"
        # TODO: Install via pm install or /system/app
        # TODO: Set as default home activity
    else
        print_error "Nova Launcher APK not found"
    fi

    return 1
}

enable_hidden_features() {
    print_step "Enabling hidden features..."
    print_warning "NOT YET IMPLEMENTED"
    # TODO: Enable additional settings
    # TODO: Unlock manufacturer-hidden options
    return 1
}

create_unlock_tools() {
    print_step "Creating unlock tools..."
    print_warning "NOT YET IMPLEMENTED"
    # TODO: Create helper scripts on device
    # TODO: Set up boot-time unlock persistence
    return 1
}

# ============================================================================
# MAIN
# ============================================================================

show_warning() {
    echo
    echo -e "${YELLOW}WARNING: This script will make system modifications${NC}"
    echo
    echo "Before continuing, ensure you have:"
    echo "  1. Created a complete backup with ./MAKE_BACKUP.sh"
    echo "  2. Verified the backup is complete (~7GB)"
    echo "  3. Tested the restore script works"
    echo
    echo -e "${RED}Proceeding without backup may brick your device!${NC}"
    echo
}

main() {
    print_header "PROJECTOR UNLOCK"

    show_warning

    if ! confirm "Continue with unlock?"; then
        echo "Cancelled"
        exit 0
    fi

    # Check requirements
    require_device true
    require_backup

    print_status "Starting unlock process..."
    echo

    # Implemented steps
    unlock_developer_options
    disable_security_restrictions

    # Unimplemented steps (will show warnings)
    prepare_system_directories || true
    install_essential_apks || true
    install_custom_launcher || true
    enable_hidden_features || true
    create_unlock_tools || true

    echo
    print_section "RESULTS"

    echo "Completed:"
    echo "  - Developer options unlocked"
    echo "  - Security restrictions modified"
    echo
    echo "Not yet implemented:"
    echo "  - System directory preparation"
    echo "  - APK installation"
    echo "  - Custom launcher installation"
    echo "  - Hidden features"
    echo "  - Persistent unlock tools"
    echo
    print_warning "Restart your projector for changes to take effect"
    echo
    echo "Use ./TOOLS.sh to access hidden features manually"
}

main "$@"
