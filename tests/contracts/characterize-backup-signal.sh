#!/bin/bash
# Record MAKE_BACKUP's output contract without asserting PROJECTOR internals.
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
    CHARACTERIZE_SUPERVISOR_STATE="${CHARACTERIZE_SUPERVISOR_STATE:-$(mktemp /tmp/nl5-backup-supervisor.XXXXXX)}"
    exec /usr/bin/python3 "$CHARACTERIZE_SUPERVISOR" \
        --timeout "${CHARACTERIZE_TIMEOUT_SECS:-240}" --grace "${CHARACTERIZE_TIMEOUT_GRACE:-0.5}" \
        --state "$CHARACTERIZE_SUPERVISOR_STATE" -- "$BASH" "$0" --bounded "$@"
fi
shift
ROOT="${CHARACTERIZE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
EXPECTED="${CHAR_OBSERVATIONS:-$ROOT/tests/contracts/observations}"
SANDBOX=$(mktemp -d /tmp/nl5-backup-characterize.XXXXXX) || exit 2
ACTUAL="$SANDBOX/actual"
PASS=0 FAIL=0
finish() {
    local rc=$?
    printf 'sandbox: %s\n' "$SANDBOX"
    printf 'SUMMARY backup-signal passed=%s failed=%s exit=%s\n' "$PASS" "$FAIL" "$rc"
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
BASH_REAL=$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BASH") || exit 2
for directory in "${BASH_REAL%/*}" /usr/bin /bin /usr/sbin /sbin; do
    [[ ! -e "$directory/adb" ]] || { bad "unexpected adb in $directory"; exit 2; }
done
PATH="$ROOT/tests/fake-adb:${BASH_REAL%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
mkdir -p "$ACTUAL" || exit 2
[[ -d "$EXPECTED" ]] || { bad 'observation baseline directory exists'; exit 2; }
EXPECTED_HASH_BEFORE=$(tree_hash "$EXPECTED") || exit 2
printf 'interpreter: %s:%s\n' "$BASH_REAL" "$BASH_VERSION"
printf 'expected observations sha256(path\\0bytes): %s\n' "$EXPECTED_HASH_BEFORE"
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

run_backup() {
    local scenario="$1"
    new_state "$scenario"
    unset FAKE_ADB_NO_EXEC_OUT FAKE_ADB_TRUNCATE_AT FAKE_ADB_TRUNCATE_MIN_SKIP FAKE_ADB_HANG_STREAM_ONCE
    cp "$SANDBOX/fixture/full-system-backup.img" "$FAKE_ADB_STATE/blockdev" || exit 2
    BACKUP_DIR="$SANDBOX/$scenario-backup"
    export BACKUP_DIR CHUNK_SIZE_MB=2 STREAM_CHUNK_MB=1 STREAM_RETRIES=1 STREAM_STALL_SECS=3
    case "$scenario" in
        truncated)
            export FAKE_ADB_NO_EXEC_OUT=1 FAKE_ADB_TRUNCATE_AT=4096 FAKE_ADB_TRUNCATE_MIN_SKIP=2
            ;;
        stall)
            export FAKE_ADB_HANG_STREAM_ONCE=1 STREAM_RETRIES=2 STREAM_STALL_SECS=2
            ;;
    esac
    "$BASH_REAL" "$ROOT/scripts/MAKE_BACKUP.sh" > "$SANDBOX/$scenario.raw" 2>&1
    RC=$?
    /usr/bin/python3 - "$SANDBOX/$scenario.raw" "$SANDBOX/$scenario.out" "$SANDBOX" <<'PY'
import re
import sys
text = re.sub(r'\x1b\[[0-9;]*m', '', open(sys.argv[1]).read()).replace(sys.argv[3], '<SANDBOX>')
open(sys.argv[2], 'w').write(text)
PY
    cp "$SANDBOX/$scenario.out" "$ACTUAL/backup-$scenario.log"
}

run_backup healthy
check 'healthy exit zero' test "$RC" = 0
check 'healthy exact completion signal' grep -Fxq 'BACKUP COMPLETE - Safe to proceed with modifications' "$SANDBOX/healthy.out"
check 'healthy final location line' grep -Fxq '[INFO] Backup location: <SANDBOX>/healthy-backup' "$SANDBOX/healthy.out"
producer_total=$(grep -ao 'Streaming in [0-9]*MB blocks ([0-9]* total' "$SANDBOX/healthy.out" | tail -1 | grep -o '([0-9]*' | tr -d '(' || true)
producer_done=$(grep -ac '^\[INFO\]   *[0-9]*%' "$SANDBOX/healthy.out" || true)
producer_stalls=$(grep -ac 'Transfer stalled' "$SANDBOX/healthy.out" || true)
printf 'healthy progress inputs: total=%s done=%s stalls=%s\n' "$producer_total" "$producer_done" "$producer_stalls"
check 'healthy producer reports four total blocks' test "$producer_total" = 4
check 'healthy producer emits four completed block lines' test "$producer_done" = 4
check 'healthy producer emits zero stalls' test "$producer_stalls" = 0
check 'healthy exact progress sequence' /usr/bin/python3 - "$SANDBOX/healthy.out" <<'PY'
import re
import sys
values = [int(match.group(1)) for match in re.finditer(r'^\[INFO\]\s+([0-9]+)%', open(sys.argv[1]).read(), re.M)]
raise SystemExit(0 if values == [25, 50, 75, 100] else 1)
PY

