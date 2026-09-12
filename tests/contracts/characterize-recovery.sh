#!/bin/bash
# Generated recovery scripts run only through record-only fake device operations.
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
    CHARACTERIZE_SUPERVISOR_STATE="${CHARACTERIZE_SUPERVISOR_STATE:-$(mktemp /tmp/nl5-recovery-supervisor.XXXXXX)}"
    exec /usr/bin/python3 "$CHARACTERIZE_SUPERVISOR" \
        --timeout "${CHARACTERIZE_TIMEOUT_SECS:-240}" --grace "${CHARACTERIZE_TIMEOUT_GRACE:-0.5}" \
        --state "$CHARACTERIZE_SUPERVISOR_STATE" -- "$BASH" "$0" --bounded "$@"
fi
shift
ROOT="${CHARACTERIZE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
EXPECTED="${CHAR_OBSERVATIONS:-$ROOT/tests/contracts/observations}"
SANDBOX=$(mktemp -d /tmp/nl5-recovery-characterize.XXXXXX) || exit 2
ACTUAL="$SANDBOX/actual"
PASS=0 FAIL=0
finish() {
    local rc=$?
    printf 'sandbox: %s\n' "$SANDBOX"
    printf 'SUMMARY recovery passed=%s failed=%s exit=%s\n' "$PASS" "$FAIL" "$rc"
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
file_sha256() { /usr/bin/shasum -a 256 "$1" | awk '{print $1}'; }
BASH_REAL=$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BASH") || exit 2
for directory in "${BASH_REAL%/*}" /usr/bin /bin /usr/sbin /sbin; do
    [[ ! -e "$directory/adb" ]] || { bad "unexpected adb in $directory"; exit 2; }
done
PATH="$ROOT/tests/fake-adb:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
mkdir -p "$ACTUAL/recovery-traces" "$ACTUAL/recovery-output" || exit 2
[[ -d "$EXPECTED" ]] || { bad 'observation baseline directory exists'; exit 2; }
EXPECTED_HASH_BEFORE=$(tree_hash "$EXPECTED") || exit 2
printf 'interpreter: %s:%s\n' "$BASH_REAL" "$BASH_VERSION"
printf 'expected observations sha256(path\\0bytes): %s\n' "$EXPECTED_HASH_BEFORE"
for knob in $(compgen -A variable FAKE_ADB_); do unset "$knob"; done
export FAKE_ADB_SU_MODE=direct FAKE_ADB_PROPAGATE_RC=1
new_state() {
    local name="$1" profile="${2:-seed}"
    [[ "$(command -v adb)" == "$ROOT/tests/fake-adb/adb" ]] || { bad 'adb routing'; exit 2; }
    FAKE_ADB_STATE=$(mktemp -d "$SANDBOX/$name.XXXXXX") || exit 2
    export FAKE_ADB_STATE
    if [[ "$profile" == seed ]]; then "$BASH" "$ROOT/tests/device-emu/seed.sh" "$FAKE_ADB_STATE" > /dev/null || exit 2; fi
}

# Both block-write forms are probed before generated recovery runs. A host dd
# stub makes a broken interceptor fail without writing even a disposable target.
new_state control empty
printf '0123456789abcdef\n' > "$FAKE_ADB_STATE/control-seed"
mkdir -p "$FAKE_ADB_STATE/dev/block" "$FAKE_ADB_STATE/sdcard" "$SANDBOX/no-write-bin"
printf 'whole target marker\n' > "$FAKE_ADB_STATE/dev/block/mmcblk0"
printf 'partition target marker\n' > "$FAKE_ADB_STATE/dev/block/mmcblk0p20"
printf 'file-input-probe\n' > "$FAKE_ADB_STATE/sdcard/probe.img"
cat > "$SANDBOX/no-write-bin/dd" <<'DD_STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${FAKE_ADB_STATE:?}/host-dd-called"
exit 99
DD_STUB
chmod +x "$SANDBOX/no-write-bin/dd"
control_whole_hash=$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0")
control_partition_hash=$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0p20")
check 'fake control decodes seeded token' test "$(adb __pt_control)" = 'pt-control:fedcba9876543210'
check 'control invocation recorded' grep -Fq '__pt_control' "$FAKE_ADB_STATE/invocations.log"
PATH="$ROOT/tests/fake-adb:$SANDBOX/no-write-bin:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH FAKE_ADB_INTERCEPT_BLOCK_DD=1
hash -r
printf 'record-only-probe' | adb shell "su -c 'dd of=/dev/block/mmcblk0 bs=1'" >/dev/null 2>&1 || true
adb shell "su -c 'dd if=/sdcard/probe.img of=/dev/block/mmcblk0p20 bs=1'" >/dev/null 2>&1 || true
{
    printf '%s\n' 'dd of=/dev/block/mmcblk0 bs=1'
    printf '%s\n' 'dd if=/sdcard/probe.img of=/dev/block/mmcblk0p20 bs=1'
} > "$SANDBOX/expected-block-dd-probe"
probe_ok=1
if [[ -f "$FAKE_ADB_STATE/block-dd.stdin" ]] \
   && cmp -s "$SANDBOX/expected-block-dd-probe" "$FAKE_ADB_STATE/block-dd.log"; then
    ok 'record-only stdin and file-input dd capability probe'
else
    bad 'record-only stdin and file-input dd capability probe'
    probe_ok=0
fi
if [[ -f "$FAKE_ADB_STATE/block-dd.stdin" ]] \
   && grep -Fxq 'record-only-probe' "$FAKE_ADB_STATE/block-dd.stdin"; then
    ok 'record-only probe consumes exact stdin'
else
    bad 'record-only probe consumes exact stdin'
    probe_ok=0
fi
if [[ ! -e "$FAKE_ADB_STATE/host-dd-called" ]]; then
    ok 'record-only probes never reach host dd'
else
    bad 'record-only probes never reach host dd'
    probe_ok=0
fi
if [[ "$control_whole_hash" = "$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0")" \
   && "$control_partition_hash" = "$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0p20")" ]]; then
    ok 'record-only probes leave exact mapped targets unchanged'
