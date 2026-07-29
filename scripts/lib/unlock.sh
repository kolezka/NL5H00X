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

# Projectivy Launcher. This projector is driven by a remote, not a touchscreen,
# and Projectivy is a leanback launcher -- it lays out for a D-pad and declares
# LEANBACK_LAUNCHER. Nova, which an earlier attempt left in /system/app, is a
# phone launcher: workable with a mouse, miserable with the remote in the box.
#
# Overridable so this works for someone who wants a different launcher; nothing
# below hardcodes Projectivy beyond these four lines.
LAUNCHER_PKG="${LAUNCHER_PKG:-com.spocky.projengmenu}"
LAUNCHER_NAME="${LAUNCHER_NAME:-Projectivy}"
LAUNCHER_APK_GLOB="${LAUNCHER_APK_GLOB:-projectivy*.apk}"
LAUNCHER_SYSTEM_DIR="${LAUNCHER_SYSTEM_DIR:-/system/app/Projectivy}"

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

# The home activity currently preferred by the system.
#
# `cmd package get-home-activity` DOES NOT EXIST on API 28 -- it answers
# "Unknown command: get-home-activity", and because that was never checked the
# status screen cheerfully printed "home screen now: Unknowncommand:get-home-activity".
# `set-home-activity` does exist, so the write path was fine and only the read
# path was fiction. Measured on the device 2026-07-29.
#
# What it writes lands in the preferred-activity table, so that is where it has
# to be read from: find the component whose filter carries CATEGORY_HOME and is
# pinned with mAlways=true.
home_activity() {
    adb_root_exec "dumpsys package preferred-activities" 2>/dev/null | tr -d '\r' | awk '
        /^[[:space:]]+[0-9a-f]+ [A-Za-z0-9_.]+\// { comp = $2; always = 0 }
        /mAlways=true/                            { always = 1 }
        /android\.intent\.category\.HOME/         { if (always && comp != "") { print comp; exit } }
    '
}

# The component a given package registers for HOME.
#
# Never hardcode this. The stock launcher's HOME entry is .WizardAciticity --
# their spelling, not a typo here -- while the activity you actually see is
# .MainActivity, which carries no HOME filter at all. --revert pointed
# set-home-activity at .MainActivity, so the way back would have failed on the
# first device it was ever tried on.
home_component_of() {
    local pkg="$1"
    adb_root_exec "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME" 2>/dev/null \
        | tr -d '\r' | grep -oE "${pkg//./[.]}/[A-Za-z0-9_.$]+" | head -1
}

package_installed() {
    adb_root_exec "pm list packages -f" 2>/dev/null | grep -q "=$1\$"
}

package_disabled() {
    adb_root_exec "pm list packages -d" 2>/dev/null | grep -q "=\?$1\$"
}

# Where a package's APK lives, or empty. Used to tell a launcher we installed
# from one that shipped in /system -- uninstalling the latter is not ours to do.
package_path() {
    adb_root_exec "pm list packages -f" 2>/dev/null | tr -d '\r' \
        | sed -n "s|^package:\(.*\)=$1\$|\1|p" | head -1
}

# The component that actually handles HOME for our launcher. Empty means the
# package registers no home activity at all, which is the honest answer and far
# better than guessing a component set-home-activity would quietly refuse.
launcher_component() { home_component_of "$LAUNCHER_PKG"; }

# Prove the replacement launcher works before anything relies on it.
#
# "Installed" is not the same as "usable": a launcher that crashes on start
# still shows up in `pm list packages`, and disabling the stock launcher on the
# strength of that leaves the projector with no home screen at all. So start it
# and check it is still alive a moment later.
launcher_runs() {
    local comp="$1" out

    out=$(adb_root_exec "am start -n $comp" 2>&1)
    # `am start` exits 0 even when it refuses -- the error is only in the text.
    if echo "$out" | grep -qiE '^Error|does not exist|Exception|not started'; then
        print_error "$LAUNCHER_NAME would not start: $(echo "$out" | grep -iE 'Error|Exception' | head -1)"
        return 1
    fi

    # Long enough for a launcher that is going to crash to have done so.
    sleep "${LAUNCHER_SETTLE_SECS:-3}"
    if ! adb_root_exec "pidof $LAUNCHER_PKG" | grep -qE '[0-9]'; then
        print_error "$LAUNCHER_NAME started and then died - it is not usable as a home screen"
        return 1
    fi
    return 0
}

# The APK to install, matched by glob so a version bump does not need an edit.
launcher_apk() {
    local f
    for f in "$APK_DIR"/$LAUNCHER_APK_GLOB; do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done
    return 1
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
    echo "Make sure the replacement launcher ($LAUNCHER_NAME) exists on the device"
}

launcher_present_state() {
    package_installed "$LAUNCHER_PKG" && echo applied || echo not-applied
}

