#!/bin/bash
# Install persistent root on a Newlink NL5H00X projector: the sud daemon, its
# init service, and the su allow-list gate. The hybrid su (replacing
# /system/xbin/su) is optional and off by default -- pass --with-su.
#
# Same shape as UNLOCK.sh: refuses a device it does not recognise, refuses to
# run without a verified backup, shows what it will change before changing
# it, checks that each change actually took, and can put everything back.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/steps.sh"
# system_rw / system_ro / system_mountpoint / system_is_rw only -- not
# otherwise related to the launcher this file was written for.
source "$SCRIPT_DIR/lib/unlock.sh"
source "$SCRIPT_DIR/lib/root.sh"

# Only these devices. Persistent root installs to a specific /system layout;
# on anything else it would be guesswork with someone else's hardware.
SUPPORTED_DEVICES=(NL5H00X NL5H00X_TP)

ASSUME_YES=0
MODE=menu
WITH_SU=0
ALLOW_PKG=""
DENY_PKG=""
RESUME_FILE=""
STEP_NAME_WIDTH=16
UNSUPPORTED_DEVICE_TEXT="This tool installs a root daemon and init service specific to this
projector's /system layout. Running it elsewhere is guesswork on
hardware it was never written for."

# ---------------------------------------------------------------------------
# state reporting
# ---------------------------------------------------------------------------
show_status() {
    steps_show_status ${ROOT_STEPS[@]+"${ROOT_STEPS[@]}"}
    if sud_running; then
        printf "  sud daemon: running\n"
    else
        printf "  sud daemon: not running"
        if [[ "$(daemon_service_state)" == "applied" ]]; then
            printf " (a daemon that never comes up after a reboot usually means\n"
            printf "               SUD_SECLABEL is not a domain this device's SELinux policy\n"
            printf "               defines -- try --seclabel)\n"
        else
            echo
        fi
    fi
    echo
}

all_applied() { steps_all_applied $(apply_steps); }
apply_all() {
    steps_apply_all "APPLYING ROOT" $(apply_steps) || return 1
    echo
    print_warning "sud only starts on the next boot. Reboot to bring it up:  adb reboot"
    print_warning "The boot result must be watched on the screen; once booted, ROOT.sh"
    print_warning "--status confirms the daemon via pidof sud over adb."
    return 0
}
revert_all() {
    steps_revert_all "This removes the root daemon, its init service and the allow-list" \
        ${ROOT_STEPS[@]+"${ROOT_STEPS[@]}"}
}

# ---------------------------------------------------------------------------
# repair: sud installed but not coming up, or adb unreachable
# ---------------------------------------------------------------------------
repair_manual_instructions() {
    cat <<EOF

  Either the device is not reachable over adb, or adb answers but su does not.
  Equivalent commands over a serial console:

  --- sud / service / allow-list, in the order --apply-all would run them
      (point the cat commands at files staged however your console allows,
      and use SUD_SECLABEL=$SUD_SECLABEL unless you built for a different one) ---

    mount -o remount,rw /

    cat <local sud>    > $SUD_BIN_PATH
    chown root:root $SUD_BIN_PATH     # chown first: it would clear setuid/setgid
    chmod 755 $SUD_BIN_PATH
    sha256sum $SUD_BIN_PATH        # compare by hand against the local sud

    cat <local sud.rc> > $SUD_RC_PATH   # seclabel line must read: seclabel $SUD_SECLABEL
    chown root:root $SUD_RC_PATH
    chmod 644 $SUD_RC_PATH

    mount -o remount,ro /

    mkdir -p $SU_ALLOW_DIR
    chmod 700 $SU_ALLOW_DIR
    cat /dev/null > $SU_ALLOW_FILE   # only if it does not already exist -- empty means nobody
    chmod 600 $SU_ALLOW_FILE

    reboot

  --- su itself broken (adb answers, su does not): restore it from the
      permanent stock copy. ROOT.sh never deletes $SU_ORIG_PATH for exactly
      this case ---

    mount -o remount,rw /
    cp $SU_ORIG_PATH $SU_HYBRID_PATH
    chown root:root $SU_HYBRID_PATH   # before chmod: chown clears setuid
    chmod $(stat -c %a $SU_ORIG_PATH) $SU_HYBRID_PATH   # the stock mode, not a guess
    sha256sum $SU_ORIG_PATH $SU_HYBRID_PATH   # confirm both lines match
    stat -c '%a %n' $SU_ORIG_PATH $SU_HYBRID_PATH   # and that the mode survived
    mount -o remount,ro /

  pm has nothing to do with any of this: these are file and mount operations,
  not package operations, and a wrong seclabel just means sud never starts --
  boot continues normally either way, never a brick.

EOF
}

