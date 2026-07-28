#!/bin/bash
# Unlock steps for the NL5H00X projector.
#
# Every step is four functions with the same shape:
#
#   <step>_describe   one line of what it changes
#   <step>_state      applied | not-applied | blocked:<reason>
#   <step>_apply      make the change
#   <step>_revert     put it back
#
# Two rules hold throughout, both learned the hard way on the backup path:
#
#   Nothing is assumed to have worked. Every apply is followed by reading the
#   value back off the device. `adb shell ... || true` is how you end up telling
#   someone their projector is unlocked when it is not.
#
#   Steps are idempotent. Re-running a finished unlock must be a no-op, because
#   people will re-run it.

[[ -n "${_UNLOCK_SH_LOADED:-}" ]] && return 0
_UNLOCK_SH_LOADED=1

STOCK_LAUNCHER="com.newlink.hisilauncher"
NOVA_PKG="com.teslacoilsw.launcher"
NOVA_ACTIVITY="$NOVA_PKG/com.teslacoilsw.launcher.NovaLauncher"
NOVA_SYSTEM_DIR="/system/app/NovaLauncher"

UNLOCK_STEPS=(dev_options launcher_present launcher_default cleanup_leftovers)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Read a setting, normalising the device's "null" to an empty string.
setting() {
    local out
    out=$(adb_root_exec "settings get $1 $2" | tr -d ' \r\n')
    [[ "$out" == "null" ]] && out=""
    echo "$out"
}

home_activity() {
    adb_root_exec "cmd package get-home-activity" | tr -d ' \r\n'
}

package_installed() {
    adb_root_exec "pm list packages -f" 2>/dev/null | grep -q "=$1\$"
}

package_disabled() {
    adb_root_exec "pm list packages -d" 2>/dev/null | grep -q "=\?$1\$"
}

system_is_rw() {
    adb_root_exec "mount" 2>/dev/null | grep -q '/system.*[( ,]rw'
}

# Remount /system writable, verifying it actually took. Callers must pair this
# with system_ro when they are done.
system_rw() {
    system_is_rw && return 0
    adb_root_exec "mount -o remount,rw /system" >/dev/null || true
    if system_is_rw; then return 0; fi
    print_error "Could not remount /system read-write"
    return 1
}

