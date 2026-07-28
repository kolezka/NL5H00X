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

APK_DIR="$SCRIPT_DIR/../apks"
source "$SCRIPT_DIR/lib/unlock.sh"

# Only these devices. The unlock targets a specific stock launcher and /system
# layout; on anything else it would be guesswork with someone else's hardware.
SUPPORTED_DEVICES=(NL5H00X NL5H00X_TP)

ASSUME_YES=0
MODE=menu

# ---------------------------------------------------------------------------
# preconditions
# ---------------------------------------------------------------------------
check_supported_device() {
    local model device d
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d ' \r\n')
    device=$(adb shell getprop ro.product.device 2>/dev/null | tr -d ' \r\n')

    for d in "${SUPPORTED_DEVICES[@]}"; do
        if [[ "$model" == "$d" || "$device" == "$d" ]]; then
            print_success "Device: $model ($device)"
            return 0
        fi
    done

    print_error "Unsupported device: model='$model' device='$device'"
    echo
    echo "This tool is written for the Newlink NL5H00X projector and makes"
    echo "changes specific to its stock launcher and /system layout."
    echo "Running it elsewhere could leave you without a home screen."
    echo
    echo "Supported: ${SUPPORTED_DEVICES[*]}"
    exit 1
}

# ---------------------------------------------------------------------------
# state reporting
# ---------------------------------------------------------------------------
step_line() {
    local step="$1" state label desc
    state=$("${step}_state")
    desc=$("${step}_describe")
    case "$state" in
        applied)     label="${GREEN}[done]${NC}   " ;;
        not-applied) label="${YELLOW}[todo]${NC}   " ;;
        blocked:*)   label="${RED}[blocked]${NC}"; desc="$desc  (${state#blocked:})" ;;
        *)           label="${RED}[?]${NC}     " ;;
    esac
    printf "  %b %-18s %s\n" "$label" "$step" "$desc"
}

show_status() {
    print_section "CURRENT STATE"
    local step
    for step in "${UNLOCK_STEPS[@]}"; do step_line "$step"; done
    echo
    printf "  home screen now: %s\n" "$(home_activity)"
    echo
}

all_applied() {
    local step
    for step in "${UNLOCK_STEPS[@]}"; do
        [[ "$("${step}_state")" == "applied" ]] || return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# running steps
# ---------------------------------------------------------------------------
run_step() {
    local step="$1" state
    state=$("${step}_state")

    case "$state" in
        applied)
            print_success "$step: already done, nothing to change"
            return 0 ;;
        blocked:*)
            print_error "$step: cannot run - ${state#blocked:}"
            return 1 ;;
    esac

    print_step "$step: $("${step}_describe")"
    if ! "${step}_apply"; then
        print_error "$step FAILED - stopping, nothing further was changed"
        return 1
    fi

    # Trust the read-back, not the return code.
    state=$("${step}_state")
    if [[ "$state" != "applied" ]]; then
        print_error "$step reported success but the device still says '$state'"
        return 1
    fi
    print_success "$step: done and verified"
    return 0
}

apply_all() {
    print_section "APPLYING UNLOCK"
    local step
    for step in "${UNLOCK_STEPS[@]}"; do
        run_step "$step" || return 1
    done
    echo
    print_success "All steps applied and verified"
    echo
    print_warning "Restart the projector for the new home screen to appear:  adb reboot"
    return 0
}

revert_all() {
    print_section "REVERTING"
    print_warning "This puts the stock launcher back as the home screen"
    echo
    # Reverse order: restore the launcher before removing its files.
    local i step failed=0
    for (( i=${#UNLOCK_STEPS[@]}-1; i>=0; i-- )); do
        step="${UNLOCK_STEPS[$i]}"
        print_step "reverting $step"
        "${step}_revert" || { print_error "$step: revert failed"; failed=1; }
    done
    echo
    if [[ "$failed" -eq 0 ]]; then
        print_success "Reverted"
    else
        print_error "Revert finished with errors - check the state below"
    fi
    show_status
    return "$failed"
}

# ---------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------
show_menu() {
    echo
    echo "  1) Apply the whole unlock"
    echo "  2) Run a single step"
    echo "  3) Show current state"
    echo "  4) Undo everything (restore the stock launcher)"
    echo "  5) Restart the projector"
    echo "  q) Quit"
    echo
}

single_step_menu() {
    local i n
    echo
    for i in "${!UNLOCK_STEPS[@]}"; do
        printf "  %d)" "$((i + 1))"
        step_line "${UNLOCK_STEPS[$i]}"
    done
    echo
    read -r -p "Which step? (Enter to go back): " n
    [[ -z "$n" ]] && return 0
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#UNLOCK_STEPS[@]} )); then
        print_error "No such step"
        return 0
    fi
    run_step "${UNLOCK_STEPS[$((n - 1))]}" || true
}

interactive() {
    local choice
    while true; do
        show_menu
        read -r -p "Choice: " choice || return 0
        case "$choice" in
            1)
                if all_applied; then
                    print_success "Everything is already applied"
                elif [[ "$ASSUME_YES" == "1" ]] || confirm "Apply all steps now?"; then
                    apply_all || true
                fi
                ;;
            2) single_step_menu ;;
            3) show_status ;;
            4) confirm "Undo all changes and restore the stock launcher?" && { revert_all || true; } ;;
            5) confirm "Restart the projector now?" && { adb reboot; print_status "Restarting..."; } ;;
            q|Q) echo "Bye"; return 0 ;;
            *) print_error "Unknown choice: $choice" ;;
        esac
    done
}

usage() {
    cat <<'EOF'
Unlock the launcher on a Newlink NL5H00X projector.

  ./UNLOCK.sh              interactive menu (default)
  ./UNLOCK.sh --status     show what is and is not applied, change nothing
  ./UNLOCK.sh --apply-all  apply every step, then stop
  ./UNLOCK.sh --revert     put the stock launcher back
  ./UNLOCK.sh --yes        do not ask for confirmation (for scripting)

Requires a rooted NL5H00X on adb and a verified backup from MAKE_BACKUP.sh.
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)    MODE=status ;;
            --apply-all) MODE=apply ;;
            --revert)    MODE=revert ;;
            --yes|-y)    ASSUME_YES=1 ;;
            -h|--help)   usage; exit 0 ;;
            *)           print_error "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    print_header "PROJECTOR UNLOCK"

    require_device true
    check_supported_device

    # Status is read-only, so it does not need a backup to exist.
    [[ "$MODE" == "status" ]] || require_backup

    case "$MODE" in
        status) show_status ;;
        apply)
            show_status
            if all_applied; then
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