repair_run() {
    # Deliberately not require_device: it exits the whole process on failure,
    # and both failures this diagnoses -- no adb at all, or adb up but su not
    # answering -- need a diagnosis printed and a normal return, not exit 1.
    if ! adb devices 2>/dev/null | grep -q "device$"; then
        print_error "No device on adb"
        repair_manual_instructions
        return 2
    fi
    check_adb || { repair_manual_instructions; return 2; }
    check_device_connected || { repair_manual_instructions; return 2; }

    print_status "Checking root access..."
    if ! check_root_access; then
        print_error "Device answers adb, but su does not answer -- su itself may be broken"
        print_warning "Restore it from the permanent stock copy over UART (see below);"
        print_warning "$SU_ORIG_PATH is never deleted by ROOT.sh for exactly this case."
        repair_manual_instructions
        return 1
    fi

    show_status

    if [[ "$(daemon_service_state)" == "applied" ]] && ! sud_running; then
        print_error "sud.rc is installed but sud is not running"
        print_warning "This usually means SUD_SECLABEL=$SUD_SECLABEL is not a domain this"
        print_warning "device's SELinux policy defines. Re-run with --seclabel <label> that"
        print_warning "exists on this device (daemon_service will overwrite the old one),"
        print_warning "then reboot."
        return 1
    fi

    print_success "Nothing to repair"
    return 0
}

# ---------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------
show_menu() { steps_show_menu "Apply all steps" "Revert everything"; }
single_step_menu() { steps_single_step_menu ${ROOT_STEPS[@]+"${ROOT_STEPS[@]}"}; }
interactive() { steps_interactive "Revert everything?"; }

usage() {
    cat <<EOF
Install persistent root on a Newlink NL5H00X projector.

  ./ROOT.sh                    interactive menu (default)
  ./ROOT.sh --status           show what is and is not applied, change nothing
  ./ROOT.sh --apply-all        apply every step, then stop
  ./ROOT.sh --revert           remove the root daemon, service and allow-list
  ./ROOT.sh --repair           sud not running after a reboot? diagnose why
  ./ROOT.sh --yes              do not ask for confirmation (for scripting)
  ./ROOT.sh --with-su          also install the hybrid su (off by default)
  ./ROOT.sh --allow PKG        add PKG to the su allow-list
  ./ROOT.sh --deny PKG         remove PKG from the su allow-list
  ./ROOT.sh --seclabel LABEL   override the sud.rc seclabel (default u:r:su:s0)

Requires a rooted NL5H00X on adb and a verified backup from MAKE_BACKUP.sh.

--repair is the exception: with adb it diagnoses; without it, it prints the
serial-console equivalent, because a stuck seclabel does not cost adb the way
a boot deadlock does.
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)    MODE=status; shift ;;
            --apply-all) MODE=apply; shift ;;
            --revert)    MODE=revert; shift ;;
            --repair)    MODE=repair; shift ;;
            --yes|-y)    ASSUME_YES=1; shift ;;
            --with-su)   WITH_SU=1; shift ;;
            # shift 1 then shift-if-present, not shift 2: a trailing
            # --allow/--deny/--seclabel with no value would make `shift 2`
            # itself the error (shift count > $#) under set -e, instead of
            # the missing-value message each mode already prints. The `if`
            # form matters here, not `[[ ... ]] && shift`: a bare `&&` whose
            # left side is false still fails the whole statement under set -e,
            # while an if's condition is the one place that failure is exempt.
            --allow)     MODE=allow; ALLOW_PKG="${2:-}"; shift; if [[ $# -gt 0 ]]; then shift; fi ;;
            --deny)      MODE=deny; DENY_PKG="${2:-}"; shift; if [[ $# -gt 0 ]]; then shift; fi ;;
            --seclabel)  SUD_SECLABEL="${2:-}"; shift; if [[ $# -gt 0 ]]; then shift; fi ;;
            -h|--help)   usage; exit 0 ;;
            *)           print_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    print_header "PROJECTOR ROOT"

    # Before require_device, which exits when nothing answers -- --repair has
    # to work precisely when that is the case.
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
        allow)
            [[ -n "$ALLOW_PKG" ]] || { print_error "--allow needs a package name"; exit 1; }
            allow_list_apply >/dev/null || true
            if allow_list_add "$ALLOW_PKG"; then
                print_success "Added $ALLOW_PKG to the allow-list"
            else
                print_error "Could not update the allow-list"
                exit 1
            fi
            ;;
        deny)
            [[ -n "$DENY_PKG" ]] || { print_error "--deny needs a package name"; exit 1; }
            allow_list_apply >/dev/null || true
            if allow_list_remove "$DENY_PKG"; then
                print_success "Removed $DENY_PKG from the allow-list"
            else
                print_error "Could not update the allow-list"
                exit 1
            fi
            ;;
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
            if [[ "$ASSUME_YES" != "1" ]] && ! confirm "Revert everything?"; then
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
