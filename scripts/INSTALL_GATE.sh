#!/bin/bash
# Change the vendor-wide install gate only by explicit request.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/unlock.sh"
source "$SCRIPT_DIR/lib/installgate.sh"

SUPPORTED_DEVICES=(NL5H00X NL5H00X_TP)

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
    printf "  %b %-18s %s\n" "$label" "$step" "$desc"
}

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
    state=$("${step}_state")
    if [[ "$state" != applied ]]; then
        print_error "$step reported success but the device still says '$state'"
        return 1
    fi
    print_success "$step: done and verified"
}

usage() {
    cat <<'EOF'
Usage: nl5h00x install-gate off|on|status [--yes]

  off       let every app on the projector install other apps
  on        restore the original build.prop, or remove the whitelist line
  status    show the live build.prop state without changing it
  --yes     skip confirmation

The change takes effect after a restart: adb reboot
EOF
}

main() {
    local mode="" assume_yes=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            off|on|status)
                [[ -z "$mode" ]] || { usage >&2; return 2; }
                mode="$1" ;;
            --yes) assume_yes=1 ;;
            -h|--help) usage; return 0 ;;
            *) usage >&2; return 2 ;;
        esac
        shift
    done
    [[ -n "$mode" ]] || { usage >&2; return 2; }

    print_header "INSTALL GATE"
    require_device true
    check_supported_device || return 1
    [[ "$mode" == status ]] || require_backup
    case "$mode" in
        status) step_line install_gate ;;
        off)
            if [[ "$assume_yes" != 1 ]]; then
                echo "This lets every app on the projector install other apps, not only the launcher."
                echo "It changes /system/build.prop and takes effect after a restart: adb reboot"
                if ! confirm "Turn off the install gate?"; then
                    echo "Cancelled"
                    return 0
                fi
            fi
            run_step install_gate
            echo "takes effect after a restart: adb reboot"
            ;;
        on)
            if [[ "$assume_yes" != 1 ]] && ! confirm "Restore the install gate?"; then
                echo "Cancelled"
                return 0
            fi
            install_gate_revert
            [[ "$(install_gate_state)" == not-applied ]] || {
                print_error "install_gate still reports applied after revert"
                return 1
            }
            echo "takes effect after a restart: adb reboot"
            ;;
    esac
}

main "$@"
