#!/bin/bash
# Standalone status and work-directory lock contracts. No device access.
set -u

suite_dir=${BASH_SOURCE[0]%/*}
module_dir="$suite_dir/../../scripts/lib/progress"
passed=0
failed=0

check_rc() {
    local name=$1 expected=$2 actual
    shift 2
    "$@" > "$work/output" 2> "$work/error"
    actual=$?
    if [[ "$actual" == "$expected" ]]; then
        printf 'ok: %s\n' "$name"
        passed=$((passed + 1))
    else
        printf 'FAIL: %s (expected rc %s, got %s)\n' "$name" "$expected" "$actual"
        failed=$((failed + 1))
    fi
}

check_text() {
    local name=$1 expected=$2 actual result
    shift 2
    actual=$("$@")
    result=$?
    if [[ "$result" == 0 && "$actual" == "$expected" ]]; then
        printf 'ok: %s\n' "$name"
        passed=$((passed + 1))
    else
        printf 'FAIL: %s (rc %s, output <%s>)\n' "$name" "$result" "$actual"
        failed=$((failed + 1))
    fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/status protocol.XXXXXXXX") || exit 1
if [[ ! -f "$module_dir/status.sh" || ! -f "$module_dir/lock.sh" ]]; then
    printf 'FAIL: status and lock modules exist\nSummary: 0 passed, 1 failed\n'
    rmdir "$work"
    exit 1
fi
source "$module_dir/status.sh"
source "$module_dir/lock.sh"

run_dir=$(status_run_dir_alloc "$work") || exit 1
run=${run_dir##*/}
running="v=1 run=$run state=running phase=init rc=none artifact=none backup_dir=none bytes=0 total=10 blocks_done=0 blocks_total=1 stalls=0"
complete="v=1 run=$run state=complete phase=verify rc=0 artifact=verified backup_dir=projector-backup-test_1.0 bytes=10 total=10 blocks_done=1 blocks_total=1 stalls=0"
terminal_failed=${running/state=running/state=failed}
terminal_failed=${terminal_failed/rc=none/rc=1}
cancelled=${running/state=running/state=cancelled}
cancelled=${cancelled/rc=none/rc=130}

write_record() {
    local directory=$1 record=$2
    local -a fields
    fields=()
    IFS=' ' read -r -a fields <<< "$record"
    status_write "$directory" "${fields[@]}"
}

check_rc 'allocation creates an absolute directory beneath a spaced workdir' 0 \
    test "$run_dir" = "$work/.projector-status/$run"
check_rc 'allocated directory exists' 0 test -d "$run_dir"
second=$(status_run_dir_alloc "$work") || exit 1
check_rc 'allocation gives each run a fresh identity' 0 test "$second" != "$run_dir"
check_rc 'missing snapshot is absent' 1 status_read "$run_dir"
check_rc 'valid running record' 0 status_validate "$running" "$run"
check_rc 'valid complete record' 0 status_validate "$complete" "$run"
check_rc 'valid failed record' 0 status_validate "$terminal_failed" "$run"
check_rc 'valid cancelled record' 0 status_validate "$cancelled" "$run"
check_text 'field lookup returns the selected backup basename' projector-backup-test_1.0 status_field "$complete" backup_dir
check_rc 'absent field returns one' 1 status_field "$complete" absent
check_rc 'empty field lookup returns one' 1 status_field '' run
check_rc 'whitespace field lookup returns one' 1 status_field '   ' run
check_rc 'unknown field' 2 status_validate "${running/stalls=0/extra=0}" "$run"
check_rc 'duplicate field' 2 status_validate "${running/stalls=0/bytes=0}" "$run"
check_rc 'missing field' 2 status_validate "${running% stalls=0}" "$run"
check_rc 'reordered fields' 2 status_validate "${running/bytes=0 total=10/total=10 bytes=0}" "$run"
check_rc 'extra field' 2 status_validate "$running extra=0" "$run"
check_rc 'unsupported version' 2 status_validate "${running/v=1/v=2}" "$run"
check_rc 'run identity mismatch' 2 status_validate "$running" run.different
check_rc 'empty record' 2 status_validate '' "$run"
check_rc 'whitespace record' 2 status_validate '   ' "$run"
check_rc 'truncated field value' 2 status_validate "${running%0}" "$run"
check_rc 'multiline record' 2 status_validate "$running"$'\n' "$run"
check_rc 'carriage return' 2 status_validate "$running"$'\r' "$run"
check_rc 'tab' 2 status_validate "$running"$'\t' "$run"
for wildcard in '*' '?' '['; do
    check_rc "wildcard $wildcard rejected" 2 status_validate "${running/backup_dir=none/backup_dir=projector-backup-$wildcard}" "$run"