else
    bad 'record-only probes leave exact mapped targets unchanged'
    probe_ok=0
fi
PATH="$ROOT/tests/fake-adb:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
unset FAKE_ADB_INTERCEPT_BLOCK_DD
[[ "$probe_ok" == 1 ]] || exit 2

"$BASH" "$ROOT/tests/fixtures/block-fixture.sh" "$SANDBOX/fixture" > "$SANDBOX/fixture-paths" || exit 2
new_state generate
cp "$SANDBOX/fixture/full-system-backup.img" "$FAKE_ADB_STATE/blockdev" || exit 2
export BACKUP_DIR="$SANDBOX/generated" STREAM_CHUNK_MB=1 STREAM_STALL_SECS=3 STREAM_RETRIES=1
"$BASH_REAL" "$ROOT/scripts/MAKE_BACKUP.sh" > "$SANDBOX/generate.log" 2>&1
RC=$?
check 'real MAKE_BACKUP generates recovery artifact' test "$RC" = 0
[[ -f "$BACKUP_DIR/RESTORE.sh" && -f "$BACKUP_DIR/reset-launcher.sh" ]] || exit 2
cp -R "$BACKUP_DIR" "$SANDBOX/pristine" || exit 2
check 'generated RESTORE syntax' /bin/bash -n "$BACKUP_DIR/RESTORE.sh"
check 'generated reset syntax' /bin/bash -n "$BACKUP_DIR/reset-launcher.sh"
/usr/bin/python3 - "$BACKUP_DIR" "$ACTUAL/recovery-menu.txt" <<'PY'
import json
import os
import re
import sys
source = open(os.path.join(sys.argv[1], 'RESTORE.sh')).read()
with open(sys.argv[2], 'w') as out:
    out.write('Generated by a complete MAKE_BACKUP.sh run, not extracted functions.\n')
    out.write('Menu strings, in order (JSON quotes retain spaces):\n')
    for line in source.splitlines():
        if line.startswith('echo "Options:') or re.match(r'echo "  [1-4q]\. ', line):
            out.write(json.dumps(line[6:-1]) + '\n')
    out.write('Prompt strings (source; read -p is silent on piped stdin):\n')
    for prompt in re.findall(r'read -p "([^"]*)"', source):
        out.write(json.dumps(prompt) + '\n')
    out.write('reset-launcher.sh has no menu or prompt.\n')
PY
compare_fixture recovery-menu.txt "$ACTUAL/recovery-menu.txt" 'recovery menu and prompts'

