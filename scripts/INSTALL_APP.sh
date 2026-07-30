#!/bin/bash
# Install an APK on a projector whose PackageManager refuses every normal install.
#
# This device answers INSTALL_FAILED_INVALID_INSTALL_LOCATION to every install
# path there is -- adb streamed, session, local file, with -f, and as uid 0 --
# with sideloading enabled, no user restrictions, install location on auto and
# gigabytes free. /data/app is empty: nothing has ever been installed normally
# here. The failure is inside the vendor's patched PackageManagerService, in
# install-location resolution, and it is not something a caller can flag around.
# See docs/INSTALL_LOCKED.md.
#
# So apps go into /system/app instead, which is how APKPure, Magisk, Nova and
# Projectivy all got onto this device.
#
# Two things make that more than `cp`, and both are why this script exists:
#
#   Native libraries. A normal install extracts lib/<abi>/*.so out of the APK.
#   Copying the APK alone does not, and the app then dies at the first
#   System.loadLibrary with "native library not loaded". Measured on hardware
#   2026-07-30: SmartTube installed fine, browsed fine, and threw
#   IllegalStateException: J2V8 native library not loaded on playback until the
#   .so files were unpacked into /system/app/SmartTube/lib/arm/.
#
#   The home intent. An APK that declares CATEGORY_HOME becomes a candidate for
#   the launcher the moment it registers, and on this firmware getting the home
#   intent wrong is what bricks the device (docs/BOOT_DEADLOCK.md). This script
#   reads the manifest and refuses rather than find out after the reboot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/unlock.sh
source "$SCRIPT_DIR/lib/unlock.sh"   # system_rw / system_ro / package_installed

SYSTEM_APP_DIR="/system/app"
STAGING="/data/local/tmp"

# Packages the --remove path will not touch, whatever the caller says. The first
# two are the home dispatcher and the stock launcher: removing either is the
# documented way to make this device stop booting.
readonly PROTECTED_PKGS=(
    com.newlink.wtprovision
    com.newlink.hisilauncher
    com.android.tv.settings
    com.android.settings
)

APK=""
APP_NAME=""
REMOVE_PKG=""
ALLOW_HOME=false
DO_REBOOT="ask"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") <file.apk> [--name NAME] [--allow-home] [--reboot|--no-reboot]
  $(basename "$0") --remove <package.name> [--reboot|--no-reboot]

  <file.apk>      APK to install.
  --name NAME     Directory under $SYSTEM_APP_DIR. Defaults to the leading
                  alphanumeric run of the APK filename (SmartTube_stable_31.94
                  -> SmartTube).
  --allow-home    Permit an APK that declares CATEGORY_HOME or
                  CATEGORY_SETUP_WIZARD. Refused by default: on this firmware a
                  wrong home candidate is how the device stops booting.
  --remove PKG    Delete a package this script installed, by package name.
  --reboot        Reboot without asking. --no-reboot skips it, and the app then
                  stays unregistered until the next boot.
EOF
}

# ---------------------------------------------------------------------------
# local helpers
# ---------------------------------------------------------------------------

local_md5() {
    if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
    else md5sum "$1" | awk '{print $1}'
    fi
}