done
for key in bytes total blocks_done blocks_total stalls; do
    original=$(status_field "$running" "$key")
    for value in -1 +1 01 1.5 x 10000000000000000 ''; do
        check_rc "$key rejects <$value>" 2 status_validate "${running/$key=$original/$key=$value}" "$run"
    done
    check_rc "$key accepts sixteen decimal digits" 0 status_validate "${running/$key=$original/$key=9999999999999999}" "$run"
done
for value in none 0 01 -1 +1 x 1.5 '' 256 10000000000000000; do
    check_rc "failed rejects rc $value" 2 status_validate "${terminal_failed/rc=1/rc=$value}" "$run"
done
check_rc 'failed accepts rc 255' 0 status_validate "${terminal_failed/rc=1/rc=255}" "$run"
check_rc 'invalid state token' 2 status_validate "${running/state=running/state=done}" "$run"
check_rc 'invalid phase token' 2 status_validate "${running/phase=init/phase=done}" "$run"
check_rc 'invalid artifact token' 2 status_validate "${running/artifact=none/artifact=done}" "$run"
for phase in init sysinfo appdata partitions image packaging verify; do
    check_rc "phase $phase accepted" 0 status_validate "${running/phase=init/phase=$phase}" "$run"
done
for artifact in none unverified verified truncated missing; do
    check_rc "artifact $artifact accepted" 0 status_validate "${running/artifact=none/artifact=$artifact}" "$run"
done
for value in projector-backup- projector-backup-a/b other projector-backup-a=1; do
    check_rc "backup basename rejects $value" 2 status_validate "${running/backup_dir=none/backup_dir=$value}" "$run"
done
for change in rc=1 artifact=unverified phase=image backup_dir=none; do
    key=${change%%=*}
    original=$(status_field "$complete" "$key")
    check_rc "complete requires $key conjunction" 2 status_validate "${complete/$key=$original/$change}" "$run"
done
check_rc 'running requires rc none' 2 status_validate "${running/rc=none/rc=0}" "$run"
for value in 129 130 143; do
    check_rc "cancelled accepts rc $value" 0 status_validate "${cancelled/rc=130/rc=$value}" "$run"
done
check_rc 'cancelled rejects other rc' 2 status_validate "${cancelled/rc=130/rc=1}" "$run"

