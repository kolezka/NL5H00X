#!/bin/bash
# Projector Hidden Features Access Tool
# Access hidden settings and features on locked Android projectors

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
# The ROOT section reuses the device paths and the allow-list helpers that
# ROOT.sh installs with, rather than restating them. Sourcing this file only
# defines functions and paths; the steps themselves run nothing here.
source "$SCRIPT_DIR/lib/root.sh"

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

# What the shell root this projector already has is actually good for. Every
# entry here goes through su, so root is probed the first time one is used --
# not at startup, because the rest of the menu needs none.
declare -a MENU_ROOT=(
    "@root-status|Root status  (su, sud daemon, allow-list)"
    "@root-apps|Apps that are allowed to use root"
    "@root-allow|Give an app root  (adds it to the allow-list)"
    "@root-deny|Take root away from an app"
    "@root-command|Run one command as root"
    "@root-pull|Copy a root-only file off the device"
    "@root-adb-wifi|ADB over Wi-Fi, on or off"
    "@root-freeze|Freeze or unfreeze an app  (changes what runs at boot)"
)

# Sections, in menu order. get_menu_entry and count_menu_items both read this,
# so a new section is numbered and reachable from one place.
MENU_SECTIONS=(MENU_SYSTEM MENU_PROJECTOR MENU_MEDIA MENU_LAUNCHER MENU_ROOT)