# Read the APK's binary manifest and print shell-safe facts about it:
#
#   PKG=<package name>
#   HOME=yes|no          declares CATEGORY_HOME or CATEGORY_SETUP_WIZARD
#   ERROR=<reason>       nothing else is printed
#
# aapt is not assumed: it ships with the Android SDK build-tools, which a person
# fixing a projector over ADB has no reason to have. The manifest is parsed
# directly instead. Two traps are handled explicitly.
#
# The string pool is UTF-16 unless a flag says otherwise, and `strings` on macOS
# cannot see UTF-16 at all -- so grepping an APK "for HOME" reports a clean bill
# of health for every APK ever made. That is a false clearance on the one check
# that stops this script bricking the device, so the pool is decoded properly
# and the result is sanity-checked against a string every manifest must contain.
#
# The package name is an attribute of the <manifest> element, so the element
# tree is walked to read it. Fishing it out of the flat string pool would be
# guesswork: the pool holds every string in the file with no structure attached.
apk_facts() {
    local apk="$1"
    unzip -p "$apk" AndroidManifest.xml 2>/dev/null | python3 -c '
import struct, sys

d = sys.stdin.buffer.read()
if len(d) < 0x20 or d[:4] != b"\x03\x00\x08\x00":
    print("ERROR=not-an-android-manifest"); raise SystemExit(0)

try:
    pool_size = struct.unpack_from("<I", d, 0x0C)[0]
    cnt, _sty, flags, stroff = struct.unpack_from("<IIII", d, 0x10)
    utf8 = bool(flags & (1 << 8))
    # The offset array starts after the whole ResStringPool_header, i.e. at
    # 0x24: stringCount, styleCount, flags, stringsStart, stylesStart. Starting
    # it at stringsStart instead shifts every index by two, which still finds
    # strings by value -- so the HOME check keeps working -- while silently
    # returning the wrong string for every index lookup.
    offs = struct.unpack_from("<%dI" % cnt, d, 0x24)
    base = 8 + stroff
    pool = []
    for o in offs:
        p = base + o
        if utf8:
            n = d[p]; p += 1
            if n & 0x80: p += 1
            n = d[p]; p += 1
            if n & 0x80:
                n = ((n & 0x7F) << 8) | d[p]; p += 1
            pool.append(d[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", d, p)[0]; p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", d, p)[0]; p += 2
            pool.append(d[p:p + n * 2].decode("utf-16-le", "replace"))
except Exception:
    print("ERROR=string-pool-unreadable"); raise SystemExit(0)

# A manifest without MAIN means the decode went wrong, not that the app is
# unusual. Bail rather than report a reassuring "no HOME".
if "android.intent.action.MAIN" not in pool:
    print("ERROR=manifest-parse-failed"); raise SystemExit(0)

def s(i):
    return pool[i] if 0 <= i < len(pool) else ""

pkg = ""
try:
    pos = 8 + pool_size
    while pos + 8 <= len(d):
        ctype, _hsize, csize = struct.unpack_from("<HHI", d, pos)
        if csize <= 0:
            break
        if ctype == 0x0102:                                   # START_TAG
            name = s(struct.unpack_from("<I", d, pos + 0x14)[0])
            if name == "manifest":
                attr_start = struct.unpack_from("<H", d, pos + 0x18)[0]
                attr_count = struct.unpack_from("<H", d, pos + 0x1C)[0]
                for i in range(attr_count):
                    a = pos + 0x10 + attr_start + i * 20
                    a_name, a_raw = struct.unpack_from("<II", d, a + 4)
                    if s(a_name) == "package":
                        pkg = s(a_raw)
                break
        pos += csize
except Exception:
    pkg = ""

home = any(x in ("android.intent.category.HOME",
                 "android.intent.category.SETUP_WIZARD") for x in pool)
print("PKG=%s" % pkg)
print("HOME=%s" % ("yes" if home else "no"))
'
}

# ABI directories present in the APK, in zip order.
apk_abis() {
    unzip -l "$1" 2>/dev/null \
        | sed -n 's|.*[[:space:]]lib/\([^/]*\)/.*\.so$|\1|p' | sort -u
}

# Android's directory name for an ABI: /system/app/X/lib/<isa>/.
abi_to_isa() {
    case "$1" in
        armeabi-v7a|armeabi) echo arm ;;
        arm64-v8a)           echo arm64 ;;
        x86)                 echo x86 ;;
        x86_64)              echo x86_64 ;;
        *)                   echo "" ;;
    esac
}

default_name_from_apk() {
    local b; b=$(basename "$1"); b="${b%.apk}"
    local lead="${b%%[!A-Za-z0-9]*}"
    [[ -n "$lead" ]] && printf '%s' "$lead" || printf '%s' "$(echo "$b" | tr -cd 'A-Za-z0-9')"
}

# ---------------------------------------------------------------------------
# reboot + verify
# ---------------------------------------------------------------------------

