#!/bin/bash
# Standalone transport contracts. All device traffic uses the fake or local stubs.
set -u

TEST_DIR=${BASH_SOURCE[0]%/*}
[[ "$TEST_DIR" == /* ]] || TEST_DIR="$PWD/$TEST_DIR"
REPO_ROOT=${TEST_DIR%/tests/contracts}
MODULE_DIR=${PT_TEST_TRANSPORT_MODULE_DIR:-$REPO_ROOT/scripts/lib/transport}
PATH='/usr/bin:/bin:/usr/sbin:/sbin'
export PATH
# Homebrew's shared bin contains adb; use the interpreter's real directory.
BASH_BIN=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$BASH") || exit 1
if [[ -x "${BASH_BIN%/*}/adb" ]]; then
    printf 'FAIL: interpreter directory must contain no adb\n'
    exit 1
fi
PATH="$PATH:${BASH_BIN%/*}"
export PATH
PASS=0
FAIL=0

ok() { printf 'ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() {
    local name=$1
    shift
    if ( "$@" ); then ok "$name"; else bad "$name"; fi
}

# The parent bounds this child in its own process group, including descendants.
if [[ "${1:-}" == --stall-child ]]; then
    source "$MODULE_DIR/adb.sh" || exit 1
    adb_t_root_probe || exit 1
    adb_t_root_stream_watched 'dd if=/dev/block/mmcblk0 bs=4096' "$SANDBOX/stalled.bin" 2 \
        > "$SANDBOX/stalled.stdout" 2> "$SANDBOX/stalled.stderr"
    rc=$?
    printf 'watched rc=%s, expected=124\n' "$rc"
    [[ "$rc" == 124 && ! -s "$SANDBOX/stalled.stdout" ]] || exit 1
    [[ -s "$FAKE_ADB_STATE/hang-pids" && -s "$SANDBOX/stalled.bin" ]] || exit 1
    IFS=' ' read -r fake_pid sleep_pid < "$FAKE_ADB_STATE/hang-pids" || exit 1
    [[ "$fake_pid" =~ ^[0-9]+$ && "$sleep_pid" =~ ^[0-9]+$ ]] || exit 1
    for pid in "$fake_pid" "$sleep_pid"; do
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            printf 'owned process remains: %s\n' "$pid" >&2
            exit 1
        fi
    done
    grep -q 'Transfer stalled 2s at .* - killing it' "$SANDBOX/stalled.stderr" || exit 1
    exit 0
fi

if command -v adb >/dev/null 2>&1; then
    bad 'controlled PATH must contain no adb'
    exit 1
fi
SANDBOX=$(mktemp -d "$REPO_ROOT/tests/contracts/.transport.XXXXXXXX") || exit 1
export SANDBOX
cleanup() {
    if [[ "$FAIL" == 0 ]]; then
        rm -rf "$SANDBOX"
    else
        printf 'retained sandbox: %s\n' "$SANDBOX" >&2
    fi
}
trap cleanup EXIT
trap 'FAIL=$((FAIL + 1)); exit 130' INT
trap 'FAIL=$((FAIL + 1)); exit 143' TERM
export PT_TRANSPORT=fake
export PT_ADB_BIN="$REPO_ROOT/tests/fake-adb/adb"
export PT_FAKE_ADB_CANONICAL="$PT_ADB_BIN"
export FAKE_ADB_STATE="$SANDBOX/state"
unset FAKE_ADB_SU_MODE FAKE_ADB_PROPAGATE_RC FAKE_ADB_FORCE_DD_SUMMARY
unset FAKE_ADB_HANG_STREAM_ONCE FAKE_ADB_SHORT_STREAM_ONCE FAKE_ADB_MBPS FAKE_ADB_NO_EXEC_OUT
"$BASH" "$REPO_ROOT/tests/device-emu/seed.sh" "$FAKE_ADB_STATE" > "$SANDBOX/seed.log" || {
    bad 'seed fake device'; exit 1;
}
mkdir "$SANDBOX/empty-path" || exit 1

if [[ ! -f "$MODULE_DIR/select.sh" || ! -f "$MODULE_DIR/adb.sh" ]]; then
    bad 'transport modules exist'
    printf 'transport: passed=%s failed=%s\n' "$PASS" "$FAIL"
    exit 1
fi

source_quiet() {
    source "$MODULE_DIR/adb.sh" > "$SANDBOX/source.stdout" 2> "$SANDBOX/source.stderr" || return 1
    [[ ! -s "$SANDBOX/source.stdout" && ! -s "$SANDBOX/source.stderr" ]] || return 1
    [[ ! -e "$FAKE_ADB_STATE/invocations.log" && "$SU_MODE" == '' ]] || return 1
    SU_MODE=direct
    source "$MODULE_DIR/adb.sh" || return 1
    [[ "$SU_MODE" == direct ]] || return 1
    declare -F transport_init >/dev/null
}
check 'source is silent, probe-free, dependency-closed and guarded' source_quiet
source "$MODULE_DIR/adb.sh" || { bad 'load transport'; exit 1; }

cp "$PT_ADB_BIN" "$SANDBOX/not-executable" || exit 1
chmod 644 "$SANDBOX/not-executable" || exit 1
cp "$PT_ADB_BIN" "$SANDBOX/not-canonical" || exit 1
chmod 755 "$SANDBOX/not-canonical" || exit 1
export STUB_LOG="$SANDBOX/stub.argv"
cat > "$SANDBOX/stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_LOG"
case "${STUB_RESPONSE:-record}" in
    record) exit 0 ;;
    garbage) printf 'garbage\n' ;;
    malformed) printf '%s\n' '-rw-r--r-- 1 root root nope date file' ;;
    missing) printf 'ls: absent: No such file or directory\n' >&2 ;;
    failed) exit 1 ;;
    crlf) printf 'first\r\nsecond\r\n__RC__=0\r\n' ;;
    empty-status) printf 'payload\n__RC__=\n' ;;
    exit-three)
        [[ "$1" == shell && "$2" == "su -c 'exit 3' 2>&1; echo __RC__=\$?" ]] || exit 99
        /bin/sh -c 'exit 3'
        printf '__RC__=%s\n' "$?"
        exit 0 ;;
esac
STUB
chmod 755 "$SANDBOX/stub" || exit 1

refusal() {
    local expected=$1 rc out
    out=$(transport_init 2> "$SANDBOX/refusal.stderr"); rc=$?
    [[ "$rc" == 2 && -z "$out" ]] || return 1
    [[ "$(< "$SANDBOX/refusal.stderr")" == "$expected" ]]
}
unknown_mode() { PT_TRANSPORT=unknown; PT_ADB_BIN=relative; refusal 'transport: unknown PT_TRANSPORT'; }
fake_unset() { unset PT_ADB_BIN; refusal 'transport: fake needs PT_ADB_BIN'; }
fake_relative() { PT_ADB_BIN=tests/fake-adb/adb; refusal 'transport: PT_ADB_BIN must be absolute and executable'; }
fake_nonexec() { PT_ADB_BIN="$SANDBOX/not-executable"; refusal 'transport: PT_ADB_BIN must be absolute and executable'; }
fake_other() { PT_ADB_BIN="$SANDBOX/not-canonical"; refusal 'transport: fake mode accepts only the canonical fake'; }
fake_no_canonical() { unset PT_FAKE_ADB_CANONICAL; refusal 'transport: fake mode accepts only the canonical fake'; }
live_invalid() { PT_TRANSPORT=live; PT_ADB_BIN=relative; refusal 'transport: explicit PT_ADB_BIN invalid; refusing'; }
live_empty() { PT_TRANSPORT=live; PT_ADB_BIN=''; refusal 'transport: explicit PT_ADB_BIN invalid; refusing'; }
live_absent() { PT_TRANSPORT=live; unset PT_ADB_BIN; PATH="$SANDBOX/empty-path"; refusal 'transport: adb not on PATH'; }
live_relative_lookup() {
    PT_TRANSPORT=live; unset PT_ADB_BIN
    adb() { return 99; }
    refusal 'transport: PATH must select an absolute executable file'
}
check 'unknown mode refused before path validation' unknown_mode
check 'fake refuses unset binary' fake_unset
check 'fake refuses relative binary' fake_relative
check 'fake refuses non-executable file' fake_nonexec
check 'fake refuses noncanonical executable' fake_other
check 'fake refuses missing canonical declaration' fake_no_canonical
check 'live refuses invalid explicit binary' live_invalid
check 'live refuses explicitly empty binary' live_empty
check 'live refuses absent PATH binary' live_absent
check 'live refuses non-file PATH resolution' live_relative_lookup

selection_success() {
    transport_init || return 1
    transport_init || return 1
    [[ "$(transport_selected_bin)" == "$PT_FAKE_ADB_CANONICAL" ]] || return 1
    PT_TRANSPORT=live PT_ADB_BIN="$SANDBOX/stub"
    transport_init || return 1
    [[ "$(transport_selected_bin)" == "$SANDBOX/stub" ]] || return 1
    local verb
    for verb in shell exec-out push pull install reboot backup restore devices get-state wait-for-device; do
        adb_t_run "$verb" 'one argument' '$(not-executed); *' '' || return 1
        printf '%s\n' "$verb" 'one argument' '$(not-executed); *' '' > "$SANDBOX/expected.argv"
        cmp "$SANDBOX/expected.argv" "$STUB_LOG" || return 1
    done
}
check 'selection is idempotent and explicit live stub preserves every verb and argv' selection_success

no_root_exec() {
    local rc
    [[ "$SU_MODE" == '' ]] || return 1
    adb_t_root_exec whoami > "$SANDBOX/no-root.stdout" 2> "$SANDBOX/no-root.stderr"; rc=$?
    [[ "$rc" == 125 && ! -s "$SANDBOX/no-root.stdout" ]] || return 1
    grep -q 'root not established' "$SANDBOX/no-root.stderr"
}
check 'root exec refuses before any probe' no_root_exec
quoted_command() {
    local rc
    adb_t_root_exec "echo 'unsafe'" > "$SANDBOX/quote.stdout" 2> "$SANDBOX/quote.stderr"; rc=$?
    [[ "$rc" == 125 && ! -s "$SANDBOX/quote.stdout" ]] || return 1
    grep -q 'command contains a single quote' "$SANDBOX/quote.stderr"
}
check 'root exec rejects single quotes with 125' quoted_command
root_payload() {
    local out rc
    adb_t_root_probe || return 1
    [[ "$SU_MODE" == piped ]] || return 1
    out=$(adb_t_root_exec whoami); rc=$?
    [[ "$rc" == 0 && "$out" == root ]]
}
check 'default fake probe selects piped root and strips sentinel' root_payload
root_direct() {
    export FAKE_ADB_SU_MODE=direct
    adb_t_root_probe || return 1
    [[ "$SU_MODE" == direct && "$(adb_t_root_exec whoami)" == root ]]
}
check 'direct root probe and execution' root_direct
root_denied() {
    local rc
    adb_t_root_probe || return 1
    export FAKE_ADB_SU_MODE=none
    adb_t_root_probe; rc=$?
    [[ "$rc" == 1 && "$SU_MODE" == '' ]] || return 1
    no_root_exec
}
check 'failed root probe clears previous root and exec refuses' root_denied
root_stub() {
    local response=$1 expected_rc=$2 expected_payload=$3 out rc
    PT_TRANSPORT=live PT_ADB_BIN="$SANDBOX/stub" SU_MODE=direct
    export STUB_RESPONSE="$response"
    out=$(adb_t_root_exec 'exit 3' 2> "$SANDBOX/root-stub.stderr"); rc=$?
    [[ "$rc" == "$expected_rc" && "$out" == "$expected_payload" ]]
}
check 'true remote exit 3 survives a successful host exit' root_stub exit-three 3 ''
check 'missing sentinel returns 125' root_stub garbage 125 ''
check 'empty sentinel status returns 125' root_stub empty-status 125 ''
check 'carriage returns normalized and payload trimmed' root_stub crlf 0 $'first\nsecond'

binary_stream() {
    adb_t_root_probe || return 1
    adb_t_root_stream 'dd if=/dev/block/mmcblk0 bs=4096' > "$SANDBOX/stream.bin" || return 1
    cmp "$FAKE_ADB_STATE/blockdev" "$SANDBOX/stream.bin"
}
check 'binary exec-out payload matches seeded block file exactly' binary_stream
binary_control() {
    export FAKE_ADB_FORCE_DD_SUMMARY=1
    adb_t_root_probe || return 1
    adb_t_root_stream 'dd if=/dev/block/mmcblk0 bs=4096' > "$SANDBOX/contaminated.bin" || return 1
    if cmp -s "$FAKE_ADB_STATE/blockdev" "$SANDBOX/contaminated.bin"; then return 1; fi
    tail -c 200 "$SANDBOX/contaminated.bin" | grep -q 'records out'
}
check 'binary comparison detects forced dd diagnostic contamination' binary_control
stream_refusals() {
    local rc
    SU_MODE=''
    adb_t_root_stream whoami > "$SANDBOX/stream-refusal.stdout" 2> "$SANDBOX/stream-refusal.stderr"; rc=$?
    [[ "$rc" == 125 && ! -s "$SANDBOX/stream-refusal.stdout" ]] || return 1
    grep -q 'root not established' "$SANDBOX/stream-refusal.stderr" || return 1
    adb_t_root_stream "echo 'unsafe'" > "$SANDBOX/stream-refusal.stdout" 2> "$SANDBOX/stream-refusal.stderr"; rc=$?
    [[ "$rc" == 125 && ! -s "$SANDBOX/stream-refusal.stdout" ]] || return 1
    grep -q 'command contains a single quote' "$SANDBOX/stream-refusal.stderr"
}
check 'binary stream refuses missing root and single quotes' stream_refusals
healthy_watch() {
    adb_t_root_probe || return 1
    adb_t_root_stream_watched 'dd if=/dev/block/mmcblk0 bs=4096' "$SANDBOX/watched.bin" 2 \
        > "$SANDBOX/watched.stdout" 2> "$SANDBOX/watched.stderr" || return 1
    [[ ! -s "$SANDBOX/watched.stdout" && ! -s "$SANDBOX/watched.stderr" ]] || return 1
    cmp "$FAKE_ADB_STATE/blockdev" "$SANDBOX/watched.bin"
}
check 'healthy watched stream completes with exact payload' healthy_watch
stalled_watch() {
    export FAKE_ADB_HANG_STREAM_ONCE=1
    python3 - "$BASH" "${BASH_SOURCE[0]}" <<'PY'
import os
import signal
import subprocess
import sys

child = subprocess.Popen([sys.argv[1], sys.argv[2], '--stall-child'], start_new_session=True)
try:
    result = child.wait(timeout=15)
except subprocess.TimeoutExpired:
    print('stall case exceeded 15 seconds', file=sys.stderr)
    result = 1
finally:
    # This process group belongs only to the child spawned above.
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()
sys.exit(result)
PY
}
check 'stalled watched stream returns 124 and reaps fake plus sleep within timeout' stalled_watch

remote_size() {
    local path=$1 expected_rc=$2 expected_out=$3 out rc
    out=$(adb_t_remote_size "$path" 2> "$SANDBOX/size.stderr"); rc=$?
    [[ "$rc" == "$expected_rc" && "$out" == "$expected_out" ]]
}
printf 'size fixture\n' > "$FAKE_ADB_STATE/sdcard/size.bin"
: > "$FAKE_ADB_STATE/sdcard/empty.bin"
check 'remote size returns exact integer for existing file' remote_size /sdcard/size.bin 0 13
check 'remote size distinguishes zero length from missing' remote_size /sdcard/empty.bin 0 0
check 'remote size returns 1 when old shell protocol hides missing-file status' remote_size /sdcard/absent.bin 1 ''
size_stub() {
    PT_TRANSPORT=live PT_ADB_BIN="$SANDBOX/stub"
    export STUB_RESPONSE=$1
    remote_size /anything "$2" ''
}
check 'remote size returns 2 for unreadable output' size_stub garbage 2
check 'remote size returns 2 for noninteger size field' size_stub malformed 2
check 'remote size returns 1 when ls exits unsuccessfully' size_stub failed 1
check 'remote size returns 1 for missing-file diagnostic' size_stub missing 1

method_refusal() {
    local method=$1 rc
    PT_TRANSPORT=unknown
    "$method" "echo 'unsafe'" "$SANDBOX/refused.bin" 2 \
        > "$SANDBOX/method.stdout" 2> "$SANDBOX/method.stderr"; rc=$?
    [[ "$rc" == 2 && ! -s "$SANDBOX/method.stdout" && ! -e "$SANDBOX/refused.bin" ]] || return 1
    [[ "$(< "$SANDBOX/method.stderr")" == 'transport: unknown PT_TRANSPORT' ]]
}
for method in adb_t_run adb_t_root_probe adb_t_root_exec adb_t_root_stream \
    adb_t_root_stream_watched adb_t_remote_size adb_t_kill_tree; do
    check "$method validates selection before work" method_refusal "$method"
done
printf 'transport: passed=%s failed=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
