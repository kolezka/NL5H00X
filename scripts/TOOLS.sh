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

STOCK_LAUNCHER_PKG="com.newlink.hisilauncher"

# Everything above only opens screens. This one changes which launcher the
# device boots into, so it is routed through reset_default_launcher rather than
# fired blindly -- see the handler for why.
declare -a MENU_LAUNCHER=(
    "am start -a android.intent.action.MAIN -c android.intent.category.HOME|Choose Launcher"
    "@reset-launcher|Reset to Default Launcher  (changes the home screen)"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

run_adb_command() {
    local cmd="$1" desc="$2" out rc

    echo
    print_status "$desc"
    echo -e "${YELLOW}> adb shell $cmd${NC}"
    echo

    out=$(adb shell "$cmd" 2>&1); rc=$?
    [[ -n "$out" ]] && echo "$out"

    # `am start` prints "Error: Activity not started" and still exits 0, so the
    # exit code alone reported "Done" for activities that never opened.
    if [[ "$rc" -ne 0 ]] || echo "$out" | grep -qiE '^Error|Exception|not found|does not exist'; then
        print_warning "That did not work -- the app or activity is probably not on this device"
        return 1
    fi
    print_success "Done"
    return 0
}

# The stock launcher cannot be made the home screen while it is disabled, which
# is exactly the state UNLOCK.sh leaves it in. Without this check the menu
# entry appears to do nothing at all.
reset_default_launcher() {
    echo
    print_status "Reset to Default Launcher"
    if adb shell "pm list packages -d" 2>/dev/null | grep -q "$STOCK_LAUNCHER_PKG"; then
        print_warning "The stock launcher is currently disabled, so it cannot be set as home."
        echo
        echo "  It was disabled by the unlock. To undo that properly:"
        echo "      ./scripts/UNLOCK.sh --revert"
        echo "  which re-enables it first and then verifies the home screen."
        return 1
    fi
    # Not .MainActivity. That is the activity you see, but the one carrying the
    # HOME filter is .WizardAciticity (their spelling), so set-home-activity
    # against .MainActivity is rejected. Ask the device rather than guess.
    local comp
    comp=$(adb shell "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME" 2>/dev/null \
           | tr -d '\r' | grep -oE "$STOCK_LAUNCHER_PKG/[A-Za-z0-9_.]+" | head -1)
    if [[ -z "$comp" ]]; then
        print_warning "The stock launcher registers no home activity on this device"
        return 1
    fi
    run_adb_command "cmd package set-home-activity $comp" "Reset to Default Launcher"
}

# These read an array whose name is in a variable. `local -n` would be the
# obvious way and it is what this used to do -- but namerefs need bash 4.3 and
# macOS ships 3.2, so `./scripts/TOOLS.sh` died on line one of the menu for
# every Mac user. eval-based indirection is uglier and works everywhere.
# The array names are literals from the loop below, never user input.
section_items() { eval "printf '%s\n' \"\${$1[@]}\""; }

show_menu_section() {
    local title="$1" name="$2" start_num="$3" entry desc i

    echo -e "${GREEN}${title}:${NC}"
    i=$start_num
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        desc="${entry#*|}"
        printf "  %2d. %s\n" "$i" "$desc"
        i=$((i + 1))
    done < <(section_items "$name")
    echo
}

get_menu_entry() {
    local choice="$1" idx=1 section entry

    for section in MENU_SYSTEM MENU_PROJECTOR MENU_MEDIA MENU_LAUNCHER; do
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            if [[ "$idx" -eq "$choice" ]]; then
                echo "$entry"
                return 0
            fi
            idx=$((idx + 1))
        done < <(section_items "$section")
    done
    return 1
}

count_menu_items() {
    local count=0 section n
    for section in MENU_SYSTEM MENU_PROJECTOR MENU_MEDIA MENU_LAUNCHER; do
        n=$(section_items "$section" | grep -c .)
        count=$((count + n))
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
        show_menu_section "SYSTEM SETTINGS" MENU_SYSTEM "$num"
        num=$((num + ${#MENU_SYSTEM[@]}))

        show_menu_section "PROJECTOR" MENU_PROJECTOR "$num"
        num=$((num + ${#MENU_PROJECTOR[@]}))

        show_menu_section "MEDIA & FILES" MENU_MEDIA "$num"
        num=$((num + ${#MENU_MEDIA[@]}))

        show_menu_section "LAUNCHER" MENU_LAUNCHER "$num"
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
                    if [[ "$cmd" == "@reset-launcher" ]]; then
                        reset_default_launcher || true
                    else
                        run_adb_command "$cmd" "$desc" || true
                    fi
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