want_call() {
    local argument
    printf adb
    for argument in "$@"; do printf '\t%q' "$argument"; done
    printf '\n'
}
expected_trace() {
    case "$case_name" in
        1-success) want_call shell cmd package set-home-activity com.newlink.hisilauncher/.WizardAciticity ;;
        1-failure) want_call shell cmd package set-home-activity 'Unknown command: get-home-activity' ;;
        2-success|2-failure) want_call restore complete-app-backup.ab ;;
        2-missing|4-failure|q) : ;;
        3-success|3-failure)
            want_call push system.img /sdcard/
            want_call shell "su -c 'dd if=/sdcard/system.img of=/dev/block/mmcblk0p20 bs=1048576'"
            want_call shell rm -f /sdcard/system.img
            ;;
        4-success)
            want_call push full-system-backup.img /sdcard/
            want_call reboot
            ;;
        4-fallback)
            want_call push full-system-backup.img /sdcard/
            want_call shell "su -c 'dd of=/dev/block/mmcblk0 bs=1048576'"
            want_call reboot
            ;;
        reset-success|reset-failure)
            want_call shell cmd package set-home-activity com.newlink.hisilauncher
            want_call shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
            ;;
    esac
}

for case_name in 1-success 1-failure 2-success 2-failure 2-missing 3-success 3-failure 4-success 4-failure 4-fallback q reset-success reset-failure; do
    for location in in-place relocated; do
        new_state "$case_name-$location"
        export FAKE_ADB_SU_MODE=direct FAKE_ADB_PROPAGATE_RC=1 FAKE_ADB_NO_DEVICE=0
        unset FAKE_ADB_INTERCEPT_BLOCK_DD FAKE_ADB_INTERCEPT_DD_RC FAKE_ADB_PUSH_FAIL_TARGET FAKE_ADB_PUSH_FAIL_RC FAKE_ADB_RESTORE_RC
        cp "$SANDBOX/fixture/full-system-backup.img" "$FAKE_ADB_STATE/blockdev" || exit 2
        mkdir -p "$FAKE_ADB_STATE/dev/block" || exit 2
        printf 'whole target marker\n' > "$FAKE_ADB_STATE/dev/block/mmcblk0"
        printf 'partition target marker\n' > "$FAKE_ADB_STATE/dev/block/mmcblk0p20"
        block_hash_before=$(file_sha256 "$FAKE_ADB_STATE/blockdev")
        whole_target_hash_before=$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0")
        partition_target_hash_before=$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0p20")
        rm -rf "$BACKUP_DIR"
        mkdir -p "$BACKUP_DIR" || exit 2
        cp -R "$SANDBOX/pristine/." "$BACKUP_DIR/" || exit 2
        case "$case_name" in
            1-success) printf 'com.newlink.hisilauncher/.WizardAciticity\n' > "$BACKUP_DIR/current-home-activity.txt" ;;
            2-success) export FAKE_ADB_RESTORE_RC=0 ;;
            2-failure) export FAKE_ADB_RESTORE_RC=7 ;;
            2-missing) rm "$BACKUP_DIR/complete-app-backup.ab" ;;
            3-success)
                head -c 4096 "$SANDBOX/fixture/full-system-backup.img" > "$BACKUP_DIR/system.img"
                rm "$BACKUP_DIR/backup-manifest.txt"
                export FAKE_ADB_INTERCEPT_BLOCK_DD=1 FAKE_ADB_INTERCEPT_DD_RC=0
                ;;
            3-failure)
                head -c 4096 "$SANDBOX/fixture/full-system-backup.img" > "$BACKUP_DIR/system.img"
                rm "$BACKUP_DIR/backup-manifest.txt"
                export FAKE_ADB_INTERCEPT_BLOCK_DD=1 FAKE_ADB_INTERCEPT_DD_RC=23
                ;;
            4-failure) rm "$BACKUP_DIR/full-system-backup.img" ;;
            4-fallback)
                export FAKE_ADB_INTERCEPT_BLOCK_DD=1 FAKE_ADB_INTERCEPT_DD_RC=0
                export FAKE_ADB_PUSH_FAIL_TARGET=/sdcard/ FAKE_ADB_PUSH_FAIL_RC=19
                ;;
            reset-failure) printf 'com.newlink.hisilauncher\n' > "$FAKE_ADB_STATE/packages_disabled" ;;
        esac
        run_dir="$BACKUP_DIR"
        if [[ "$location" == relocated ]]; then
            run_dir=$(mktemp -d "$SANDBOX/relocated.XXXXXX") || exit 2
            cp -R "$BACKUP_DIR/." "$run_dir/" || exit 2
        fi
        script=RESTORE.sh
        [[ "$case_name" != reset-* ]] || script=reset-launcher.sh
        option="${case_name%%-*}"
        printf '%s\nRESTORE\n' "$option" > "$SANDBOX/input"
        ( cd "$run_dir" && "$BASH_REAL" "./$script" < "$SANDBOX/input" ) > "$SANDBOX/output.raw" 2>&1
        RC=$?
        /usr/bin/python3 - "$SANDBOX/output.raw" "$SANDBOX/output" "$SANDBOX" <<'PY'
