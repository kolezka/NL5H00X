#!/bin/bash
# Projector Hidden Features Access Tool
# Access hidden settings and features on locked Android projectors

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============================================================================
# MENU DEFINITIONS
# Each entry: "command|description"
# ============================================================================

declare -a MENU_SYSTEM=(
    "am start -n com.android.tv.settings/.MainSettings|Android TV Settings"
    "am start -a android.settings.SETTINGS|Standard Settings"
    "am start -a android.settings.WIFI_SETTINGS|WiFi Settings"
    "am start -a android.settings.BLUETOOTH_SETTINGS|Bluetooth Settings"
    "am start -a android.settings.DISPLAY_SETTINGS|Display Settings"
    "am start -a android.settings.SECURITY_SETTINGS|Security Settings"
    "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS|Developer Options"
    "am start -a android.settings.MANAGE_APPLICATIONS_SETTINGS|App Management"
)

declare -a MENU_PROJECTOR=(
    "am start -n com.hisilicon.tvsetting/.MainActivity|Hisilicon TV Settings"
    "am start -n com.newlink.hisetting/.MainActivity|Newlink Settings"
    "am start -n com.hisilicon.tv.menu/.MainActivity|TV Menu"
    "am start -n com.android.tv.quicksettings/.MainActivity|Quick Settings"
    "am start -n com.hisilicon.tvinput.external/.MainActivity|External Input"
)

declare -a MENU_MEDIA=(
    "monkey -p com.newlink.filemanager -c android.intent.category.LAUNCHER 1|File Manager"
    "am start -n com.hisilicon.higallery/.MainActivity|Gallery"
    "am start -n com.hisilicon.android.music/.MainActivity|Music Player"
    "am start -n com.hisilicon.android.videoplayer/.MainActivity|Video Player"
)

declare -a MENU_LAUNCHER=(
    "am start -a android.intent.action.MAIN -c android.intent.category.HOME|Choose Launcher"
    "cmd package set-home-activity com.newlink.hisilauncher|Reset to Default Launcher"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

run_adb_command() {
    local cmd="$1"
    local desc="$2"

    echo
    print_status "$desc"
    echo -e "${YELLOW}> adb shell $cmd${NC}"
    echo

    if adb shell "$cmd" 2>&1; then
        print_success "Done"
    else
        print_warning "Command may have failed or app not available"
    fi
}

show_menu_section() {
    local title="$1"
    shift
    local -n items=$1
    local start_num="$2"

    echo -e "${GREEN}${title}:${NC}"
    local i=$start_num
    for entry in "${items[@]}"; do
        local desc="${entry#*|}"
        printf "  %2d. %s\n" "$i" "$desc"
        ((i++))
    done
    echo
}

get_menu_entry() {
    local choice="$1"
    local idx=1

    for section in MENU_SYSTEM MENU_PROJECTOR MENU_MEDIA MENU_LAUNCHER; do
        local -n arr=$section
        for entry in "${arr[@]}"; do
            if [[ "$idx" -eq "$choice" ]]; then
                echo "$entry"
                return 0
            fi
            ((idx++))
        done
    done
    return 1
}

count_menu_items() {
    local count=0
    for section in MENU_SYSTEM MENU_PROJECTOR MENU_MEDIA MENU_LAUNCHER; do
        local -n arr=$section
        count=$((count + ${#arr[@]}))
    done
    echo "$count"
}

show_system_info() {
    echo
    print_status "System Information"
    echo

    echo -e "${CYAN}Device:${NC}"
    adb shell getprop | grep -E "ro.product.model|ro.product.manufacturer|ro.build.version.release" | \
        sed 's/\[ro\.product\.\([^]]*\)\]: \[\(.*\)\]/  \1: \2/' | \
        sed 's/\[ro\.build\.version\.release\]: \[\(.*\)\]/  Android: \1/'
    echo

    echo -e "${CYAN}Storage:${NC}"
    adb shell df -h /sdcard/ 2>/dev/null | tail -1 | awk '{print "  Total: "$2"  Used: "$3"  Free: "$4}'
    echo

    echo -e "${CYAN}Memory:${NC}"
    adb shell cat /proc/meminfo 2>/dev/null | head -3 | sed 's/^/  /'
}

show_hardware_info() {
    echo
    print_status "Hardware Information"
    echo

    echo -e "${CYAN}CPU:${NC}"
    adb shell cat /proc/cpuinfo 2>/dev/null | grep -E "^Hardware|^processor" | head -5 | sed 's/^/  /'
    echo

    echo -e "${CYAN}Display:${NC}"
    adb shell dumpsys display 2>/dev/null | grep -E "mDisplayId=0|mCurrentDisplayRect" | head -2 | sed 's/^/  /'
}

list_launcher_activities() {
    echo
    print_status "Available Launcher Activities"
    echo
    adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null | head -30
}

show_service_status() {
    echo
    print_status "Critical Services Status"
    echo

    local services=("zhiying.powerservice" "hisilicon.tv.service" "newlink.service")
    for svc in "${services[@]}"; do
        if adb shell ps 2>/dev/null | grep -q "$svc"; then
            echo -e "  ${GREEN}[RUNNING]${NC} $svc"
        else
            echo -e "  ${YELLOW}[NOT FOUND]${NC} $svc"
        fi
    done
}

main_menu() {
    local total
    total=$(count_menu_items)

    while true; do
        clear
        print_header "PROJECTOR ACCESS TOOLKIT"

        local num=1
        show_menu_section "SYSTEM SETTINGS" MENU_SYSTEM $num
        num=$((num + ${#MENU_SYSTEM[@]}))

        show_menu_section "PROJECTOR" MENU_PROJECTOR $num
        num=$((num + ${#MENU_PROJECTOR[@]}))

        show_menu_section "MEDIA & FILES" MENU_MEDIA $num
        num=$((num + ${#MENU_MEDIA[@]}))

        show_menu_section "LAUNCHER" MENU_LAUNCHER $num
        num=$((num + ${#MENU_LAUNCHER[@]}))

        echo -e "${YELLOW}DIAGNOSTICS:${NC}"
        echo "  i.  System Information"
        echo "  h.  Hardware Information"
        echo "  l.  List Launcher Activities"
        echo "  s.  Service Status"
        echo
        echo -e "${RED}  q.  Quit${NC}"
        echo

        read -r -p "Select option: " choice

        case "$choice" in
            [1-9]|[1-9][0-9])
                if entry=$(get_menu_entry "$choice"); then
                    local cmd="${entry%%|*}"
                    local desc="${entry#*|}"
                    run_adb_command "$cmd" "$desc"
                    pause
                else
                    print_error "Invalid option"
                    pause
                fi
                ;;
            i|I)
                show_system_info
                pause
                ;;
            h|H)
                show_hardware_info
                pause
                ;;
            l|L)
                list_launcher_activities
                pause
                ;;
            s|S)
                show_service_status
                pause
                ;;
            q|Q|0)
                echo
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    require_device false
    main_menu
}

main "$@"