implicit_record=${running/run=$run/run=${second##*/}}
check_rc 'writer supplies version and run and orders caller fields' 0 status_write "$second" \
    stalls=0 total=10 bytes=0 backup_dir=none artifact=none rc=none phase=init state=running blocks_total=1 blocks_done=0
check_text 'writer emits the exact fixed field order' "$implicit_record" status_read "$second"
check_rc 'writer creates first snapshot' 0 write_record "$run_dir" "$running"
check_text 'reader sees old snapshot' "$running" status_read "$run_dir"
check_rc 'same writer atomically replaces snapshot' 0 write_record "$run_dir" "$complete"
check_text 'reader sees new snapshot' "$complete" status_read "$run_dir"
check_rc 'invalid write refused' 2 write_record "$run_dir" "${complete/rc=0/rc=1}"
check_text 'invalid write preserves snapshot' "$complete" status_read "$run_dir"
check_rc 'writer rejects unknown fields' 2 write_record "$run_dir" "$complete extra=0"
check_rc 'writer rejects duplicate fields' 2 write_record "$run_dir" "$complete bytes=10"
check_rc 'writer rejects supplied run mismatch' 2 write_record "$run_dir" "${complete/run=$run/run=wrong}"
check_rc 'writer refuses missing fields' 2 status_write "$second" state=running
check_rc 'new shell refuses a snapshot from another writer' 2 "$BASH" -u -c \
    'source "$1"; source "$1"; IFS=" " read -r -a fields <<< "$3"; status_write "$2" "${fields[@]}"' \
    bash "$module_dir/status.sh" "$run_dir" "$complete"
stale=$(status_run_dir_alloc "$work") || exit 1
stale_record=${running/run=$run/run=${stale##*/}}
printf '%s\n' "$stale_record" > "$stale/status"
check_rc 'stale run directory refused' 2 write_record "$stale" "$stale_record"

subshell_write() (
    write_record "$@"
)
check_rc 'inherited subshell cannot reuse parent writer authorization' 2 subshell_write "$run_dir" "$running"
check_text 'refused inherited writer preserves parent snapshot' "$complete" status_read "$run_dir"
printf '999999999\n' > "$run_dir/writer/pid"
check_rc 'later writes recheck writer claim ownership' 2 write_record "$run_dir" "$running"
check_text 'changed writer claim preserves the published snapshot' "$complete" status_read "$run_dir"
claimed=$(status_run_dir_alloc "$work") || exit 1
mkdir "$claimed/writer" || exit 1
printf '999999999\n' > "$claimed/writer/pid"
check_rc 'stale writer claim without a snapshot is refused' 2 write_record "$claimed" "${running/run=$run/run=${claimed##*/}}"

competing_first_writers() {
    local directory old new first second ready='' first_rc='' second_rc='' owner_pid='' record bad=0
    directory=$(status_run_dir_alloc "$work") || return 1
    old=${running/run=$run/run=${directory##*/}}
    new=${complete/run=$run/run=${directory##*/}}
    mkdir "$directory/bin" || return 1
    # Pause both writers at snapshot allocation, before either can publish.
    printf '%s\n' '#!/bin/bash' \
        'path=$("$STATUS_REAL_MKTEMP" "$@") || exit 1' \
        'case "$1" in */.status.XXXXXXXX)' \
        'printf "ready\n" >&7' \
        'IFS= read -r -t 5 go <&8 || exit 1' \
        'esac' \
        'printf "%s\n" "$path"' > "$directory/bin/mktemp"
    chmod +x "$directory/bin/mktemp" || return 1
    local STATUS_REAL_MKTEMP
    STATUS_REAL_MKTEMP=$(type -P mktemp) || return 1
    export STATUS_REAL_MKTEMP
    local PATH="$directory/bin:$PATH"
    mkfifo "$directory/ready" "$directory/go" || return 1
    exec 7<> "$directory/ready" 8<> "$directory/go"
    ( write_record "$directory" "$old"; printf '%s\n' "$?" > "$directory/first.rc" ) &
    first=$!
    ( write_record "$directory" "$new"; printf '%s\n' "$?" > "$directory/second.rc" ) &
    second=$!
    IFS= read -r -t 5 ready <&7 || bad=1
    [[ "$ready" == ready ]] || bad=1
    IFS= read -r -t 5 ready <&7 || bad=1
    [[ "$ready" == ready ]] || bad=1
    printf 'go\ngo\n' >&8
    wait "$first" || bad=1
    wait "$second" || bad=1
    exec 7>&- 8>&-
    IFS= read -r first_rc < "$directory/first.rc" || bad=1
    IFS= read -r second_rc < "$directory/second.rc" || bad=1
    record=$(status_read "$directory") || bad=1
    IFS= read -r owner_pid < "$directory/writer/pid" || bad=1
    if [[ "$first_rc" == 0 && "$second_rc" == 2 ]]; then
        [[ "$record" == "$old" && "$owner_pid" == "$first" ]] || bad=1
    elif [[ "$first_rc" == 2 && "$second_rc" == 0 ]]; then
        [[ "$record" == "$new" && "$owner_pid" == "$second" ]] || bad=1
    else
        printf 'Competing writer return codes: %s %s\n' "$first_rc" "$second_rc" >&2
        bad=1
    fi
    return "$bad"
}
check_rc 'two competing first writers yield exactly one success' 0 competing_first_writers

malformed=$(status_run_dir_alloc "$work") || exit 1
malformed_record=${running/run=$run/run=${malformed##*/}}
printf '' > "$malformed/status"
check_rc 'empty snapshot is malformed not absent' 2 status_read "$malformed"
printf '%s\n\n' "$malformed_record" > "$malformed/status"
check_rc 'second blank line is malformed' 2 status_read "$malformed"
printf '%s\n%s\n' "$malformed_record" "$malformed_record" > "$malformed/status"
check_rc 'two records are malformed' 2 status_read "$malformed"
printf '%s\nx' "$malformed_record" > "$malformed/status"
check_rc 'unterminated second line is malformed' 2 status_read "$malformed"
printf '%s' "${malformed_record% stalls=0}" > "$malformed/status"
check_rc 'truncated snapshot is malformed' 2 status_read "$malformed"
printf '%s\n' "$running" > "$malformed/status"
check_rc 'reader checks directory run identity' 2 status_read "$malformed"

check_text 'classify complete with successful child' complete status_classify "$complete" 0
check_text 'classify complete contradicted by child' failed status_classify "$complete" 1
check_text 'classify terminal failed' failed status_classify "$terminal_failed" 0
check_text 'classify cancelled' cancelled status_classify "$cancelled" 130
check_text 'classify running after exit' aborted status_classify "$running" 1
check_text 'byte count equal to total is not completion' aborted status_classify "${running/bytes=0/bytes=10}" 0
for child_rc in 0 1 130; do
    check_text "missing record with child $child_rc is indeterminate" indeterminate status_classify '' "$child_rc"
    check_text "malformed record with child $child_rc is indeterminate" indeterminate status_classify 'broken' "$child_rc"
done

check_rc 'lock acquired' 0 lock_acquire "$work"
IFS=' ' read -r owner_pid owner_time < "$work/.projector-status/backup.lock/owner"
check_rc 'owner records this shell pid' 0 test "$owner_pid" = "$$"
check_rc 'owner records a timestamp' 0 test -n "$owner_time"
check_rc 'second acquisition is busy' 3 lock_acquire "$work"
check_text 'busy diagnostic contains owner' "$owner_pid $owner_time" tail -n 1 "$work/error"
check_rc 'another shell cannot release owner lock' 3 "$BASH" -u -c \
    'source "$1"; lock_release "$2"' bash "$module_dir/lock.sh" "$work"
check_rc 'owner lock survives refused release' 0 test -f "$work/.projector-status/backup.lock/owner"
check_rc 'owner releases lock' 0 lock_release "$work"
check_rc 'released lock directory removed' 0 test ! -d "$work/.projector-status/backup.lock"
check_rc 'absent lock cannot be released' 3 lock_release "$work"
mkdir "$work/.projector-status/backup.lock" || exit 1
printf '999999999 0\n' > "$work/.projector-status/backup.lock/owner"
check_rc 'stale lock is never guessed dead' 3 lock_acquire "$work"
check_rc 'stale lock cannot be released by this shell' 3 lock_release "$work"

parent_owned_lock() {
    local directory child_rc bad=0
    directory=$(mktemp -d "$work/parent lock.XXXXXXXX") || return 1
    lock_acquire "$directory" || return 1
    ( lock_release "$directory" )
    child_rc=$?
    [[ "$child_rc" == 3 && -f "$directory/.projector-status/backup.lock/owner" ]] || bad=1
    lock_release "$directory" || bad=1
    return "$bad"
}
check_rc 'child subshell cannot release parent lock' 0 parent_owned_lock

child_owned_lock() {
    local mode=$1 directory child sibling ready='' owner='' timestamp='' result bad=0
    directory=$(mktemp -d "$work/child lock.XXXXXXXX") || return 1
    mkfifo "$directory/ready" "$directory/go" || return 1
    exec 7<> "$directory/ready" 8<> "$directory/go"
    (
        lock_acquire "$directory" || exit 1
        printf 'ready\n' >&7
        IFS= read -r -t 5 ready <&8 || exit 1
        lock_release "$directory"
    ) &
    child=$!
    IFS= read -r -t 5 ready <&7 || bad=1
    [[ "$ready" == ready ]] || bad=1
    IFS=' ' read -r owner timestamp < "$directory/.projector-status/backup.lock/owner" || bad=1
    [[ "$owner" == "$child" ]] || bad=1
    if [[ "$mode" == parent ]]; then
        lock_release "$directory"
        result=$?
        [[ "$result" == 3 ]] || bad=1
    else
        (
            lock_acquire "$directory"
            acquired=$?
            lock_release "$directory"
            released=$?
            [[ "$acquired" == 3 && "$released" == 3 ]]
        ) &
        sibling=$!
        wait "$sibling" || bad=1
    fi
    [[ -f "$directory/.projector-status/backup.lock/owner" ]] || bad=1
    printf 'go\n' >&8
    wait "$child" || bad=1
    exec 7>&- 8>&-
    return "$bad"
}
check_rc 'parent cannot release child-owned lock' 0 child_owned_lock parent
check_rc 'sibling cleanup after busy acquisition preserves the live lock' 0 child_owned_lock sibling

atomic_snapshots() {
    local directory old new i record child ready='' observations=0
    directory=$(status_run_dir_alloc "$work") || return 1
    old=${running/run=$run/run=${directory##*/}}
    new=${complete/run=$run/run=${directory##*/}}
    mkfifo "$directory/ready" "$directory/observed" || return 1
    exec 7<> "$directory/ready" 8<> "$directory/observed"
    (
        write_record "$directory" "$old" || exit 1
        printf 'ready\n' >&7
        IFS= read -r -t 5 ready <&8 || exit 1
        [[ "$ready" == observed ]] || exit 1
        for ((i=0; i<50; i++)); do
            write_record "$directory" "$old" || exit 1
            write_record "$directory" "$new" || exit 1
        done
    ) &
    child=$!
    local bad=0 result
    IFS= read -r -t 5 ready <&7 || bad=1
    [[ "$ready" == ready ]] || bad=1
    for ((i=0; i<100; i++)); do
        record=$(status_read "$directory")
        result=$?
        if [[ "$result" == 0 ]]; then
            if [[ "$record" == "$old" || "$record" == "$new" ]]; then
                if [[ "$observations" == 0 ]]; then
                    printf 'observed\n' >&8
                fi
                observations=$((observations + 1))
            else
                bad=1
            fi
        elif [[ "$result" != 1 ]]; then
            bad=1
        fi
    done
    [[ "$observations" -gt 0 ]] || printf 'stop\n' >&8
    wait "$child" || bad=1
    exec 7>&- 8>&-
    record=$(status_read "$directory") || bad=1
    [[ "$record" == "$new" && "$bad" == 0 && "$observations" -gt 0 ]]
}
check_rc 'concurrent reader sees only whole old or new snapshots' 0 atomic_snapshots

source_cleanly() {
    local module=$1
    "$BASH" -u -c 'source "$1"; source "$1"' bash "$module" > "$work/source-output" 2>&1 || return 1
    [[ ! -s "$work/source-output" ]]
}
check_rc 'status sources alone twice without output under nounset' 0 source_cleanly "$module_dir/status.sh"
check_rc 'lock sources alone twice without output under nounset' 0 source_cleanly "$module_dir/lock.sh"
set +f
status_validate "$running" "$run"
check_rc 'validation preserves enabled globbing' 0 test "${-//f/}" = "$-"
set -f
status_validate broken "$run"
check_rc 'invalid validation preserves disabled globbing' 0 test "${-//f/}" != "$-"
set +f

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed"
if [[ "$failed" != 0 ]]; then
    printf 'Retained sandbox: %s\n' "$work"
    exit 1
fi
rm -rf "$work"
