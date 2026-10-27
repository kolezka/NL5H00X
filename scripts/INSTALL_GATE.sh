#!/bin/bash
# Change the vendor-wide install gate only by explicit request.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/steps.sh"
source "$SCRIPT_DIR/lib/unlock.sh"
source "$SCRIPT_DIR/lib/installgate.sh"

SUPPORTED_DEVICES=(NL5H00X NL5H00X_TP)
RESUME_FILE=""
STEP_NAME_WIDTH=18

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
            steps_run install_gate
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
