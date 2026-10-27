#!/bin/bash
# Unlock the launcher on a Newlink NL5H00X Android projector.
#
# Written to be run by people who did not write it. It refuses to touch a
# device it does not recognise, refuses to run without a verified backup, shows
# what it will change before changing it, checks that each change actually
# took, and can put everything back.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/steps.sh"

APK_DIR="${APK_DIR:-$SCRIPT_DIR/../apks}"
source "$SCRIPT_DIR/lib/unlock.sh"

# Only these devices. The unlock targets a specific stock launcher and /system
# layout; on anything else it would be guesswork with someone else's hardware.
SUPPORTED_DEVICES=(NL5H00X NL5H00X_TP)

ASSUME_YES=0
MODE=menu

# A step that needs a reboot is saved here, so a run cut short by the reboot
# can pick up where it stopped. Lives in the working directory.
RESUME_MARKER=".unlock-resume"
RESUME_FILE="$RESUME_MARKER"
STEP_NAME_WIDTH=18
UNSUPPORTED_DEVICE_TEXT="This tool is written for the Newlink NL5H00X projector and makes
changes specific to its stock launcher and /system layout.
Running it elsewhere could leave you without a home screen."
UNLOCK_BOOT_TIMEOUT="${UNLOCK_BOOT_TIMEOUT:-180}"

# ---------------------------------------------------------------------------
# state reporting
# ---------------------------------------------------------------------------
# The package wtprovision's cache names, when wtprovision intercepts HOME and
# the cache holds a pair; empty otherwise.
wtprov_cache_pkg() {
    local icept pair
    icept=$(home_interceptor)
    [[ -n "$icept" ]] && is_wtprov "$icept" || return 0
    pair=$(wtprov_cache_read)
    [[ -n "$pair" ]] && echo "${pair%% *}"
    return 0
}

show_status() {
    steps_show_status ${UNLOCK_STEPS[@]+"${UNLOCK_STEPS[@]}"}
    local cached focus
    printf "  home screen now: %s\n" "$(home_owner)"
    # The cache is only read when wtprovision starts, so the two can disagree.
    # No HOME press here: --status changes nothing, so only a home screen
    # already in front counts, not whatever app is open.
    cached=$(wtprov_cache_pkg)
    if [[ -n "$cached" ]]; then
        focus=$(focused_package)
        if [[ -n "$focus" && "$focus" != "$cached" && -n "$(home_component_of "$focus")" ]]; then
            print_warning "HOME shows $focus, but wtprovision's cache names $cached; --apply-all restarts wtprovision"
        fi
    fi
    echo
}

# All steps applied: press HOME and make sure it agrees with the cache,
# restarting wtprovision once if it does not.
confirm_home_on_launcher() {
    local shown focus
    [[ -n "$(wtprov_cache_pkg)" ]] || return 0
    shown=$(home_focus) || return 1
    [[ "$shown" == "$LAUNCHER_PKG" ]] && return 0
    shown="${shown:-nothing}"
    print_warning "The cache names $LAUNCHER_PKG but HOME shows $shown; restarting wtprovision"
    if wtprov_restart && focus=$(home_focus) && [[ "$focus" == "$LAUNCHER_PKG" ]]; then
        print_success "HOME is on $LAUNCHER_NAME after the restart"
        return 0
    fi
    print_error "HOME still shows '${focus:-$shown}', not $LAUNCHER_PKG; revert with: bash scripts/UNLOCK.sh --revert"
    return 1
}

all_applied() { steps_all_applied ${UNLOCK_STEPS[@]+"${UNLOCK_STEPS[@]}"}; }
apply_all() { steps_apply_all "APPLYING UNLOCK" ${UNLOCK_STEPS[@]+"${UNLOCK_STEPS[@]}"}; }
revert_all() {
    steps_revert_all "This puts the stock launcher back as the home screen" \
        ${UNLOCK_STEPS[@]+"${UNLOCK_STEPS[@]}"}
}

# ---------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------
show_menu() {
    steps_show_menu "Apply the whole unlock" "Undo everything (restore the stock launcher)"
}
single_step_menu() { steps_single_step_menu ${UNLOCK_STEPS[@]+"${UNLOCK_STEPS[@]}"}; }
interactive() { steps_interactive "Undo all changes and restore the stock launcher?"; }

usage() {
    cat <<'EOF'
Unlock the launcher on a Newlink NL5H00X projector.

  ./UNLOCK.sh              interactive menu (default)
  ./UNLOCK.sh --status     show what is and is not applied, change nothing
  ./UNLOCK.sh --apply-all  apply every step, then stop; restarts the projector
                           once if the launcher can only go into /system/app
  ./UNLOCK.sh --revert     put the stock launcher back
  ./UNLOCK.sh --repair     projector stuck on the vendor logo? diagnose and fix
  ./UNLOCK.sh --yes        do not ask for confirmation (for scripting)

Requires a rooted NL5H00X on adb and a verified backup from MAKE_BACKUP.sh.

--repair is the exception: it needs neither, because the failure it repairs
leaves the device with no adb at all. Without a device it prints the commands
to type at a serial console instead. See docs/BOOT_DEADLOCK.md.
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)    MODE=status ;;
            --apply-all) MODE=apply ;;
            --revert)    MODE=revert ;;
            --repair)    MODE=repair ;;
            --yes|-y)    ASSUME_YES=1 ;;
            -h|--help)   usage; exit 0 ;;
            *)           print_error "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    print_header "PROJECTOR UNLOCK"

    # Before require_device, which exits when nothing answers. A projector stuck
    # in this failure has no adb by definition, and that is exactly when someone
    # needs this mode.
    if [[ "$MODE" == "repair" ]]; then
        repair_run
        exit $?
    fi

    require_device true
    check_supported_device

    # Status is read-only, so it does not need a backup to exist.
    [[ "$MODE" == "status" ]] || require_backup

    case "$MODE" in
        status) show_status ;;
        apply)
            show_status
            if all_applied; then
                confirm_home_on_launcher || exit 1
                rm -f "$RESUME_MARKER"
                print_success "Nothing to do - everything is already applied"
                exit 0
            fi
            if [[ "$ASSUME_YES" != "1" ]] && ! confirm "Apply all steps now?"; then
                echo "Cancelled"; exit 0
            fi
            apply_all
            ;;
        revert)
            if [[ "$ASSUME_YES" != "1" ]] && ! confirm "Restore the stock launcher?"; then
                echo "Cancelled"; exit 0
            fi
            revert_all
            ;;
        menu)
            show_status
            interactive
            ;;
    esac
}

main "$@"