# Try a normal install first, fall back to /system/app.
#
# `pm install` is the better path where it works: it registers immediately, so
# launcher_default can prove the new launcher runs while the stock one is still
# there to fall back on, and it is plainly reversible.
#
# On this projector it does not work. Every install path -- adb install,
# streamed, and a session install whose write phase succeeds -- fails at commit
# with INSTALL_FAILED_INVALID_INSTALL_LOCATION, with sideloading fully enabled,
# no user restrictions, install location on auto and 4.2 GB free. /data/app is
# empty and `pm list packages -3` returns nothing: nothing has EVER been
# installed normally on this device. That is the vendor lock this toolkit
# exists to work around, and it is why APKPure, Magisk and Nova are all sitting
# in /system/app rather than installed.
#
# So: prefer the clean path, and drop to /system/app when the device refuses.
# The cost of the fallback is that the package only registers on the next boot,
# which is why this reports needs-restart rather than pretending to be done.
launcher_present_apply() {
    if package_installed "$LAUNCHER_PKG"; then return 0; fi

    local apk out
    if ! apk=$(launcher_apk); then
        print_error "No $LAUNCHER_NAME APK in $APK_DIR (looked for $LAUNCHER_APK_GLOB)"
        return 1
    fi

    out=$(adb install -r "$apk" 2>&1)
    if package_installed "$LAUNCHER_PKG"; then return 0; fi

    print_warning "The device refused a normal install: $(echo "$out" | grep -oE 'Failure \[[A-Z_]+\]' | head -1)"
    print_status "Falling back to $LAUNCHER_SYSTEM_DIR, which is how this device accepts apps"

    system_rw || return 1
    adb_root_exec "mkdir -p $LAUNCHER_SYSTEM_DIR" >/dev/null || true
    if ! adb push "$apk" "$LAUNCHER_SYSTEM_DIR/$(basename "$LAUNCHER_SYSTEM_DIR").apk" >/dev/null 2>&1; then
        print_error "Could not copy the launcher into $LAUNCHER_SYSTEM_DIR"
        system_ro
        return 1
    fi
    adb_root_exec "chmod 644 $LAUNCHER_SYSTEM_DIR/$(basename "$LAUNCHER_SYSTEM_DIR").apk" >/dev/null || true
    system_ro

    print_warning "$LAUNCHER_NAME will only register after a restart - rerun this afterwards"
    return 1
}

launcher_present_revert() {
    # The fallback copy may exist even when the package never registered, so
    # this runs regardless of whether pm knows about the launcher.
    if adb_root_exec "ls -d $LAUNCHER_SYSTEM_DIR" >/dev/null 2>&1; then
        system_rw || return 1
        adb_root_exec "rm -rf $LAUNCHER_SYSTEM_DIR" >/dev/null || true
        system_ro
        print_warning "Removed $LAUNCHER_SYSTEM_DIR; it stops being a package after a restart"
    fi

    package_installed "$LAUNCHER_PKG" || return 0

    # A launcher that shipped in /system with the firmware is not ours to
    # remove, and pm uninstall on a system package only strips the update.
    local path; path=$(package_path "$LAUNCHER_PKG")
    if [[ "$path" == /system/* && "$path" != "$LAUNCHER_SYSTEM_DIR"/* ]]; then
        print_warning "$LAUNCHER_NAME lives in $path and was not installed by this tool - leaving it"
        return 0
    fi

    adb_root_exec "pm uninstall $LAUNCHER_PKG" >/dev/null 2>&1 || true
    if package_installed "$LAUNCHER_PKG"; then
        print_error "Could not uninstall $LAUNCHER_PKG"
        return 1
    fi
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
#
# Disabling it is also the only moment in the unlock that can leave someone
# staring at a projector with no home screen, so it happens last and only after
# the replacement has been seen to actually run.
# ---------------------------------------------------------------------------
launcher_default_describe() {
    echo "Make $LAUNCHER_NAME the home screen and disable the locked stock launcher"
}

launcher_default_state() {
    package_installed "$LAUNCHER_PKG" || { echo "blocked:install the launcher first"; return; }
    local home; home=$(home_activity)
    if [[ "$home" == "$LAUNCHER_PKG"* ]] && package_disabled "$STOCK_LAUNCHER"; then
        echo applied
    else
        echo not-applied
    fi
}

launcher_default_apply() {
    if ! package_installed "$LAUNCHER_PKG"; then
        print_error "$LAUNCHER_PKG is not installed yet"
        return 1
    fi

    local comp; comp=$(launcher_component)
    if [[ -z "$comp" ]]; then
        print_error "$LAUNCHER_NAME registers no home activity on this device"
        print_warning "Nothing was changed; the stock launcher is untouched"
        return 1
    fi

    # Everything above this line is reversible by doing nothing. Prove the
    # replacement works while the stock launcher is still enabled and running,
    # so a broken launcher costs a failed step rather than a home screen.
    print_status "Checking $LAUNCHER_NAME actually runs before touching the stock launcher"
    if ! launcher_runs "$comp"; then
        print_warning "Refusing to disable the stock launcher - you would have nothing to go back to"
        return 1
    fi

    # Order matters: disable the stock launcher first, so it cannot win the
    # home-activity race, then point home at the replacement.
    adb_root_exec "pm disable-user $STOCK_LAUNCHER" >/dev/null || true
    if ! package_disabled "$STOCK_LAUNCHER"; then
        print_error "Could not disable $STOCK_LAUNCHER - it is still enabled"
        return 1
    fi

    adb_root_exec "cmd package set-home-activity $comp" >/dev/null || true
    local home; home=$(home_activity)
    if [[ "$home" != "$LAUNCHER_PKG"* ]]; then
        print_error "Home activity is '$home', expected $LAUNCHER_PKG"
        print_warning "Re-enabling the stock launcher so you are not left without one"
        adb_root_exec "pm enable $STOCK_LAUNCHER" >/dev/null || true
        return 1
    fi
    return 0
}

launcher_default_revert() {
    # Re-enable first: a disabled package registers no activities, so the
    # component lookup below would come back empty.
    adb_root_exec "pm enable $STOCK_LAUNCHER" >/dev/null || true
    if package_disabled "$STOCK_LAUNCHER"; then
        print_error "Could not re-enable $STOCK_LAUNCHER"
        return 1
    fi

    local comp; comp=$(home_component_of "$STOCK_LAUNCHER")
    if [[ -z "$comp" ]]; then
        print_error "$STOCK_LAUNCHER registers no home activity to restore to"
        return 1
    fi

    adb_root_exec "cmd package set-home-activity $comp" >/dev/null || true
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