system_ro() {
    adb_root_exec "mount -o remount,ro /system" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# step: dev_options
# ---------------------------------------------------------------------------
DEV_SETTINGS=(
    "global development_settings_enabled 1"
    "global package_verifier_enable 0"
    "global verifier_verify_adb_installs 0"
    "secure install_non_market_apps 1"
)

dev_options_describe() {
    echo "Enable developer options and allow installing apps from outside the store"
}

dev_options_state() {
    local s ns key want
    for s in "${DEV_SETTINGS[@]}"; do
        read -r ns key want <<<"$s"
        [[ "$(setting "$ns" "$key")" == "$want" ]] || { echo not-applied; return; }
    done
    echo applied
}

dev_options_apply() {
    local s ns key want got
    for s in "${DEV_SETTINGS[@]}"; do
        read -r ns key want <<<"$s"
        adb_root_exec "settings put $ns $key $want" >/dev/null || true
        got=$(setting "$ns" "$key")
        if [[ "$got" != "$want" ]]; then
            print_error "$ns/$key is '$got' after writing '$want' - the device rejected it"
            return 1
        fi
    done
    return 0
}

dev_options_revert() {
    adb_root_exec "settings put secure install_non_market_apps 0" >/dev/null || true
    adb_root_exec "settings put global package_verifier_enable 1" >/dev/null || true
    adb_root_exec "settings put global verifier_verify_adb_installs 1" >/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# step: launcher_present
# ---------------------------------------------------------------------------
launcher_present_describe() {
    echo "Make sure a replacement launcher (Nova) exists on the device"
}

launcher_present_state() {
    package_installed "$NOVA_PKG" && echo applied || echo not-applied
}

launcher_present_apply() {
    if package_installed "$NOVA_PKG"; then return 0; fi

    local apk="$APK_DIR/nova-launcher-7.0.57.apk"
    if [[ ! -f "$apk" ]]; then
        print_error "Launcher APK not found at $apk"
        return 1
    fi

    system_rw || return 1
    adb_root_exec "mkdir -p $NOVA_SYSTEM_DIR" >/dev/null || true
    if ! adb push "$apk" "$NOVA_SYSTEM_DIR/NovaLauncher.apk" >/dev/null 2>&1; then
        print_error "Could not copy the launcher into $NOVA_SYSTEM_DIR"
        system_ro
        return 1
    fi
    adb_root_exec "chmod 644 $NOVA_SYSTEM_DIR/NovaLauncher.apk" >/dev/null || true
    system_ro

    print_status "Launcher copied; it registers on the next restart"
    return 0
}

launcher_present_revert() {
    system_rw || return 1
    adb_root_exec "rm -rf $NOVA_SYSTEM_DIR" >/dev/null || true
    system_ro
    return 0
}

# ---------------------------------------------------------------------------
# step: launcher_default
#
# The one that matters. Setting the home activity on its own does not survive a
# restart while the stock launcher is still enabled -- which is why an earlier
# attempt left Nova sitting in /system/app since July and the projector still
# came up on the stock launcher. Disabling the stock launcher is what makes it
# stick, so this step does both and treats either half failing as failure.
# ---------------------------------------------------------------------------
launcher_default_describe() {
    echo "Make Nova the home screen and disable the locked stock launcher"
}

launcher_default_state() {
    package_installed "$NOVA_PKG" || { echo "blocked:install the launcher first"; return; }
    local home; home=$(home_activity)
    if [[ "$home" == "$NOVA_PKG"* ]] && package_disabled "$STOCK_LAUNCHER"; then
        echo applied
    else
        echo not-applied
    fi
}

launcher_default_apply() {
    if ! package_installed "$NOVA_PKG"; then
        print_error "$NOVA_PKG is not installed yet"
        return 1
    fi

    # Order matters: disable the stock launcher first, so it cannot win the
    # home-activity race, then point home at Nova.
    adb_root_exec "pm disable-user $STOCK_LAUNCHER" >/dev/null || true
    if ! package_disabled "$STOCK_LAUNCHER"; then
        print_error "Could not disable $STOCK_LAUNCHER - it is still enabled"
        return 1
    fi

    adb_root_exec "cmd package set-home-activity $NOVA_ACTIVITY" >/dev/null || true
    local home; home=$(home_activity)
    if [[ "$home" != "$NOVA_PKG"* ]]; then
        print_error "Home activity is '$home', expected $NOVA_PKG"
        print_warning "Re-enabling the stock launcher so you are not left without one"
        adb_root_exec "pm enable $STOCK_LAUNCHER" >/dev/null || true
        return 1
    fi
    return 0
}

launcher_default_revert() {
    adb_root_exec "pm enable $STOCK_LAUNCHER" >/dev/null || true
    adb_root_exec "cmd package set-home-activity $STOCK_LAUNCHER/.MainActivity" >/dev/null || true
    local home; home=$(home_activity)
    if [[ "$home" != "$STOCK_LAUNCHER"* ]]; then
        print_error "Could not restore the stock launcher (home is '$home')"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# step: cleanup_leftovers
# ---------------------------------------------------------------------------
LEFTOVERS=(/system/app/APKPurev32051ap /system/app/NovaLauncher_old)

cleanup_leftovers_describe() {
    echo "Remove empty and duplicated folders left by earlier unlock attempts"
}

cleanup_leftovers_state() {
    local d
    for d in "${LEFTOVERS[@]}"; do
        adb_root_exec "ls -d $d" >/dev/null 2>&1 && { echo not-applied; return; }
    done
    echo applied
}

cleanup_leftovers_apply() {
    system_rw || return 1
    local d
    for d in "${LEFTOVERS[@]}"; do
        adb_root_exec "rm -rf $d" >/dev/null 2>&1 || true
    done
    system_ro
    return 0
}

cleanup_leftovers_revert() {
    # Deliberately not reversible: these are duplicates of files that remain
    # elsewhere on the device. Saying so is better than pretending.
    print_warning "cleanup_leftovers cannot be undone (the duplicates are gone)"
    return 0
}