# Packages this menu will not freeze. wtprovision owns the home intent on this
# firmware and freezing it stops the projector booting -- see the README. The
# others take the screen or Settings down with them.
ROOT_PROTECTED_PKGS=(
    com.newlink.wtprovision
    com.newlink.hisilauncher
    com.android.tv.settings
    com.android.systemui
    android
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

    for section in "${MENU_SECTIONS[@]}"; do
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
    for section in "${MENU_SECTIONS[@]}"; do
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

# ============================================================================
# ROOT ACTIONS
#
# The shell on this projector is already root: `su 0 id` returns uid 0. These
# entries are the things that need it. Apps are a separate problem and go
# through the sud daemon -- see root/README.md.
# ============================================================================

# Root is probed on first use, not at startup. adb_root_exec refuses to run
# anything until SU_MODE says which su form this device accepts.
ensure_root() {
    [[ -n "${SU_MODE:-}" ]] && return 0
    print_status "Checking root access..."
    if check_root_access; then
        print_success "Root confirmed (su form: $SU_MODE)"
        return 0
    fi
    print_error "su on this device does not return uid 0"
    echo "  Everything in ROOT needs it. Check that the projector is connected"
    echo "  and authorised over adb, then try again."
    return 1
}

# Root command output as text, with the device's CR endings stripped. Failure
# is the caller's to handle: `out=$(root_out "...") || out=""`.
root_out() {
    adb_root_exec "$1" 2>/dev/null | tr -d '\r'
}

root_valid_pkg() {
    local pkg="$1"
    if [[ "$pkg" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]]; then
        return 0
    fi
    print_error "'$pkg' is not a package name (expected something like com.example.app)"
    return 1
}

root_pkg_installed() {
    adb shell "pm list packages" 2>/dev/null | tr -d '\r' | grep -qx "package:$1"
}

root_allow_list_summary() {
    local list n
    list=$(allow_list_read 2>/dev/null) || {
        echo "not created yet -- run ./scripts/ROOT.sh --apply-all"
        return 0
    }
    n=$(printf '%s\n' "$list" | grep -c '[^[:space:]]' || true)
    if [[ "${n:-0}" -eq 0 ]]; then
        echo "empty -- no app can use root (it fails closed)"
    else
        echo "$n package(s)"
    fi
}

root_show_status() {
    echo
    print_status "Root status"
    echo

    printf "  %-12s %s\n" "su" "uid 0, '$SU_MODE' form"

    local state
    device_file_exists "$SUD_BIN_PATH" && state="installed at $SUD_BIN_PATH" \
        || state="missing -- run ./scripts/ROOT.sh --apply-all"
    printf "  %-12s %s\n" "sud binary" "$state"

    device_file_exists "$SUD_RC_PATH" && state="installed at $SUD_RC_PATH" \
        || state="missing -- apps get no root after a reboot"
    printf "  %-12s %s\n" "sud service" "$state"

    sud_running && state="running" || state="not running -- apps cannot get root until it is"
    printf "  %-12s %s\n" "sud daemon" "$state"

    printf "  %-12s %s\n" "allow-list" "$(root_allow_list_summary)"

    local selinux mounts sysmode
    selinux=$(root_out "getenforce") || selinux=""
    printf "  %-12s %s\n" "SELinux" "${selinux:-unknown}"

    # system-as-root: /system is a directory on /, so the line to read is /.
    mounts=$(root_out "cat /proc/mounts") || mounts=""
    sysmode=$(awk '$2 == "/" {print $4}' <<<"$mounts" | cut -d, -f1 | head -1)
    printf "  %-12s %s\n" "/system" "${sysmode:-unknown}  (it lives on / here)"

    echo
    echo "  This menu runs as root through su. Apps never do -- they ask sud."
}

root_show_allow_list() {
    echo
    print_status "Apps that are allowed to use root"
    echo
    local list
    if ! list=$(allow_list_read 2>/dev/null); then
        print_warning "No allow-list on the device yet"
        echo "  ./scripts/ROOT.sh --apply-all creates it. Until then sud refuses everyone."
        return 0
    fi
    list=$(printf '%s\n' "$list" | grep '[^[:space:]]' || true)
    if [[ -z "$list" ]]; then
        echo "  (empty -- sud refuses every app, which is the safe default)"
        return 0
    fi
    printf '    %s\n' $list
    echo
    echo "  sud reads this file on every request, so a change is live at once."
}

root_grant() {
    echo
    print_status "Give an app root"
    echo "  This only adds the package to sud's allow-list. The app still has to"
    echo "  ask sud for root itself -- see root/README.md."
    echo
    local pkg
    read -r -p "Package name (Enter to cancel): " pkg
    [[ -z "$pkg" ]] && { print_status "Cancelled"; return 0; }
    root_valid_pkg "$pkg" || return 1

    if ! root_pkg_installed "$pkg"; then
        print_warning "$pkg is not installed here. The entry is harmless, but it does nothing."
    fi
    if ! sud_running; then
        print_warning "sud is not running, so nothing reads this list yet. Reboot after ROOT.sh."
    fi
    print_warning "An allowed app can do everything root can: read every app's data,"
    print_warning "write /system, and stop the projector booting. Allow only your own apps."
    confirm "Allow $pkg to use root?" || { print_status "Cancelled"; return 0; }

    allow_list_apply >/dev/null 2>&1 || true
    if ! allow_list_add "$pkg"; then
        print_error "Could not write the allow-list"
        return 1
    fi
    # Read it back off the device, the same way every other step in this
    # toolkit does -- a write that reported success is not a write that landed.
    if root_out "cat $SU_ALLOW_FILE" | grep -qx "$pkg"; then
        print_success "$pkg is on the allow-list"
    else
        print_error "$pkg is not in $SU_ALLOW_FILE after writing it"
        return 1
    fi
    root_show_allow_list
}

root_revoke() {
    echo
    print_status "Take root away from an app"
    root_show_allow_list
    echo
    local pkg
    read -r -p "Package name (Enter to cancel): " pkg
    [[ -z "$pkg" ]] && { print_status "Cancelled"; return 0; }
    root_valid_pkg "$pkg" || return 1

    if ! allow_list_remove "$pkg"; then
        print_error "Could not write the allow-list"
        return 1
    fi
    if root_out "cat $SU_ALLOW_FILE" | grep -qx "$pkg"; then
        print_error "$pkg is still in $SU_ALLOW_FILE"
        return 1
    fi
    print_success "$pkg can no longer use root"
    echo "  A process that already holds root keeps it until it exits."
}

root_run_command() {
    echo
    print_status "Run one command as root"
    echo "  It runs through su on the device, as uid 0."
    echo
    local cmd out rc
    read -r -p "Command (Enter to cancel): " cmd
    [[ -z "$cmd" ]] && { print_status "Cancelled"; return 0; }
    # adb_root_exec wraps the command in single quotes on the far side, so a
    # quote of your own truncates it into a different command.
    if [[ "$cmd" == *"'"* ]]; then
        print_error "Single quotes cannot be passed through su here -- rewrite without them"
        return 1
    fi

    echo
    echo -e "${YELLOW}> su 0 $cmd${NC}"
    confirm "Run it?" || { print_status "Cancelled"; return 0; }
    echo
    rc=0
    out=$(adb_root_exec "$cmd") || rc=$?
    [[ -n "$out" ]] && echo "$out"
    if [[ "$rc" -eq 0 ]]; then
        print_success "exit 0"
    else
        print_warning "exit $rc"
    fi
    return 0
}

root_pull_file() {
    echo
    print_status "Copy a root-only file off the device"
    echo "  /data/system/packages.list, an app's database, a build.prop: none of"
    echo "  them can be read without root."
    echo
    local path dest rh algo digest lh
    read -r -p "Device path [/data/system/packages.list]: " path
    path="${path:-/data/system/packages.list}"
    if [[ "$path" != /* || "$path" == *"'"* || "$path" == *" "* ]]; then
        print_error "Give one absolute path, with no spaces or quotes"
        return 1
    fi

    dest="./$(basename "$path").$(date +%Y%m%d_%H%M%S)"
    # exec-out, not a captured shell: this has to survive binary content.
    adb_root_stream "cat $path" > "$dest" || true
    if [[ ! -s "$dest" ]]; then
        rm -f "$dest"
        print_error "Nothing came back -- $path is missing, empty, or unreadable"
        return 1
    fi

    # Same rule as every other transfer here: the copy is only a copy once it
    # hashes the same as the source.
    if rh=$(remote_hash "$path"); then
        algo="${rh%%:*}"; digest="${rh#*:}"
        lh=$(local_hash "$dest" "$algo")
        if [[ "$lh" != "$digest" ]]; then
            print_error "$dest does not match the device ($algo) -- deleting it"
            rm -f "$dest"
            return 1
        fi
        print_success "$dest  $(human_size "$(local_size "$dest")"), $algo matches the device"
    else
        print_warning "Saved $dest, but the device would not hash $path -- unverified"
    fi
}

# adbd has to be restarted for the port to take, and that drops the current
# connection for a moment. Root is re-probed afterwards, because a lost adb
# channel must not read as "the property did not change".
root_restart_adbd() {
    adb_root_exec "stop adbd" >/dev/null 2>&1 || true
    adb_root_exec "start adbd" >/dev/null 2>&1 || true
    sleep 2
    SU_MODE=""
    if ! check_root_access; then
        print_error "adb is not answering as root after restarting adbd"
        print_warning "Unplug and replug the USB cable, or reboot the projector -- the"
        print_warning "port is not persistent, so a reboot clears it either way."
        return 1
    fi
    return 0
}

root_adb_wifi() {
    echo
    print_status "ADB over Wi-Fi"
    echo "  setprop and start/stop are root-only on this device: as shell they"
    echo "  fail with 'must be root'."
    echo

    local port new
    port=$(root_out "getprop service.adb.tcp.port") || port=""
    port="${port//[[:space:]]/}"

    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -gt 0 ]]; then
        echo "  On now, port $port"
        confirm "Turn it off?" || { print_status "Cancelled"; return 0; }
        adb_root_exec "setprop service.adb.tcp.port -1" >/dev/null 2>&1 || true
        root_restart_adbd || return 1
        new=$(root_out "getprop service.adb.tcp.port") || new=""
        new="${new//[[:space:]]/}"
        if [[ "$new" =~ ^[0-9]+$ ]] && [[ "$new" -gt 0 ]]; then
            print_error "The port is still $new"
            return 1
        fi
        print_success "ADB over Wi-Fi is off"
        return 0
    fi

    echo "  Off now"
    print_warning "Restarting adbd drops the current adb connection for a moment."
    print_warning "The property is not persistent: a reboot turns this back off."
    confirm "Turn it on, port 5555?" || { print_status "Cancelled"; return 0; }
    adb_root_exec "setprop service.adb.tcp.port 5555" >/dev/null 2>&1 || true
    root_restart_adbd || return 1
    new=$(root_out "getprop service.adb.tcp.port") || new=""
    new="${new//[[:space:]]/}"
    if [[ "$new" != "5555" ]]; then
        print_error "service.adb.tcp.port reads '$new', not 5555"
        return 1
    fi
    print_success "ADB over Wi-Fi is on, port 5555"

    local ip
    ip=$(root_out "getprop dhcp.wlan0.ipaddress") || ip=""
    ip="${ip//[[:space:]]/}"
    if [[ -n "$ip" ]]; then
        echo "  Connect with:  adb connect $ip:5555"
    else
        echo "  Find the projector's IP in Settings, then:  adb connect <ip>:5555"
    fi
}

root_freeze() {
    echo
    print_status "Freeze or unfreeze an app"
    echo "  A frozen app stays installed and stops running, across reboots. This is"
    echo "  how vendor apps and updaters are kept quiet without deleting anything."
    echo

    local frozen pkg p
    frozen=$(root_out "pm list packages -d") || frozen=""
    frozen=$(printf '%s\n' "$frozen" | sed 's/^package://' | grep '[^[:space:]]' || true)
    if [[ -n "$frozen" ]]; then
        echo "  Frozen now:"
        printf '    %s\n' $frozen
    else
        echo "  Nothing is frozen."
    fi
    echo

    read -r -p "Package name (Enter to cancel): " pkg
    [[ -z "$pkg" ]] && { print_status "Cancelled"; return 0; }
    root_valid_pkg "$pkg" || return 1

    for p in "${ROOT_PROTECTED_PKGS[@]}"; do
        if [[ "$pkg" == "$p" ]]; then
            print_error "$pkg is part of the boot path -- refusing"
            echo "  Freezing com.newlink.wtprovision stops this projector booting and takes"
            echo "  adb, Wi-Fi and the screen with it. See the README, 'the wtprovision brick'."
            return 1
        fi
    done

    if printf '%s\n' "$frozen" | grep -qx "$pkg"; then
        confirm "Unfreeze $pkg?" || { print_status "Cancelled"; return 0; }
        adb_root_exec "pm enable $pkg" >/dev/null 2>&1 || true
        if root_out "pm list packages -d" | sed 's/^package://' | grep -qx "$pkg"; then
            print_error "$pkg is still frozen"
            return 1
        fi
        print_success "$pkg runs again"
        return 0
    fi

    if ! root_pkg_installed "$pkg"; then
        print_error "$pkg is not installed on this device"
        return 1
    fi
    # A home screen is the one thing you cannot freeze safely, and the list of
    # them is on the device rather than in this script.
    if adb shell "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME" 2>/dev/null \
        | tr -d '\r' | grep -q "^$pkg/"; then
        print_warning "$pkg is a home screen. Freeze it and the projector may boot to no launcher."
    fi

    confirm "Freeze $pkg?" || { print_status "Cancelled"; return 0; }
    adb_root_exec "pm disable-user --user 0 $pkg" >/dev/null 2>&1 || true
    if ! root_out "pm list packages -d" | sed 's/^package://' | grep -qx "$pkg"; then
        print_error "$pkg is not frozen -- the device refused it"
        return 1
    fi
    print_success "$pkg is frozen. Unfreeze it from this same entry."
}

root_action() {
    local action="$1"
    ensure_root || return 1
    case "$action" in
        @root-status)   root_show_status ;;
        @root-apps)     root_show_allow_list ;;
        @root-allow)    root_grant ;;
        @root-deny)     root_revoke ;;
        @root-command)  root_run_command ;;
        @root-pull)     root_pull_file ;;
        @root-adb-wifi) root_adb_wifi ;;
        @root-freeze)   root_freeze ;;
        *) print_error "Unknown root action: $action"; return 1 ;;
    esac
}

main_menu() {
    local total
    total=$(count_menu_items)

    while true; do
        # Not `clear`: it needs TERM, and with set -e a missing TERM ends the
        # script on its first menu draw. PROJECTOR.sh writes the same escape.
        printf '\033[2J\033[H'
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

        show_menu_section "ROOT  (needs root)" MENU_ROOT "$num"
        num=$((num + ${#MENU_ROOT[@]}))

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
                    case "$cmd" in
                        @reset-launcher) reset_default_launcher || true ;;
                        @root-*)         root_action "$cmd" || true ;;
                        *)               run_adb_command "$cmd" "$desc" || true ;;
                    esac
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