reboot_and_wait() {
    local before after
    before=$(adb shell 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')
    [[ -n "$before" ]] || before=0

    print_step "Rebooting so the package manager rescans $SYSTEM_APP_DIR"
    adb reboot >/dev/null 2>&1 || true

    for _ in $(seq 1 40); do
        sleep 5
        [[ "$(adb shell 'getprop sys.boot_completed' 2>/dev/null | tr -d '\r')" == "1" ]] || continue
        after=$(adb shell 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')
        # "the device answered again" only proves a reboot if uptime went
        # backwards; without that a dropped-and-restored link reads as success.
        if [[ -n "$after" && "$after" -lt "$before" ]]; then
            print_success "Device rebooted (uptime $before s -> $after s)"
            return 0
        fi
        print_warning "Device responded but uptime did not reset ($before s -> ${after:-?} s)"
        return 1
    done

    print_error "Device did not come back within 200s"
    print_warning "If it is stuck, see docs/BOOT_DEADLOCK.md and scripts/UNLOCK.sh --repair"
    return 1
}

verify_installed() {
    local pkg="$1" isa="$2" dir="$3"

    if ! package_installed "$pkg"; then
        print_error "$pkg did not register after the reboot"
        return 1
    fi
    print_success "$pkg is registered"

    local abi
    abi=$(adb_root_exec "dumpsys package $pkg" 2>/dev/null | tr -d '\r' \
          | sed -n 's/.*primaryCpuAbi=\([^ ]*\).*/\1/p' | head -1) || true
    if [[ -n "$isa" ]]; then
        if [[ -z "$abi" || "$abi" == "null" ]]; then
            print_error "No primaryCpuAbi resolved - native libraries will not load"
            print_warning "Check $dir/lib/$isa/ exists and is readable"
            return 1
        fi
        print_success "Native ABI resolved: $abi"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------

remove_app() {
    local pkg="$1" p code dir

    for p in "${PROTECTED_PKGS[@]}"; do
        if [[ "$pkg" == "$p" ]]; then
            print_error "Refusing to remove $pkg - it is required for this device to boot"
            return 1
        fi
    done

    code=$(adb_root_exec "dumpsys package $pkg" 2>/dev/null | tr -d '\r' \
           | sed -n 's/.*codePath=\(.*\)/\1/p' | head -1) || true
    if [[ -z "$code" ]]; then
        print_error "$pkg is not installed"
        return 1
    fi
    if [[ "$code" != "$SYSTEM_APP_DIR/"* ]]; then
        print_error "$pkg lives at $code, not under $SYSTEM_APP_DIR - not ours to delete"
        return 1
    fi

    dir="$code"
    print_warning "About to delete $dir"
    read -r -p "Type the package name to confirm: " confirm
    [[ "$confirm" == "$pkg" ]] || { print_status "Cancelled"; return 1; }

    system_rw || return 1
    adb_root_exec "rm -rf $dir" >/dev/null || true
    system_ro

    if adb_root_exec "ls -d $dir" >/dev/null 2>&1; then
        print_error "$dir is still there"
        return 1
    fi
    print_success "Deleted $dir"
    return 0
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

install_app() {
    local apk="$1" name="$2"
    local dir="$SYSTEM_APP_DIR/$name"
    local remote
    remote="$STAGING/$(basename "$apk")"

    # --- manifest gate, before anything touches the device ------------------
    print_step "Reading the manifest"
    local facts; facts=$(apk_facts "$apk")
    case "$facts" in
        *ERROR=*)
            print_error "Could not read the manifest: ${facts#*ERROR=}"
            print_warning "Refusing to install an APK whose home declaration cannot be checked"
            return 1
            ;;
    esac
    if [[ "$facts" == *"HOME=yes"* ]]; then
        if [[ "$ALLOW_HOME" != true ]]; then
            print_error "This APK declares CATEGORY_HOME or CATEGORY_SETUP_WIZARD"
            print_warning "On this firmware a wrong home candidate stops the device booting."
            print_warning "See docs/BOOT_DEADLOCK.md. Pass --allow-home if you mean it."
            return 1
        fi
        print_warning "APK claims the home intent and --allow-home was given"
    else
        print_success "Does not claim the home intent"
    fi

    local pkg; pkg=$(sed -n 's/^PKG=//p' <<<"$facts")
    if [[ -z "$pkg" ]]; then
        print_error "Could not read the package name from the manifest"
        return 1
    fi
    print_status "Package: $pkg"

    # An existing copy elsewhere would be shadowed rather than replaced, and the
    # operator would be looking at the old code wondering why nothing changed.
    local existing
    existing=$(adb_root_exec "dumpsys package $pkg" 2>/dev/null | tr -d '\r' \
               | sed -n 's/.*codePath=\(.*\)/\1/p' | head -1) || true
    if [[ -n "$existing" && "$existing" != "$dir" ]]; then
        print_warning "$pkg is already installed at $existing"
        print_warning "Installing to $dir as well would leave two copies on the device"
        read -r -p "Continue anyway? [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]] || { print_status "Cancelled"; return 1; }
    fi

    # --- ABI ---------------------------------------------------------------
    local apk_abi_list dev_abis isa="" chosen=""
    apk_abi_list=$(apk_abis "$apk")
    if [[ -n "$apk_abi_list" ]]; then
        dev_abis=$(adb shell 'getprop ro.product.cpu.abilist' 2>/dev/null | tr -d '\r')
        local d
        for d in ${dev_abis//,/ }; do
            if grep -qx "$d" <<<"$apk_abi_list"; then chosen="$d"; break; fi
        done
        if [[ -z "$chosen" ]]; then
            print_error "APK has native code for [$(echo "$apk_abi_list" | tr '\n' ' ')]"
            print_error "but this device is [$dev_abis]. Get the matching build."
            return 1
        fi
        isa=$(abi_to_isa "$chosen")
        [[ -n "$isa" ]] || { print_error "No library directory known for ABI $chosen"; return 1; }
        print_success "Native code: $chosen -> lib/$isa"
    else
        print_status "No native libraries in this APK"
    fi

    # --- try the clean path first ------------------------------------------
    print_step "Trying a normal install"
    local out; out=$(adb install -r "$apk" 2>&1 || true)
    if [[ "$out" == *Success* ]]; then
        print_success "Installed normally - no $SYSTEM_APP_DIR copy needed"
        return 0
    fi
    print_warning "Refused: $(grep -oE 'Failure \[[A-Z_]+\]' <<<"$out" | head -1)"
    print_status "Falling back to $dir"

    # --- stage --------------------------------------------------------------
    # Staged through $STAGING because `adb push` runs as the shell user, which
    # cannot write /system even when it is mounted rw.
    print_step "Uploading"
    adb push "$apk" "$remote" >/dev/null || { print_error "Could not upload to $remote"; return 1; }

    local want; want=$(local_md5 "$apk")
    local got; got=$(adb_root_exec "md5sum $remote" | awk '{print $1}')
    if [[ "$want" != "$got" ]]; then
        print_error "Upload corrupted ($want vs $got)"
        adb_root_exec "rm -f $remote" >/dev/null 2>&1 || true
        return 1
    fi

    # --- unpack native libraries locally ------------------------------------
    local libtmp=""
    if [[ -n "$isa" ]]; then
        libtmp=$(mktemp -d)
        # -j flattens lib/<abi>/ away, which is what the destination wants.
        unzip -o -j "$apk" "lib/$chosen/*" -d "$libtmp" >/dev/null 2>&1 || true
        if ! compgen -G "$libtmp/*.so" >/dev/null; then
            print_error "Could not unpack lib/$chosen/ out of the APK"
            rm -rf "$libtmp"; return 1
        fi
        print_step "Uploading $(find "$libtmp" -name '*.so' | wc -l | tr -d ' ') native libraries"
        adb_root_exec "rm -rf $STAGING/applibs" >/dev/null 2>&1 || true
        adb shell "mkdir -p $STAGING/applibs" >/dev/null 2>&1 || true
        adb push "$libtmp/." "$STAGING/applibs/" >/dev/null || {
            print_error "Could not upload native libraries"; rm -rf "$libtmp"; return 1; }
    fi

    # --- install into /system ----------------------------------------------
    print_step "Installing into $dir"
    system_rw || { adb_root_exec "rm -f $remote" >/dev/null 2>&1 || true; return 1; }

    adb_root_exec "mkdir -p $dir" >/dev/null || true
    adb_root_exec "cp $remote $dir/$name.apk" >/dev/null || true
    adb_root_exec "chmod 755 $dir" >/dev/null || true
    adb_root_exec "chmod 644 $dir/$name.apk" >/dev/null || true

    if [[ -n "$isa" ]]; then
        adb_root_exec "mkdir -p $dir/lib/$isa" >/dev/null || true
        adb_root_exec "cp $STAGING/applibs/*.so $dir/lib/$isa/" >/dev/null || true
        adb_root_exec "chmod 755 $dir/lib $dir/lib/$isa" >/dev/null || true
        adb_root_exec "chmod 644 $dir/lib/$isa/*.so" >/dev/null || true
    fi
    adb_root_exec "chown -R root:root $dir" >/dev/null || true

    system_ro
    adb_root_exec "rm -f $remote" >/dev/null 2>&1 || true
    adb_root_exec "rm -rf $STAGING/applibs" >/dev/null 2>&1 || true

    # --- verify what actually landed ---------------------------------------
    print_step "Verifying"
    got=$(adb_root_exec "md5sum $dir/$name.apk" | awk '{print $1}')
    if [[ "$want" != "$got" ]]; then
        print_error "APK in $dir does not match the source ($want vs $got)"
        return 1
    fi
    print_success "APK verified"

    if [[ -n "$isa" ]]; then
        local f base rgot rwant bad=0
        for f in "$libtmp"/*.so; do
            base=$(basename "$f")
            rwant=$(local_md5 "$f")
            rgot=$(adb_root_exec "md5sum $dir/lib/$isa/$base" | awk '{print $1}')
            if [[ "$rwant" != "$rgot" ]]; then
                print_error "$base does not match ($rwant vs $rgot)"; bad=1
            fi
        done
        rm -rf "$libtmp"
        [[ "$bad" -eq 0 ]] || return 1
        print_success "Native libraries verified"
    fi

    print_success "Staged. The package registers on the next boot, not before."
    APP_PKG="$pkg"; APP_ISA="$isa"; APP_DIR="$dir"
    return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            --name)       APP_NAME="${2:-}"; shift 2 ;;
            --remove)     REMOVE_PKG="${2:-}"; shift 2 ;;
            --allow-home) ALLOW_HOME=true; shift ;;
            --reboot)     DO_REBOOT="yes"; shift ;;
            --no-reboot)  DO_REBOOT="no"; shift ;;
            -*)           print_error "Unknown option: $1"; usage; exit 1 ;;
            *)            APK="$1"; shift ;;
        esac
    done

    print_header "Install app"

    if [[ -z "$REMOVE_PKG" && -z "$APK" ]]; then usage; exit 1; fi
    if [[ -n "$APK" && ! -f "$APK" ]]; then print_error "No such file: $APK"; exit 1; fi

    for t in unzip python3; do
        command -v "$t" >/dev/null 2>&1 || { print_error "$t is required"; exit 1; }
    done

    require_device true

    if [[ -n "$REMOVE_PKG" ]]; then
        remove_app "$REMOVE_PKG" || exit 1
    else
        [[ -n "$APP_NAME" ]] || APP_NAME=$(default_name_from_apk "$APK")
        APP_PKG=""; APP_ISA=""; APP_DIR=""
        install_app "$APK" "$APP_NAME" || exit 1
        [[ -n "$APP_DIR" ]] || exit 0   # normal install worked; nothing pending
    fi

    if [[ "$DO_REBOOT" == "ask" ]]; then
        read -r -p "Reboot now to finish? [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]] && DO_REBOOT=yes || DO_REBOOT=no
    fi

    if [[ "$DO_REBOOT" != "yes" ]]; then
        print_warning "Not rebooting. The change takes effect on the next boot."
        exit 0
    fi

    reboot_and_wait || exit 1
    check_root_access >/dev/null 2>&1 || true

    if [[ -z "$REMOVE_PKG" && -n "${APP_PKG:-}" ]]; then
        verify_installed "$APP_PKG" "$APP_ISA" "$APP_DIR" || exit 1
    fi
    print_success "Done"
}

main "$@"
