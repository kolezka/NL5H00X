#!/bin/bash
# Record MAKE_BACKUP's output contract without asserting PROJECTOR internals.
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
SANDBOX=$(mktemp -d /tmp/nl5-backup-characterize.XXXXXX) || exit 2
PASS=0 FAIL=0
finish() {
    local rc=$?
    printf 'SUMMARY backup-signal passed=%s failed=%s exit=%s\n' "$PASS" "$FAIL" "$rc"
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
mkdir -p "$OBS" || exit 2
for knob in $(compgen -A variable FAKE_ADB_); do unset "$knob"; done
export FAKE_ADB_SU_MODE=piped
new_state() {
    [[ "$(command -v adb)" == "$ROOT/tests/fake-adb/adb" ]] || { bad 'adb routing'; exit 2; }
    FAKE_ADB_STATE=$(mktemp -d "$SANDBOX/$1.XXXXXX") || exit 2
    export FAKE_ADB_STATE
    "$BASH" "$ROOT/tests/device-emu/seed.sh" "$FAKE_ADB_STATE" > /dev/null || exit 2
}
new_state control
printf '0123456789abcdef\n' > "$FAKE_ADB_STATE/control-seed"
check 'fake control decodes seeded token' test "$(adb __pt_control)" = 'pt-control:fedcba9876543210'
check 'control invocation recorded' grep -Fq '__pt_control' "$FAKE_ADB_STATE/invocations.log"
check 'block fixture verifies through toolkit' "$BASH" "$ROOT/tests/fixtures/block-fixture.sh" "$SANDBOX/fixture"
[[ -f "$SANDBOX/fixture/full-system-backup.img" ]] || exit 2
printf 'MAKE_BACKUP baseline. ANSI removed; sandbox paths and created timestamp normalized.\n' > "$OBS/backup-signal.txt"
printf '\nPROJECTOR progress consumers (source observation, not assertions):\n' >> "$OBS/backup-signal.txt"
awk '(NR >= 145 && NR <= 148) || (NR >= 151 && NR <= 152) || (NR >= 197 && NR <= 198) {printf "%d %s\n", NR, $0}' \
    "$ROOT/scripts/PROJECTOR.sh" >> "$OBS/backup-signal.txt"
for scenario in healthy truncated; do
    new_state "$scenario"
    cp "$SANDBOX/fixture/full-system-backup.img" "$FAKE_ADB_STATE/blockdev" || exit 2
    BACKUP_DIR="$SANDBOX/$scenario-backup"
    export BACKUP_DIR CHUNK_SIZE_MB=2 STREAM_CHUNK_MB=1 STREAM_RETRIES=1 STREAM_STALL_SECS=3
    if [[ "$scenario" == truncated ]]; then
        export FAKE_ADB_NO_EXEC_OUT=1 FAKE_ADB_TRUNCATE_AT=4096 FAKE_ADB_TRUNCATE_MIN_SKIP=2
    fi
    "$BASH_REAL" "$ROOT/scripts/MAKE_BACKUP.sh" > "$SANDBOX/$scenario.raw" 2>&1
    RC=$?
    /usr/bin/python3 - "$SANDBOX/$scenario.raw" "$SANDBOX/$scenario.out" <<'PY'
import re, sys
open(sys.argv[2], 'w').write(re.sub(r'\x1b\[[0-9;]*m', '', open(sys.argv[1]).read()))
PY
    if [[ "$scenario" == healthy ]]; then
        check 'healthy exit zero' test "$RC" = 0
        check 'healthy exact completion signal' grep -Fxq 'BACKUP COMPLETE - Safe to proceed with modifications' "$SANDBOX/$scenario.out"
        check 'healthy final location line' grep -Fxq "[INFO] Backup location: $BACKUP_DIR" "$SANDBOX/$scenario.out"
        check 'healthy streaming total emitted' grep -Fxq '[INFO] Streaming in 1MB blocks (4 total, nothing staged on the device)' "$SANDBOX/$scenario.out"
    else
        check 'truncated exit one' test "$RC" = 1
        check 'truncated exact incomplete signal' grep -Fxq 'BACKUP INCOMPLETE - Do NOT modify system' "$SANDBOX/$scenario.out"
        check 'truncated final location line' grep -Fxq "[INFO] Backup location: $BACKUP_DIR" "$SANDBOX/$scenario.out"
        if grep -Fq 'BACKUP COMPLETE' "$SANDBOX/$scenario.out"; then bad 'truncated falsely announces completion'; else ok 'truncated omits success signal'; fi
    fi
    /usr/bin/python3 - "$scenario" "$RC" "$BACKUP_DIR" "$SANDBOX/$scenario.out" "$SANDBOX" >> "$OBS/backup-signal.txt" <<'PY'
import os, re, sys
scenario, rc, directory, log, sandbox = sys.argv[1:]
text = open(log).read().replace(sandbox, '<SANDBOX>')
lines = [line for line in text.splitlines() if line.strip()]
print('\n[%s] exit=%s' % (scenario, rc))
print('last nonempty line: ' + (lines[-1] if lines else '<none>'))
print('completion signal: ' + '\n'.join(line for line in lines if line.startswith('BACKUP ')))
print('progress producer lines:')
for line in lines:
    if 'Streaming in ' in line or 'Transfer stalled' in line or re.match(r'^\[INFO\]   *[0-9]+%', line):
        print(line)
print('manifest filename: backup-manifest.txt')
manifest = os.path.join(directory, 'backup-manifest.txt')
if os.path.isfile(manifest):
    print(re.sub(r'^created=.*$', 'created=<UTC timestamp>', open(manifest).read(), flags=re.M), end='')
else:
    print('manifest: absent')
print('artifact state (regular files, bytes):')
for name in sorted(os.listdir(directory)):
    path = os.path.join(directory, name)
    if os.path.isfile(path):
        print('%s %s' % (name, os.path.getsize(path)))
PY
    sed "s|$SANDBOX|<SANDBOX>|g" "$SANDBOX/$scenario.out" > "$OBS/backup-$scenario.log"
done
[[ "$FAIL" == 0 ]]