run_backup truncated
check 'truncated exit one' test "$RC" = 1
check 'truncated exact incomplete signal' grep -Fxq 'BACKUP INCOMPLETE - Do NOT modify system' "$SANDBOX/truncated.out"
check 'truncated final location line' grep -Fxq '[INFO] Backup location: <SANDBOX>/truncated-backup' "$SANDBOX/truncated.out"
if grep -Fq 'BACKUP COMPLETE' "$SANDBOX/truncated.out"; then bad 'truncated falsely announces completion'; else ok 'truncated omits success signal'; fi

run_backup stall
check 'contained stall recovers successfully' test "$RC" = 0
stall_count=$(grep -ac 'Transfer stalled' "$SANDBOX/stall.out" || true)
printf 'stall progress input: stalls=%s\n' "$stall_count"
check 'contained fixture emits a nonzero stall count' test "$stall_count" -gt 0
check 'stall run completes after retry' grep -Fxq 'BACKUP COMPLETE - Safe to proceed with modifications' "$SANDBOX/stall.out"
check 'stall fixture recorded owned process ids' test -s "$FAKE_ADB_STATE/hang-pids"
if [[ -s "$FAKE_ADB_STATE/hang-pids" ]]; then
    read -r fake_pid sleep_pid < "$FAKE_ADB_STATE/hang-pids"
    if kill -0 "$fake_pid" 2>/dev/null; then bad 'stalled fake adb process reaped'; else ok 'stalled fake adb process reaped'; fi
    if kill -0 "$sleep_pid" 2>/dev/null; then bad 'stalled fake child process reaped'; else ok 'stalled fake child process reaped'; fi
fi

/usr/bin/python3 - "$ACTUAL/backup-signal.txt" "$SANDBOX" <<'PY'
import os
import re
import sys

output, sandbox = sys.argv[1:]
with open(output, 'w') as summary:
    summary.write('MAKE_BACKUP baseline. ANSI removed; sandbox paths and created timestamp normalized.\n')
    summary.write('\nHistorical front-end observation, not a source assertion: the current UI reads the producer strings "Transfer stalled", "Streaming in ... blocks (... total", percentage lines, and "BACKUP COMPLETE".\n')
    for scenario in ('healthy', 'truncated', 'stall'):
        directory = os.path.join(sandbox, scenario + '-backup')
        log = os.path.join(sandbox, scenario + '.out')
        text = open(log).read()
        lines = [line for line in text.splitlines() if line.strip()]
        completion = [line for line in lines if line.startswith('BACKUP ')]
        progress = [line for line in lines if 'Streaming in ' in line or 'Transfer stalled' in line or re.match(r'^\[INFO\]\s+[0-9]+%', line)]
        raw = open(os.path.join(sandbox, scenario + '.raw')).read()
        match = re.search(r'^BACKUP (?:COMPLETE|INCOMPLETE)', re.sub(r'\x1b\[[0-9;]*m', '', raw), re.M)
        rc = 0 if scenario != 'truncated' else 1
        summary.write('\n[%s] exit=%s\n' % (scenario, rc))
        summary.write('last nonempty line: ' + (lines[-1] if lines else '<none>') + '\n')
        summary.write('completion signal: ' + ('\n'.join(completion) if completion else '<none>') + '\n')
        summary.write('progress producer lines:\n')
        for line in progress:
            summary.write(line + '\n')
        summary.write('progress inputs: total=%s done=%s stalls=%s\n' % (
            next((m.group(1) for m in [re.search(r'\(([0-9]+) total', line) for line in progress] if m), '0'),
            sum(1 for line in progress if re.match(r'^\[INFO\]\s+[0-9]+%', line)),
            sum(1 for line in progress if 'Transfer stalled' in line),
        ))
        summary.write('manifest filename: backup-manifest.txt\n')
        manifest = os.path.join(directory, 'backup-manifest.txt')
        if os.path.isfile(manifest):
            summary.write(re.sub(r'^created=.*$', 'created=<UTC timestamp>', open(manifest).read(), flags=re.M))
        else:
            summary.write('manifest: absent\n')
        summary.write('artifact state (regular files, bytes):\n')
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                summary.write('%s %s\n' % (name, os.path.getsize(path)))
PY

compare_fixture backup-signal.txt "$ACTUAL/backup-signal.txt" 'backup signal summary'
compare_fixture backup-healthy.log "$ACTUAL/backup-healthy.log" 'healthy backup log'
compare_fixture backup-truncated.log "$ACTUAL/backup-truncated.log" 'truncated backup log'
compare_fixture backup-stall.log "$ACTUAL/backup-stall.log" 'stall backup log'
check 'expected observations unchanged during normal run' test "$EXPECTED_HASH_BEFORE" = "$(tree_hash "$EXPECTED")"
[[ "$FAIL" == 0 ]]
