#!/bin/bash
# Exercise the shipped entry point, including its embedded AXML decoder.
set -u
if [[ "${1:-}" != --bounded ]]; then
    for timer in /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout; do
        if [[ -x "$timer" ]]; then exec "$timer" -k 2 180 "$BASH" "$0" --bounded "$@"; fi
    done
    "$BASH" "$0" --bounded "$@" & child=$!
    ( sleep 180; kill -TERM "$child" 2>/dev/null ) & watchdog=$!
    wait "$child"; status=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    exit "$status"
fi
shift
ROOT="${CHARACTERIZE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OBS="${CHAR_OBSERVATIONS:-$ROOT/tests/contracts/observations}"
SANDBOX=$(mktemp -d /tmp/nl5-app-characterize.XXXXXX) || exit 2
PASS=0 FAIL=0
finish() {
    local rc=$?
    printf 'SUMMARY app-install passed=%s failed=%s exit=%s\n' "$PASS" "$FAIL" "$rc"
    printf 'sandbox: %s\n' "$SANDBOX"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ok() { printf 'ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
BASH_REAL=$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BASH") || exit 2
for directory in "${BASH_REAL%/*}" /usr/bin /bin /usr/sbin /sbin; do
    [[ ! -e "$directory/adb" ]] || { bad "unexpected adb in $directory"; exit 2; }
done
PATH="$ROOT/tests/fake-adb:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
mkdir -p "$OBS/app-traces" || exit 2
# Remove inherited fault knobs rather than accidentally exercising someone else's scenario.
for knob in $(compgen -A variable FAKE_ADB_); do unset "$knob"; done
export FAKE_ADB_SU_MODE=direct
new_state() {
    local name="$1" profile="${2:-seed}"
    [[ "$(command -v adb)" == "$ROOT/tests/fake-adb/adb" ]] || { bad 'adb routing'; exit 2; }
    FAKE_ADB_STATE=$(mktemp -d "$SANDBOX/$name.XXXXXX") || exit 2
    export FAKE_ADB_STATE
    if [[ "$profile" == seed ]]; then "$BASH" "$ROOT/tests/device-emu/seed.sh" "$FAKE_ADB_STATE" > /dev/null || exit 2; fi
}
new_state control empty
printf '0123456789abcdef\n' > "$FAKE_ADB_STATE/control-seed"
check 'fake control decodes seeded token' test "$(adb __pt_control)" = 'pt-control:fedcba9876543210'
check 'control invocation recorded' grep -Fq '__pt_control' "$FAKE_ADB_STATE/invocations.log"

run_install() {
    local label="$1"; shift
    "$BASH_REAL" -x "$ROOT/scripts/INSTALL_APP.sh" "$@" > "$SANDBOX/$label.raw" 2>&1
    RC=$?
    /usr/bin/python3 - "$SANDBOX/$label.raw" "$SANDBOX/$label.out" "$SANDBOX/$label.facts" <<'PY'
import re, sys
text = re.sub(r'\x1b\[[0-9;]*m', '', open(sys.argv[1]).read())
open(sys.argv[2], 'w').write(text)
match = re.search(r"\+ facts=(?:\$)?'?(PKG=[^\n']*(?:\n|\\n)HOME=(?:yes|no)|ERROR=[^\n']+)", text)
open(sys.argv[3], 'w').write(match.group(1).replace('\\n', '\n') + '\n' if match else '')
PY
    if [[ -f "$FAKE_ADB_STATE/invocations.log" ]]; then
        sed "s|$SANDBOX|<SANDBOX>|g" "$FAKE_ADB_STATE/invocations.log" > "$OBS/app-traces/$label.log"
    else
        : > "$OBS/app-traces/$label.log"
    fi
}
want_call() {
    local argument
    printf adb
    for argument in "$@"; do printf '\t%q' "$argument"; done
    printf '\n'
}
require_trace() {
    want_call devices
    want_call shell "su -c 'whoami'"
}
: > "$OBS/app-install.txt"
for variant in utf16 utf8 home native; do
    new_state "$variant"
    apk="$SANDBOX/$variant.apk"
    /usr/bin/python3 "$ROOT/tests/fixtures/make-apk.py" "$apk" --variant "$variant" --package "com.example.$variant" || exit 2
    # Sidecar only supplies the fake package database; the real parser reads AXML.
    printf 'pkg=com.example.%s\n' "$variant" > "$apk.meta"
    printf 'secure install_non_market_apps 1\n' > "$FAKE_ADB_STATE/settings"
    run_install "$variant" "$apk" --no-reboot
    home=no; [[ "$variant" != home ]] || home=yes
    printf 'PKG=com.example.%s\nHOME=%s\n' "$variant" "$home" > "$SANDBOX/expected-facts"
    check "$variant exact parser facts" cmp -s "$SANDBOX/expected-facts" "$SANDBOX/$variant.facts"
    {
        printf '\n[%s] exit=%s\n' "$variant" "$RC"
        cat "$SANDBOX/$variant.facts"
        grep -E '^\[(INFO|OK|WARN|ERROR)\]' "$SANDBOX/$variant.out"
    } >> "$OBS/app-install.txt"
    require_trace > "$SANDBOX/expected-trace"
    case "$variant" in
        utf16|utf8)
            check "$variant normal fake install exit" test "$RC" = 0
            check "$variant package from script output" grep -Fxq "[INFO] Package: com.example.$variant" "$SANDBOX/$variant.out"
            want_call shell "su -c 'dumpsys package com.example.$variant' 2>&1; echo __RC__=\$?" >> "$SANDBOX/expected-trace"
            want_call install -r "$apk" >> "$SANDBOX/expected-trace"
            ;;
        home)
            check 'home refused without allow flag' test "$RC" = 1
            check 'home refusal text' grep -Fxq '[ERROR] This APK declares CATEGORY_HOME or CATEGORY_SETUP_WIZARD' "$SANDBOX/home.out"
            ;;
        native)
            check 'native mismatch exit' test "$RC" = 1
            check 'native ABI list' grep -Fxq '[ERROR] APK has native code for [x86_64 ]' "$SANDBOX/native.out"
            check 'seed lacks abilist, no abi fallback' grep -Fxq '[ERROR] but this device is []. Get the matching build.' "$SANDBOX/native.out"
            want_call shell "su -c 'dumpsys package com.example.native' 2>&1; echo __RC__=\$?" >> "$SANDBOX/expected-trace"
            want_call shell 'getprop ro.product.cpu.abilist' >> "$SANDBOX/expected-trace"
            ;;
    esac
    check "$variant exact device command trace" cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