import re
import sys
text = re.sub(r'\x1b\[[0-9;]*m', '', open(sys.argv[1]).read()).replace(sys.argv[3], '<SANDBOX>')
open(sys.argv[2], 'w').write(text)
PY
        expected_trace > "$SANDBOX/expected-trace"
        if [[ -f "$FAKE_ADB_STATE/invocations.log" ]]; then
            cp "$FAKE_ADB_STATE/invocations.log" "$SANDBOX/trace"
        else
            : > "$SANDBOX/trace"
        fi
        check "$case_name $location exact command trace" cmp -s "$SANDBOX/expected-trace" "$SANDBOX/trace"
        expected_rc=0
        [[ "$case_name" != 4-failure ]] || expected_rc=1
        check "$case_name $location exit $expected_rc" test "$RC" = "$expected_rc"
        check "$case_name $location fake source block hash unchanged" test "$block_hash_before" = "$(file_sha256 "$FAKE_ADB_STATE/blockdev")"
        check "$case_name $location whole-device target hash unchanged" test "$whole_target_hash_before" = "$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0")"
        check "$case_name $location partition target hash unchanged" test "$partition_target_hash_before" = "$(file_sha256 "$FAKE_ADB_STATE/dev/block/mmcblk0p20")"
        case "$case_name" in
            1-success) check "$case_name $location accepted launcher" grep -Fxq 'Success' "$SANDBOX/output" ;;
            1-failure)
                check "$case_name $location saved diagnostic reaches fake" grep -Fxq 'Error: component get-home-activity not found' "$SANDBOX/output"
                check "$case_name $location still claims success" grep -Fxq 'Launcher reset' "$SANDBOX/output"
                ;;
            2-success)
                check "$case_name $location restore succeeds" grep -Fxq 'restore completed' "$SANDBOX/output"
                check "$case_name $location no masked missing message" test "$(grep -Fc 'No app backup found' "$SANDBOX/output")" = 0
                check "$case_name $location restore metadata captured" test -s "$FAKE_ADB_STATE/restore.log"
                ;;
            2-failure)
                check "$case_name $location configured restore failure visible" grep -Fxq 'adb: restore failed with configured rc 7' "$SANDBOX/output"
                check "$case_name $location production masks failure as missing" grep -Fxq 'No app backup found' "$SANDBOX/output"
                ;;
            2-missing)
                check "$case_name $location missing app backup" grep -Fxq 'No app backup found' "$SANDBOX/output"
                check "$case_name $location makes no restore call" test ! -s "$SANDBOX/trace"
                ;;
            3-success)
                check "$case_name $location block dd argv captured" grep -Fxq "dd if=/sdcard/system.img of=/dev/block/mmcblk0p20 bs=1048576" "$FAKE_ADB_STATE/block-dd.log"
                check "$case_name $location no stdin payload" test ! -e "$FAKE_ADB_STATE/block-dd.stdin"
                ;;
            3-failure)
                check "$case_name $location configured dd failure visible" grep -Fxq 'fake-adb: intercepted block dd failed with configured rc 23' "$SANDBOX/output"
                check "$case_name $location still claims restored" grep -Fxq 'System partition restored' "$SANDBOX/output"
                ;;
            4-success)
                check "$case_name $location fake reboot recorded" grep -Fxq '1' "$FAKE_ADB_STATE/reboots"
                check "$case_name $location no restore write issued" test ! -e "$FAKE_ADB_STATE/block-dd.log"
                ;;
            4-failure) check "$case_name $location missing whole image" grep -Fxq 'No full-system-backup.img here' "$SANDBOX/output" ;;
            4-fallback)
                check "$case_name $location configured push failure visible" grep -Fxq 'adb: configured push failure for /sdcard/ (rc 19)' "$SANDBOX/output"
                check "$case_name $location enters streaming fallback" grep -Fxq 'Streaming restore...' "$SANDBOX/output"
                check "$case_name $location stdin fallback payload captured" cmp -s "$run_dir/full-system-backup.img" "$FAKE_ADB_STATE/block-dd.stdin"
                payload_bytes=$(wc -c < "$FAKE_ADB_STATE/block-dd.stdin" | tr -d ' ')
                payload_hash=$(file_sha256 "$FAKE_ADB_STATE/block-dd.stdin")
                source_hash=$(file_sha256 "$run_dir/full-system-backup.img")
                check "$case_name $location captured payload byte count" test "$payload_bytes" = 4194304
                check "$case_name $location captured payload digest" test "$payload_hash" = "$source_hash"
                check "$case_name $location current reboot still occurs" grep -Fxq '1' "$FAKE_ADB_STATE/reboots"
                ;;
            reset-failure)
                check "$case_name $location disabled launcher refused" grep -Fxq 'Error: package com.newlink.hisilauncher is disabled' "$SANDBOX/output"
                check "$case_name $location still claims default" grep -Fxq 'Launcher reset to default' "$SANDBOX/output"
                ;;
        esac
        if [[ "$location" == in-place ]]; then
            cp "$SANDBOX/trace" "$ACTUAL/recovery-traces/$case_name.log"
            { printf 'exit=%s\n' "$RC"; cat "$SANDBOX/output"; } > "$ACTUAL/recovery-output/$case_name.txt"
        else
            check "$case_name relocated trace equals in-place" cmp -s "$ACTUAL/recovery-traces/$case_name.log" "$SANDBOX/trace"
            check "$case_name relocated output equals in-place" cmp -s "$ACTUAL/recovery-output/$case_name.txt" <( { printf 'exit=%s\n' "$RC"; cat "$SANDBOX/output"; } )
            cp "$SANDBOX/trace" "$ACTUAL/recovery-traces/$case_name-relocated.log"
        fi
    done
