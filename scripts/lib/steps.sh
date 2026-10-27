#!/bin/bash
# Shared step runner. Entry scripts own their step lists and device-specific status.

check_supported_device() {
    local model device d
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d ' \r\n')
    device=$(adb shell getprop ro.product.device 2>/dev/null | tr -d ' \r\n')
    for d in "${SUPPORTED_DEVICES[@]+"${SUPPORTED_DEVICES[@]}"}"; do
        if [[ "$model" == "$d" || "$device" == "$d" ]]; then
            print_success "Device: $model ($device)"
            return 0
        fi
    done
    print_error "Unsupported device: model='$model' device='$device'"
    if [[ -n "${UNSUPPORTED_DEVICE_TEXT:-}" ]]; then
        echo
        printf '%s\n' "$UNSUPPORTED_DEVICE_TEXT"
        echo
        echo "Supported: ${SUPPORTED_DEVICES[*]}"
    fi
    return 1
}

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
    printf "  %b %-${STEP_NAME_WIDTH:-18}s %s\n" "$label" "$step" "$desc"
}

steps_show_status() {
    print_section "CURRENT STATE"
    local step
    for step in "$@"; do step_line "$step"; done
    echo
}

steps_all_applied() {
    local step
    for step in "$@"; do
        [[ "$("${step}_state")" == "applied" ]] || return 1
    done
    return 0
}

steps_run() {
    local step="$1" state rc=0
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
    "${step}_apply" || rc=$?
    if [[ -n "${RESUME_FILE:-}" && "$rc" -eq "${NEEDS_REBOOT:-3}" ]]; then
        return "$rc"
    fi
    if [[ "$rc" -ne 0 ]]; then
        print_error "$step FAILED - stopping, nothing further was changed"
        return 1
    fi
    state=$("${step}_state")
    if [[ "$state" != "applied" ]]; then
        print_error "$step reported success but the device still says '$state'"
        return 1
    fi
    print_success "$step: done and verified"
    return 0
}

steps_restart_for_step() {
    local step="$1" uptime_before rc=0
    uptime_before=$(device_uptime_s)
    if ! printf '%s\n' "$step" 2>/dev/null > "$RESUME_FILE" \
        || [[ "$(cat "$RESUME_FILE" 2>/dev/null)" != "$step" ]]; then
        print_error "Could not save the resume marker $RESUME_FILE, so the projector was not restarted"
        return 1
    fi
    if [[ -z "$uptime_before" ]]; then
        print_error "Could not read /proc/uptime, so the projector was not restarted. Restart it by hand, then run the same command again; the marker $RESUME_FILE keeps the place."
        return 1
    fi
    print_status "Restarting the projector to register $step; the unlock continues on its own"
    if [[ "$ASSUME_YES" != "1" ]] && ! confirm "Restart the projector now?"; then
        print_warning "Not restarted. Restart the projector, then run the same command again; the marker $RESUME_FILE keeps the place."
        return 1
    fi
    if ! adb reboot >/dev/null 2>&1; then
        print_error "adb reboot failed. Restart the projector by hand, then run the same command again; the marker $RESUME_FILE keeps the place."
        return 1
    fi
    wait_for_device_boot "$UNLOCK_BOOT_TIMEOUT" "$uptime_before" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
        print_error "The projector did not restart. Restart it by hand, then run the same command again; the marker $RESUME_FILE keeps the place."
        return 1
    elif [[ "$rc" -ne 0 ]]; then
        print_error "The projector did not come back within $UNLOCK_BOOT_TIMEOUT s. When it is up, run the same command again; the marker $RESUME_FILE keeps the place."
        return 1
    fi
    print_success "The projector is back"
}

steps_apply_all() {
    local title="$1" step rc resumed="" skip_to="" candidate=""
    shift
    print_section "$title"
    if [[ -n "${RESUME_FILE:-}" && -f "$RESUME_FILE" ]]; then
        resumed=$(tr -d ' \r\n' < "$RESUME_FILE")
        for candidate in "$@"; do
            [[ "$candidate" == "$resumed" ]] && break
        done
        if [[ "$candidate" == "$resumed" ]]; then
            print_status "Resuming after a restart, from $resumed"
            skip_to="$resumed"
        else
            print_warning "Ignoring $RESUME_FILE: '$resumed' is not a step"
            resumed=""
        fi
    fi
    for step in "$@"; do
        if [[ -n "$skip_to" ]]; then
            [[ "$step" == "$skip_to" ]] || continue
            skip_to=""
        fi
        rc=0
        steps_run "$step" || rc=$?
        if [[ -n "${RESUME_FILE:-}" && "$rc" -eq "${NEEDS_REBOOT:-3}" ]]; then
            if [[ "$step" == "$resumed" ]]; then
                print_error "$step still needs a restart after the last one; the launcher did not register. Check /system/app on the device."
                return 1
            fi
            steps_restart_for_step "$step" || return 1
        elif [[ "$rc" -ne 0 ]]; then
            return 1
        fi
    done
    if [[ -n "${RESUME_FILE:-}" ]]; then rm -f "$RESUME_FILE"; fi
    echo
    print_success "All steps applied and verified"
    return 0
}

steps_revert_all() {
    local warning="$1" i step failed=0
    shift
    print_section "REVERTING"
    print_warning "$warning"
    echo
    if [[ -n "${RESUME_FILE:-}" ]]; then rm -f "$RESUME_FILE"; fi
    local count=$# steps=("$@")
    for (( i=count-1; i>=0; i-- )); do
        step="${steps[$i]}"
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

steps_show_menu() {
    echo
    echo "  1) $1"
    echo "  2) Run a single step"
    echo "  3) Show current state"
    echo "  4) $2"
    echo "  5) Restart the projector"
    echo "  q) Quit"
    echo
}

steps_single_step_menu() {
    local i n rc=0 count=$# steps=("$@")
    echo
    for (( i=0; i<count; i++ )); do
        printf "  %d)" "$((i + 1))"
        step_line "${steps[$i]}"
    done
    echo
    read -r -p "Which step? (Enter to go back): " n
    [[ -z "$n" ]] && return 0
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > count )); then
        print_error "No such step"
        return 0
    fi
    steps_run "${steps[$((n - 1))]}" || rc=$?
    if [[ -n "${RESUME_FILE:-}" && "$rc" -eq "${NEEDS_REBOOT:-3}" ]]; then
        print_warning "Restart the projector (option 5) for this to take effect"
    fi
    return 0
}

steps_interactive() {
    local revert_confirm="$1" choice
    while true; do
        show_menu
        read -r -p "Choice: " choice || return 0
        case "$choice" in
            1)
                if all_applied; then
                    if [[ -z "${RESUME_FILE:-}" ]] || confirm_home_on_launcher; then
                        print_success "Everything is already applied"
                        if [[ -n "${RESUME_FILE:-}" ]]; then rm -f "$RESUME_FILE"; fi
                    fi
                elif [[ "$ASSUME_YES" == "1" ]] || confirm "Apply all steps now?"; then
                    apply_all || true
                fi
                ;;
            2) single_step_menu ;;
            3) show_status ;;
            4) confirm "$revert_confirm" && { revert_all || true; } ;;
            5) confirm "Restart the projector now?" && { adb reboot; print_status "Restarting..."; } ;;
            q|Q) echo "Bye"; return 0 ;;
            *) print_error "Unknown choice: $choice" ;;
        esac
    done
}
