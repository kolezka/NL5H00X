#!/bin/bash
# Exercise the shipped entry point, including its embedded AXML decoder.
set -u
if [[ "${1:-}" != --bounded ]]; then
    CHARACTERIZE_ROOT_RESOLVED="${CHARACTERIZE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
    if [[ -n "${PT_CONTROL_DIR:-}" ]]; then
        CHARACTERIZE_SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/${0##*/}"
        CHARACTERIZE_SUITE="${CHARACTERIZE_SCRIPT_PATH#$CHARACTERIZE_ROOT_RESOLVED/tests/}"
        CHARACTERIZE_OUTER_STATE="$PT_CONTROL_DIR/${CHARACTERIZE_SUITE//\//_}.supervisor.log"
        CHARACTERIZE_PGID=$(/bin/ps -o pgid= -p $$ | tr -d ' ')
        for CHARACTERIZE_WAIT in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            grep -q "^spawn supervisor=.* pgid=$CHARACTERIZE_PGID$" "$CHARACTERIZE_OUTER_STATE" 2>/dev/null && \
                exec "$BASH" "$0" --bounded "$@"
            sleep 0.05
        done
        echo 'could not verify the aggregate runner supervisor boundary' >&2
        exit 2
    fi
    CHARACTERIZE_SUPERVISOR="${PT_TEST_SUPERVISOR:-$CHARACTERIZE_ROOT_RESOLVED/tests/local/supervise.py}"
    CHARACTERIZE_SUPERVISOR_STATE="${CHARACTERIZE_SUPERVISOR_STATE:-$(mktemp /tmp/nl5-app-supervisor.XXXXXX)}"
    exec /usr/bin/python3 "$CHARACTERIZE_SUPERVISOR" \
        --timeout "${CHARACTERIZE_TIMEOUT_SECS:-180}" --grace "${CHARACTERIZE_TIMEOUT_GRACE:-0.5}" \
        --state "$CHARACTERIZE_SUPERVISOR_STATE" -- "$BASH" "$0" --bounded "$@"
fi
shift
ROOT="${CHARACTERIZE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
EXPECTED="${CHAR_OBSERVATIONS:-$ROOT/tests/contracts/observations}"
SANDBOX=$(mktemp -d /tmp/nl5-app-characterize.XXXXXX) || exit 2
ACTUAL="$SANDBOX/actual"
PASS=0 FAIL=0
finish() {
    local rc=$?
    printf 'sandbox: %s\n' "$SANDBOX"
    printf 'SUMMARY app-install passed=%s failed=%s exit=%s\n' "$PASS" "$FAIL" "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ok() { printf 'ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
tree_hash() {
    /usr/bin/python3 - "$1" <<'PY'
import hashlib
import os
import sys

root = os.path.realpath(sys.argv[1])
digest = hashlib.sha256()
for directory, directories, files in os.walk(root):
    directories.sort()
    for name in sorted(files):
        path = os.path.join(directory, name)
        relative = os.path.relpath(path, root).replace(os.sep, '/')
        digest.update(relative.encode('utf-8') + b'\0')
        with open(path, 'rb') as source:
            for block in iter(lambda: source.read(65536), b''):
                digest.update(block)
print(digest.hexdigest())
PY
}
compare_fixture() {
    local relative="$1" actual="$2" label="$3" expected
    expected="$EXPECTED/$relative"
    if [[ ! -f "$expected" ]]; then
        bad "$label baseline exists: $relative"
        return
    fi
    if cmp -s "$expected" "$actual"; then
        ok "$label matches immutable baseline"
    else
        bad "$label matches immutable baseline"
        diff -u "$expected" "$actual" || true
    fi
}
file_md5() { /sbin/md5 -q "$1"; }
BASH_REAL=$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BASH") || exit 2
for directory in "${BASH_REAL%/*}" /usr/bin /bin /usr/sbin /sbin; do
    [[ ! -e "$directory/adb" ]] || { bad "unexpected adb in $directory"; exit 2; }
done
PATH="$ROOT/tests/fake-adb:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
mkdir -p "$ACTUAL/app-traces" || exit 2
[[ -d "$EXPECTED" ]] || { bad 'observation baseline directory exists'; exit 2; }
EXPECTED_HASH_BEFORE=$(tree_hash "$EXPECTED") || exit 2
printf 'interpreter: %s:%s\n' "$BASH_REAL" "$BASH_VERSION"
printf 'expected observations sha256(path\\0bytes): %s\n' "$EXPECTED_HASH_BEFORE"
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
import re
import sys

text = re.sub(r'\x1b\[[0-9;]*m', '', open(sys.argv[1]).read())
open(sys.argv[2], 'w').write(text)
match = re.search(r"\+ facts=(?:\$)?'?(PKG=[^\n']*(?:\n|\\n)HOME=(?:yes|no)|ERROR=[^\n']+)", text)
open(sys.argv[3], 'w').write(match.group(1).replace('\\n', '\n') + '\n' if match else '')
PY
    if [[ -f "$FAKE_ADB_STATE/invocations.log" ]]; then
        sed "s|$SANDBOX|<SANDBOX>|g" "$FAKE_ADB_STATE/invocations.log" > "$ACTUAL/app-traces/$label.log"
    else
        : > "$ACTUAL/app-traces/$label.log"
    fi
}
append_case() {
    local label="$1"
    {
        printf '\n[%s] exit=%s\n' "$label" "$RC"
        cat "$SANDBOX/$label.facts"
        grep -E '^\[(STEP|INFO|OK|WARN|ERROR)\]' "$SANDBOX/$label.out" || true
    } >> "$ACTUAL/app-install.txt"
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
: > "$ACTUAL/app-install.txt"
for variant in utf16 utf8 home native; do
    new_state "$variant"
    apk="$SANDBOX/$variant.apk"
    /usr/bin/python3 "$ROOT/tests/fixtures/make-apk.py" "$apk" --variant "$variant" --package "com.example.$variant" || exit 2
    # Sidecar only supplies the fake package database; the real parser reads AXML.
    printf 'pkg=com.example.%s\n' "$variant" > "$apk.meta"
    printf 'secure install_non_market_apps 1\n' > "$FAKE_ADB_STATE/settings"
    if [[ "$variant" == native ]]; then
        printf 'ro.product.cpu.abilist=armeabi-v7a\n' >> "$FAKE_ADB_STATE/props"
    fi
    run_install "$variant" "$apk" --no-reboot
    home=no; [[ "$variant" != home ]] || home=yes
    printf 'PKG=com.example.%s\nHOME=%s\n' "$variant" "$home" > "$SANDBOX/expected-facts"
    check "$variant exact parser facts" cmp -s "$SANDBOX/expected-facts" "$SANDBOX/$variant.facts"
    append_case "$variant"
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
            check 'native incompatible nonempty device ABI' grep -Fxq '[ERROR] but this device is [armeabi-v7a]. Get the matching build.' "$SANDBOX/native.out"
            want_call shell "su -c 'dumpsys package com.example.native' 2>&1; echo __RC__=\$?" >> "$SANDBOX/expected-trace"
            want_call shell 'getprop ro.product.cpu.abilist' >> "$SANDBOX/expected-trace"
            ;;
    esac
    check "$variant exact device command trace" cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
done

new_state native-empty
printf 'secure install_non_market_apps 1\n' > "$FAKE_ADB_STATE/settings"
run_install native-empty "$SANDBOX/native.apk" --no-reboot
check 'native empty ABI legacy exit' test "$RC" = 1
check 'native empty ABI legacy observation' grep -Fxq '[ERROR] but this device is []. Get the matching build.' "$SANDBOX/native-empty.out"
append_case native-empty
require_trace > "$SANDBOX/expected-trace"
want_call shell "su -c 'dumpsys package com.example.native' 2>&1; echo __RC__=\$?" >> "$SANDBOX/expected-trace"
want_call shell 'getprop ro.product.cpu.abilist' >> "$SANDBOX/expected-trace"
check 'native empty exact device command trace' cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"

new_state text
/usr/bin/python3 - "$SANDBOX/text.apk" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('AndroidManifest.xml', '<manifest package="com.example.text"/>')
PY
run_install text "$SANDBOX/text.apk" --no-reboot
check 'plain text manifest rejected' test "$RC" = 1
check 'plain text exact decoder error' grep -Fxq 'ERROR=not-an-android-manifest' "$SANDBOX/text.facts"
check 'plain text refusal from real main' grep -Fxq '[WARN] Refusing to install an APK whose home declaration cannot be checked' "$SANDBOX/text.out"
require_trace > "$SANDBOX/expected-trace"
check 'plain text rejected before mutation' cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
append_case text

for pkg in com.newlink.wtprovision com.newlink.hisilauncher com.android.tv.settings com.android.settings; do
    label="remove-$pkg"
    new_state "$label"
    run_install "$label" --remove "$pkg" --no-reboot
    check "$pkg protected removal exit" test "$RC" = 1
    check "$pkg protected refusal text" grep -Fxq "[ERROR] Refusing to remove $pkg - it is required for this device to boot" "$SANDBOX/$label.out"
    require_trace > "$SANDBOX/expected-trace"
    check "$pkg requires device before refusal" cmp -s "$SANDBOX/expected-trace" "$FAKE_ADB_STATE/invocations.log"
    append_case "$label"
done

new_state upload-success
export FAKE_ADB_REMOTE_MD5=1
unset FAKE_ADB_CORRUPT_PUSH_TARGET
run_install upload-success "$SANDBOX/utf16.apk" --name Fixture --no-reboot
want=$(file_md5 "$SANDBOX/utf16.apk")
staged_hash=$(awk -F '\t' '$1=="/data/local/tmp/utf16.apk" {print $2; exit}' "$FAKE_ADB_STATE/remote-md5.log" 2>/dev/null || true)
final_hash=$(awk -F '\t' '$1=="/system/app/Fixture/Fixture.apk" {print $2; exit}' "$FAKE_ADB_STATE/remote-md5.log" 2>/dev/null || true)
printf 'checksums: local=%s staged=%s final=%s\n' "$want" "$staged_hash" "$final_hash"
check 'upload success exits zero' test "$RC" = 0
check 'staged checksum is nonempty and matches' test -n "$staged_hash" -a "$staged_hash" = "$want"
check 'final checksum is nonempty and matches' test -n "$final_hash" -a "$final_hash" = "$want"
check 'verified APK exists in fake system state' cmp -s "$SANDBOX/utf16.apk" "$FAKE_ADB_STATE/system/app/Fixture/Fixture.apk"
check 'successful stage cleaned up' test ! -e "$FAKE_ADB_STATE/data/local/tmp/utf16.apk"
check 'success reports final verification' grep -Fxq '[OK] APK verified' "$SANDBOX/upload-success.out"
append_case upload-success
printf 'CHECKSUM local=%s staged=%s final=%s\n' "$want" "$staged_hash" "$final_hash" >> "$ACTUAL/app-install.txt"

new_state upload-corrupt
export FAKE_ADB_REMOTE_MD5=1 FAKE_ADB_CORRUPT_PUSH_TARGET=/data/local/tmp/utf16.apk
run_install upload-corrupt "$SANDBOX/utf16.apk" --name Fixture --no-reboot
corrupt_hash=$(awk -F '\t' '$1=="/data/local/tmp/utf16.apk" {print $2; exit}' "$FAKE_ADB_STATE/remote-md5.log" 2>/dev/null || true)
printf 'corruption: local=%s staged=%s\n' "$want" "$corrupt_hash"
check 'corrupt upload exits one' test "$RC" = 1
check 'corrupt staged checksum is nonempty' test -n "$corrupt_hash"
check 'corrupt staged checksum differs from source' test "$corrupt_hash" != "$want"
check 'corrupt upload error compares real hashes' grep -Fxq "[ERROR] Upload corrupted ($want vs $corrupt_hash)" "$SANDBOX/upload-corrupt.out"
check 'corrupt stage cleaned before placement' test ! -e "$FAKE_ADB_STATE/data/local/tmp/utf16.apk"
check 'corrupt upload never creates system directory' test ! -e "$FAKE_ADB_STATE/system/app/Fixture"
append_case upload-corrupt
printf 'CHECKSUM local=%s staged=%s result=refused-before-placement\n' "$want" "$corrupt_hash" >> "$ACTUAL/app-install.txt"
unset FAKE_ADB_REMOTE_MD5 FAKE_ADB_CORRUPT_PUSH_TARGET

new_state help empty
"$BASH_REAL" "$ROOT/scripts/INSTALL_APP.sh" --help > "$ACTUAL/install-help.txt" 2>&1
RC=$?
check 'help exits zero' test "$RC" = 0
check 'help starts with Usage' grep -Fxq 'Usage:' "$ACTUAL/install-help.txt"
check 'help needs no device calls' test ! -s "$FAKE_ADB_STATE/invocations.log"
printf '\n[help] exit=%s; empty state; invocations.log absent or empty.\n' "$RC" >> "$ACTUAL/app-install.txt"

compare_fixture app-install.txt "$ACTUAL/app-install.txt" 'app output'
compare_fixture install-help.txt "$ACTUAL/install-help.txt" 'install help'
for trace in "$ACTUAL"/app-traces/*.log; do
    compare_fixture "app-traces/${trace##*/}" "$trace" "app trace ${trace##*/}"
done
check 'expected observations unchanged during normal run' test "$EXPECTED_HASH_BEFORE" = "$(tree_hash "$EXPECTED")"
[[ "$FAIL" == 0 ]]