done

cat > "$ACTUAL/recovery-hazards.md" <<'EOF'
## Recovery baseline hazards

These traces describe fake execution, not proof of a working hardware restore. Every block-target `dd` was intercepted before a write, and each scenario kept the source block plus both exact mapped target hashes unchanged. The generated directory was run in place and from a copied fresh path.

- Option 1 forwards the saved launcher text without validation. A saved `Unknown command: get-home-activity` diagnostic reaches `set-home-activity`; the command fails, but the script prints `Launcher reset` and exits zero.
- Option 2 invokes `adb restore` when the file exists. A configured restore failure is masked as `No app backup found` and exits zero. A missing file makes no restore call.
- Option 3 accepts a 4096-byte `system.img` without a manifest or typed confirmation. It issues a block-target `dd`; a configured nonzero `dd` result is ignored, then the script prints `System partition restored` and exits zero.
- Option 4 verifies only image length. A successful push is followed by reboot without any restore write. A configured failed push reaches the stdin whole-device `dd` fallback; the fake consumed all 4194304 bytes with a matching digest, performed no block write, and the script still rebooted.
- Quit has no failing action, so it has one trace only. `reset-launcher.sh` runs both commands and reports success even when the launcher reset command fails.

The recovery HOLD remains open. These are characterization results, not endorsements of the production algorithm.
EOF

compare_fixture recovery-hazards.md "$ACTUAL/recovery-hazards.md" 'recovery hazards'
for output in "$ACTUAL"/recovery-output/*.txt; do
    compare_fixture "recovery-output/${output##*/}" "$output" "recovery output ${output##*/}"
done
for trace in "$ACTUAL"/recovery-traces/*.log; do
    compare_fixture "recovery-traces/${trace##*/}" "$trace" "recovery trace ${trace##*/}"
done
check 'expected observations unchanged during normal run' test "$EXPECTED_HASH_BEFORE" = "$(tree_hash "$EXPECTED")"
[[ "$FAIL" == 0 ]]