done

new_state text
/usr/bin/python3 - "$SANDBOX/text.apk" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('AndroidManifest.xml', '<manifest package="com.example.text"/>')
PY
run_install text "$SANDBOX/text.apk" --no-reboot
check 'plain text manifest rejected' test "$RC" = 1
check 'plain text exact decoder error' grep -Fxq 'ERROR=not-an-android-manifest' "$SANDBOX/text.facts"
check 'plain text refusal from real main' grep -Fxq '[WARN] Refusing to install an APK whose home declaration cannot be checked' "$SANDBOX/text.out"
require_trace > "$SANDBOX/expected-trace"
check 'plain text rejected before mutation' cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
printf '\n[text] exit=%s\n' "$RC" >> "$OBS/app-install.txt"
cat "$SANDBOX/text.facts" >> "$OBS/app-install.txt"

for pkg in com.newlink.wtprovision com.newlink.hisilauncher com.android.tv.settings com.android.settings; do
    new_state "remove-$pkg"
    run_install "remove-$pkg" --remove "$pkg" --no-reboot
    check "$pkg protected removal exit" test "$RC" = 1
    check "$pkg protected refusal text" grep -Fxq "[ERROR] Refusing to remove $pkg - it is required for this device to boot" "$SANDBOX/remove-$pkg.out"
    require_trace > "$SANDBOX/expected-trace"
    check "$pkg requires device before refusal" cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
    grep -E '^\[(INFO|OK|WARN|ERROR)\]' "$SANDBOX/remove-$pkg.out" >> "$OBS/app-install.txt"
done

new_state upload
run_install upload "$SANDBOX/utf16.apk" --name Fixture --no-reboot
check 'unhandled checksum command refuses upload' test "$RC" = 1
want=$(/sbin/md5 -q "$SANDBOX/utf16.apk")
printf 'checksum comparison: local=%s remote=<empty>\n' "$want"
check 'checksum refusal has exact compared values' grep -Fxq "[ERROR] Upload corrupted ($want vs )" "$SANDBOX/upload.out"
check 'staged upload checksum queried' grep -Fq 'md5sum\ /data/local/tmp/utf16.apk' "$FAKE_ADB_STATE/invocations.log"
{
    require_trace
    want_call shell "su -c 'dumpsys package com.example.utf16' 2>&1; echo __RC__=\$?"
    want_call install -r "$SANDBOX/utf16.apk"
    want_call push "$SANDBOX/utf16.apk" /data/local/tmp/utf16.apk
    want_call shell "su -c 'md5sum /data/local/tmp/utf16.apk' 2>&1; echo __RC__=\$?"
    want_call shell "su -c 'rm -f /data/local/tmp/utf16.apk' 2>&1; echo __RC__=\$?"
} > "$SANDBOX/expected-trace"
check 'checksum failure exact trace stops before system write' cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
{
    printf '\n[upload] exit=%s\n' "$RC"
    grep -E '^\[(STEP|INFO|OK|WARN|ERROR)\]' "$SANDBOX/upload.out"
    printf 'Comparison: local_md5(APK) versus first field of root md5sum /data/local/tmp/utf16.apk.\n'
    printf 'MATCH NOT RUN: fake lacks remote md5sum support (sentinel status 127), so got is empty.\n'
    printf 'Source-only match path: no dedicated upload success line; proceeds to Installing into the system directory.\n'
    printf 'Mismatch observed from unsupported checksum command, not corrupted bytes; no corruption knob exists.\n'
} >> "$OBS/app-install.txt"

new_state help empty
"$BASH_REAL" "$ROOT/scripts/INSTALL_APP.sh" --help > "$OBS/install-help.txt" 2>&1
RC=$?
check 'help exits zero' test "$RC" = 0
check 'help starts with Usage' grep -Fxq 'Usage:' "$OBS/install-help.txt"
check 'help needs no device calls' test ! -s "$FAKE_ADB_STATE/invocations.log"
printf '\n[help] exit=%s; empty state; invocations.log absent or empty.\n' "$RC" >> "$OBS/app-install.txt"
[[ "$FAIL" == 0 ]]
