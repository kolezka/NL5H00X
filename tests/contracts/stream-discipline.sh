#!/bin/bash
# Stream discipline contracts for the ui and progress modules. No device access.
#
# The contract: a helper that returns a value writes that value to stdout and
# nothing else, and every human diagnostic goes to stderr. That is what makes
# out=$(helper) safe. A diagnostic on stdout would be swallowed into the
# caller's variable, corrupting the value and hiding the message.
#
# Capture-sensitive cases call the real helper inside command substitution.
# Cases that must preserve trailing-newline bytes or same-process ownership use
# file redirection instead. A log line printed outside the substitution was
# never a candidate for capture, so a suite built that way proves nothing.
#
#   function              class   stream contract
#   --------------------  ------  ---------------------------------------
#   log_info              none    diagnostic on stderr, stdout empty
#   log_ok                none    diagnostic on stderr, stdout empty
#   log_warn              none    diagnostic on stderr, stdout empty
#   log_error             none    diagnostic on stderr, stdout empty
#   log_step              none    diagnostic on stderr, stdout empty
#   render_header         value   screen block on stdout
#   render_section        value   screen block on stdout
#   render_size           value   human size on stdout
#   render_bar            value   bar on stdout, no trailing newline
#   render_hr             value   rule on stdout
#   print_status          value   legacy line stays on stdout
#   print_success         value   legacy line stays on stdout
#   print_step            value   legacy line stays on stdout
#   print_warning         none    legacy diagnostic stays on stderr
#   print_error           none    legacy diagnostic stays on stderr
#   print_header          value   delegates to render_header
#   print_section         value   delegates to render_section
#   human_size            value   delegates to render_size
#   status_run_dir_alloc  value   fresh run directory on stdout
#   status_read           value   record on stdout
#   status_field          value   one field on stdout
#   status_classify       value   verdict on stdout
#   status_write          none    stdout empty, refusals on stderr
#   status_validate       none    result is the exit code only
#   lock_acquire          none    stdout empty, refusals on stderr
#   lock_release          none    stdout empty, refusals on stderr
#
# No production helper returns binary today, so the binary rule is pinned by a
# fixture that carries arbitrary bytes through stdout while the real log_warn
# writes to stderr. It is compared with cmp. Scanning bytes for a bracketed
# prefix would be wrong: a legitimate payload can contain the text [WARN].
set -u

# shellcheck source-path=SCRIPTDIR

# Byte comparisons and greps over the binary payload must not depend on locale.
LC_ALL=C
export LC_ALL

case "${BASH_SOURCE[0]}" in
    */*) suite_dir=${BASH_SOURCE[0]%/*} ;;
    *) suite_dir=. ;;
esac
ui_dir="$suite_dir/../../scripts/lib/ui"
progress_dir="$suite_dir/../../scripts/lib/progress"

passed=0
failed=0

# Escapes are invisible in a failure line and a raw one repaints the terminal.
visible() {
    local text=$1
    text=${text//$'\033'/^[}
    printf '%s' "$text"
}

pass() {
    printf 'ok: %s\n' "$1"
    passed=$((passed + 1))
}

fail() {
    printf 'FAIL: %s (%s)\n' "$1" "$2"
    failed=$((failed + 1))
}

check_equal() {
    local name=$1 expected=$2 actual=$3
    if [[ "$actual" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected <$(visible "$expected")> got <$(visible "$actual")>"
    fi
}

check_empty() {
    local name=$1 actual=$2
    if [[ -z "$actual" ]]; then
        pass "$name"
    else
        fail "$name" "expected empty stdout, got <$(visible "$actual")>"
    fi
}

check_rc() {
    local name=$1 expected=$2 actual=$3
    if [[ "$actual" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected rc $expected, got $actual"
    fi
}

check_bytes() {
    local name=$1 expected_file=$2 actual_file=$3
    if cmp -s "$expected_file" "$actual_file"; then
        pass "$name"
    else
        fail "$name" "$(cmp "$expected_file" "$actual_file" 2>&1 | head -1)"
    fi
}

check_file_empty() {
    local name=$1 file=$2
    if [[ ! -s "$file" ]]; then
        pass "$name"
    else
        fail "$name" "expected empty file, got <$(visible "$(head -c 200 "$file")")>"
    fi
}

check_file_not_empty() {
    local name=$1 file=$2
    if [[ -s "$file" ]]; then
        pass "$name"
    else
        fail "$name" 'expected output, got an empty file'
    fi
}

for module in "$ui_dir/colors.sh" "$ui_dir/log.sh" "$ui_dir/render.sh" \
    "$ui_dir/legacy.sh" "$progress_dir/status.sh" "$progress_dir/lock.sh"; do
    if [[ ! -f "$module" ]]; then
        printf 'FAIL: module %s exists\nSummary: 0 passed, 1 failed\n' "$module"
        exit 1
    fi
done

# shellcheck source=../../scripts/lib/ui/log.sh
source "$ui_dir/log.sh"
# shellcheck source=../../scripts/lib/ui/render.sh
source "$ui_dir/render.sh"
# shellcheck source=../../scripts/lib/ui/legacy.sh
source "$ui_dir/legacy.sh"
# shellcheck source=../../scripts/lib/progress/status.sh
source "$progress_dir/status.sh"
# shellcheck source=../../scripts/lib/progress/lock.sh
source "$progress_dir/lock.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/stream discipline.XXXXXXXX") || exit 1

# ---------------------------------------------------------------------------
# 16.1 A real log helper runs inside the substitution the caller is capturing.
# ---------------------------------------------------------------------------

# Returns a value on stdout and warns the operator while it works.
fixture_lookup() {
    log_warn "cache miss for $1"
    printf 'resolved:%s\n' "$1"
}

# Two diagnostics on the way to one value, so ordering cannot hide a leak.
fixture_probe() {
    log_error "device busy"
    log_info "retrying"
    printf 'value=%s\n' "$1"
}

# The broken shape this suite exists to catch: the diagnostic on stdout.
fixture_leaky() {
    printf '[WARN] cache miss for %s\n' "$1"
    printf 'resolved:%s\n' "$1"
}

lookup_err="$work/lookup.err"
lookup_out=$(fixture_lookup key1 2>"$lookup_err")
check_equal '16.1 log_warn fixture: captured stdout is the payload only' \
    'resolved:key1' "$lookup_out"
printf '%b\n' "${YELLOW}[WARN]${NC} cache miss for key1" > "$work/lookup.expected"
check_bytes '16.1 log_warn fixture: the diagnostic went to stderr' \
    "$work/lookup.expected" "$lookup_err"

probe_err="$work/probe.err"
probe_out=$(fixture_probe 7 2>"$probe_err")
check_equal '16.1 log_error fixture: captured stdout is the payload only' \
    'value=7' "$probe_out"
{
    printf '%b\n' "${RED}[ERROR]${NC} device busy"
    printf '%b\n' "${BLUE}[INFO]${NC} retrying"
} > "$work/probe.expected"
check_bytes '16.1 log_error fixture: both diagnostics went to stderr' \
    "$work/probe.expected" "$probe_err"

# Positive control on the assertion itself. If a diagnostic on stdout still
# compared equal, every pass above would be worthless.
leaky_out=$(fixture_leaky key1 2>/dev/null)
if [[ "$leaky_out" == 'resolved:key1' ]]; then
    fail '16.1 control: a diagnostic on stdout is caught' \
        'a leaked [WARN] line compared equal to the payload'
else
    pass '16.1 control: a diagnostic on stdout is caught'
fi

# ---------------------------------------------------------------------------
# 16.2 Binary payload, compared byte for byte.
# ---------------------------------------------------------------------------

# Deliberately hostile payload: bracketed text a prefix scan would mistake for
# a diagnostic, then every byte from 0x01 to 0xff, newlines and escapes
# included. NUL free, because a shell variable cannot carry NUL and the
# fixture is meant to be capturable by redirection.
make_binary_seed() {
    local target=$1 i=1
    printf '[WARN] this is payload, not a diagnostic\n' > "$target" || return 1
    while [[ $i -lt 256 ]]; do
        printf '%b' "\\0$(printf '%03o' "$i")" >> "$target" || return 1
        i=$((i + 1))
    done
    printf '\ntail [ERROR] marker\n' >> "$target" || return 1
}

# Streams a byte payload on stdout and narrates on stderr with real helpers.
fixture_binary() {
    log_warn "streaming $1"
    /bin/cat "$1"
    log_ok "streamed $1"
}

seed="$work/payload.bin"
make_binary_seed "$seed" || exit 1

# Validate the fixture before trusting it as a yardstick: 41 bytes of text,
# 255 bytes of 0x01 to 0xff, then 21 bytes of tail.
seed_bytes=$(wc -c < "$seed" | tr -d ' ')
check_equal '16.2 control: the payload is the expected 317 bytes' 317 "$seed_bytes"
seed_without_nul=$(tr -d '\000' < "$seed" | wc -c | tr -d ' ')
check_equal '16.2 control: the payload carries no NUL' 317 "$seed_without_nul"
if grep -q '\[WARN\]' "$seed"; then
    pass '16.2 control: the payload really contains bracketed text'
else
    fail '16.2 control: the payload really contains bracketed text' 'no [WARN] in the seed'
fi

binary_out="$work/payload.out"
binary_err="$work/payload.err"
fixture_binary "$seed" > "$binary_out" 2> "$binary_err"
check_rc '16.2 the binary fixture succeeded' 0 $?
check_bytes '16.2 binary stdout is byte identical to the payload' "$seed" "$binary_out"
{
    printf '%b\n' "${YELLOW}[WARN]${NC} streaming $seed"
    printf '%b\n' "${GREEN}[OK]${NC} streamed $seed"
} > "$work/payload.expected-err"
check_bytes '16.2 the binary fixture kept its narration on stderr' \
    "$work/payload.expected-err" "$binary_err"

# ---------------------------------------------------------------------------
# 16.3 Class by class: value functions expose their value on stdout, none
#      functions return nothing on stdout. File comparisons pin exact bytes.
# ---------------------------------------------------------------------------

# Golden literals for the render_* screen blocks. Lengths are asserted so a
# miscounted golden fails as itself instead of as a render regression.
rule_50='=================================================='
pad_24='                        '
dashes_59='-----------------------------------------------------------'
check_equal '16.3 golden: header rule is 50 characters' 50 "${#rule_50}"
check_equal '16.3 golden: title padding is 24 characters' 24 "${#pad_24}"
check_equal '16.3 golden: horizontal rule is 59 dashes' 59 "${#dashes_59}"

# Each render_* function is asserted twice. The captured comparison is the
# shape a caller writes, out=$(render_...), but it is only a text-value check:
# command substitution strips trailing newlines. The redirected output and cmp
# pin the exact bytes. The golden is written to a file first and the captured
# form is derived from that same file by the same stripping rule.

# value: render_header. Title T, so printf centres on width (1 + 50) / 2 = 25,
# which is 24 spaces then the title.
header_err="$work/header.err"
printf '%b\n%s\n%s%s\n%s%b\n\n' "$CYAN" "$rule_50" "$pad_24" T "$rule_50" "$NC" \
    > "$work/header.expected"
header_expected=$(< "$work/header.expected")
header_out=$(render_header T 2>"$header_err")
check_equal '16.3 render_header is value: captured stdout is the block' \
    "$header_expected" "$header_out"
render_header T > "$work/header.out" 2>>"$header_err"
check_bytes '16.3 render_header stdout is byte exact, trailing newlines included' \
    "$work/header.expected" "$work/header.out"
check_file_empty '16.3 render_header writes nothing to stderr' "$header_err"

# value: render_section
section_err="$work/section.err"
printf '\n%b=== %s ===%b\n\n' "$BOLD" Contract "$NC" > "$work/section.expected"
section_expected=$(< "$work/section.expected")
section_out=$(render_section Contract 2>"$section_err")
check_equal '16.3 render_section is value: captured stdout is the block' \
    "$section_expected" "$section_out"
render_section Contract > "$work/section.out" 2>>"$section_err"
check_bytes '16.3 render_section stdout is byte exact, trailing newlines included' \
    "$work/section.expected" "$work/section.out"
check_file_empty '16.3 render_section writes nothing to stderr' "$section_err"

# value: render_size. 1KB is the observed output of render_size 1536, taken
# from a fresh shell on 2026-09-12 under bash 3.2.57 and 5.3.15, and it is
# what common.sh's human_size has always printed for that input: the division
# is decimal and truncating, so 1536 / 1000 is 1.
size_err="$work/size.err"
printf '1KB\n' > "$work/size.expected"
size_out=$(render_size 1536 2>"$size_err")
check_equal '16.3 render_size is value: captured stdout is the size' 1KB "$size_out"
render_size 1536 > "$work/size.out" 2>>"$size_err"
check_bytes '16.3 render_size stdout is byte exact, one line with a newline' \
    "$work/size.expected" "$work/size.out"
check_file_empty '16.3 render_size writes nothing to stderr' "$size_err"

# value: render_bar. It ends without a newline, and only the byte comparison
# can show that. The captured form looks identical either way, because command
# substitution would strip a newline the renderer had started emitting.
bar_err="$work/bar.err"
printf '%s' '#####.....' > "$work/bar.expected"
bar_out=$(render_bar 50 10 2>"$bar_err")
check_equal '16.3 render_bar is value: captured stdout is the bar' \
    '#####.....' "$bar_out"
render_bar 50 10 > "$work/bar.out" 2>>"$bar_err"
check_bytes '16.3 render_bar stdout is byte exact, with no trailing newline' \
    "$work/bar.expected" "$work/bar.out"
check_file_empty '16.3 render_bar writes nothing to stderr' "$bar_err"

# value: render_hr
hr_err="$work/hr.err"
printf '  %b%s%b\n' "$DIM" "$dashes_59" "$NC" > "$work/hr.expected"
hr_expected=$(< "$work/hr.expected")
hr_out=$(render_hr 2>"$hr_err")
check_equal '16.3 render_hr is value: captured stdout is the rule' "$hr_expected" "$hr_out"
render_hr > "$work/hr.out" 2>>"$hr_err"
check_bytes '16.3 render_hr stdout is byte exact, trailing newline included' \
    "$work/hr.expected" "$work/hr.out"
check_file_empty '16.3 render_hr writes nothing to stderr' "$hr_err"

# none: every log_* helper. Stdout empty, message on stderr, in the shape a
# caller would use it.
for helper in log_info log_ok log_warn log_error log_step; do
    helper_err="$work/$helper.err"
    helper_out=$("$helper" 'sampling the device' 2>"$helper_err")
    check_empty "16.3 $helper is none: captured stdout is empty" "$helper_out"
    check_file_not_empty "16.3 $helper wrote its diagnostic to stderr" "$helper_err"
done

# value: status_run_dir_alloc. Its value is freshly generated, so the
# assertion is on the shape: one line, on stdout, naming a directory that now
# exists inside the work directory.
alloc_err="$work/alloc.err"
run_dir=$(status_run_dir_alloc "$work" 2>"$alloc_err") || exit 1
check_equal '16.3 status_run_dir_alloc is value: stdout is the run directory' \
    "$work/.projector-status/${run_dir##*/}" "$run_dir"
if [[ -d "$run_dir" ]]; then
    pass '16.3 control: the captured run directory exists'
else
    fail '16.3 control: the captured run directory exists' "no directory at <$run_dir>"
fi
check_file_empty '16.3 status_run_dir_alloc writes nothing to stderr' "$alloc_err"

run=${run_dir##*/}
running="v=1 run=$run state=running phase=init rc=none artifact=none backup_dir=none bytes=0 total=10 blocks_done=0 blocks_total=1 stalls=0"
complete="v=1 run=$run state=complete phase=verify rc=0 artifact=verified backup_dir=projector-backup-test_1.0 bytes=10 total=10 blocks_done=1 blocks_total=1 stalls=0"

# none: status_validate. The answer is the exit code; nothing is printed.
validate_err="$work/validate.err"
validate_out=$(status_validate "$running" "$run" 2>"$validate_err")
check_rc '16.3 status_validate accepts a valid record' 0 $?
check_empty '16.3 status_validate is none: captured stdout is empty' "$validate_out"
check_file_empty '16.3 status_validate writes nothing to stderr' "$validate_err"

# none: status_write into the fresh run directory.
write_err="$work/write.err"
write_out=$(status_write "$run_dir" state=running phase=init rc=none artifact=none \
    backup_dir=none bytes=0 total=10 blocks_done=0 blocks_total=1 stalls=0 2>"$write_err")
check_rc '16.3 status_write accepted the record' 0 $?
check_empty '16.3 status_write is none: captured stdout is empty' "$write_out"
check_file_empty '16.3 status_write writes nothing to stderr' "$write_err"

# value: status_read. This doubles as the positive control that the silent
# write above actually wrote something.
read_err="$work/read.err"
read_out=$(status_read "$run_dir" 2>"$read_err")
check_equal '16.3 status_read is value: stdout is exactly the record' "$running" "$read_out"
check_file_empty '16.3 status_read writes nothing to stderr' "$read_err"

# value: status_field
field_err="$work/field.err"
field_out=$(status_field "$running" state 2>"$field_err")
check_equal '16.3 status_field is value: stdout is exactly the field' running "$field_out"
check_file_empty '16.3 status_field writes nothing to stderr' "$field_err"

# value: status_classify
classify_err="$work/classify.err"
classify_out=$(status_classify "$complete" 0 2>"$classify_err")
check_equal '16.3 status_classify is value: captured stdout is the verdict' \
    complete "$classify_out"
check_file_empty '16.3 status_classify writes nothing to stderr' "$classify_err"

# refusal: claim a separate run directly in this shell, then write from a
# command-substitution child. Ownership is the measured process id, so the
# child is a conflicting writer even though it inherited the shell variables.
conflict_run_dir=$(status_run_dir_alloc "$work") || exit 1
conflict_setup_out="$work/conflict-setup.out"
conflict_setup_err="$work/conflict-setup.err"
status_write "$conflict_run_dir" state=running phase=init rc=none artifact=none \
    backup_dir=none bytes=0 total=10 blocks_done=0 blocks_total=1 stalls=0 \
    > "$conflict_setup_out" 2> "$conflict_setup_err"
conflict_setup_rc=$?
check_rc '16.3 conflict setup claimed the writer in this process' 0 \
    "$conflict_setup_rc"
check_file_empty '16.3 conflict setup kept stdout empty' "$conflict_setup_out"
check_file_empty '16.3 conflict setup kept stderr empty' "$conflict_setup_err"

conflict_write_err="$work/conflict-write.err"
conflict_write_out=$(status_write "$conflict_run_dir" state=running phase=init \
    rc=none artifact=none backup_dir=none bytes=0 total=10 blocks_done=0 \
    blocks_total=1 stalls=0 2>"$conflict_write_err")
conflict_write_rc=$?
check_rc '16.3 conflicting status_write returns rc 2' 2 "$conflict_write_rc"
check_empty '16.3 conflicting status_write keeps stdout empty' "$conflict_write_out"
printf 'Refusing existing writer claim: %s\n' "$conflict_run_dir" \
    > "$work/conflict-write.expected"
check_bytes '16.3 conflicting status_write writes the exact refusal to stderr' \
    "$work/conflict-write.expected" "$conflict_write_err"

# none: lock_acquire, captured the way a caller would capture a value.
lock_capture_dir="$work/lock-capture"
mkdir -p "$lock_capture_dir" || exit 1
acquire_err="$work/acquire.err"
acquire_out=$(lock_acquire "$lock_capture_dir" 2>"$acquire_err")
check_rc '16.3 lock_acquire took the lock' 0 $?
check_empty '16.3 lock_acquire is none: captured stdout is empty' "$acquire_out"
check_file_empty '16.3 lock_acquire writes nothing to stderr' "$acquire_err"

# none: lock_release. The owner is a pid, so release only succeeds in the
# process that acquired. A command substitution forks, so the pair is run in
# this shell with stdout redirected to a file instead.
lock_pair_dir="$work/lock-pair"
mkdir -p "$lock_pair_dir" || exit 1
pair_out="$work/pair.out"
pair_err="$work/pair.err"
lock_acquire "$lock_pair_dir" > "$pair_out" 2> "$pair_err"
check_rc '16.3 lock_acquire took the paired lock' 0 $?
lock_release "$lock_pair_dir" >> "$pair_out" 2>> "$pair_err"
check_rc '16.3 lock_release released it' 0 $?
check_file_empty '16.3 lock_release is none: redirected stdout is empty' "$pair_out"
check_file_empty '16.3 lock_release writes nothing to stderr' "$pair_err"

# refusal: keep one lock owned by this shell. A second acquire is busy, and a
# release inside command substitution is a different process and must refuse.
refusal_lock_dir="$work/lock-refusal"
mkdir -p "$refusal_lock_dir" || exit 1
refusal_setup_out="$work/refusal-setup.out"
refusal_setup_err="$work/refusal-setup.err"
lock_acquire "$refusal_lock_dir" > "$refusal_setup_out" 2> "$refusal_setup_err"
refusal_setup_rc=$?
check_rc '16.3 refusal setup acquired the lock' 0 "$refusal_setup_rc"
check_file_empty '16.3 refusal setup kept stdout empty' "$refusal_setup_out"
check_file_empty '16.3 refusal setup kept stderr empty' "$refusal_setup_err"

busy_lock_err="$work/busy-lock.err"
busy_lock_out=$(lock_acquire "$refusal_lock_dir" 2>"$busy_lock_err")
busy_lock_rc=$?
check_rc '16.3 busy lock_acquire returns rc 3' 3 "$busy_lock_rc"
check_empty '16.3 busy lock_acquire keeps stdout empty' "$busy_lock_out"
{
    printf 'Backup lock is busy: %s\n' \
        "$refusal_lock_dir/.projector-status/backup.lock"
    /bin/cat "$refusal_lock_dir/.projector-status/backup.lock/owner"
} > "$work/busy-lock.expected"
check_bytes '16.3 busy lock_acquire writes the exact refusal to stderr' \
    "$work/busy-lock.expected" "$busy_lock_err"

foreign_release_err="$work/foreign-release.err"
foreign_release_out=$(lock_release "$refusal_lock_dir" 2>"$foreign_release_err")
foreign_release_rc=$?
check_rc '16.3 foreign lock_release returns rc 3' 3 "$foreign_release_rc"
check_empty '16.3 foreign lock_release keeps stdout empty' "$foreign_release_out"
printf "Cannot release another owner's backup lock: %s\n" \
    "$refusal_lock_dir/.projector-status/backup.lock" \
    > "$work/foreign-release.expected"
check_bytes '16.3 foreign lock_release writes the exact refusal to stderr' \
    "$work/foreign-release.expected" "$foreign_release_err"

refusal_cleanup_out="$work/refusal-cleanup.out"
refusal_cleanup_err="$work/refusal-cleanup.err"
lock_release "$refusal_lock_dir" > "$refusal_cleanup_out" 2> "$refusal_cleanup_err"
refusal_cleanup_rc=$?
check_rc '16.3 refusal cleanup released the parent-owned lock' 0 \
    "$refusal_cleanup_rc"
check_file_empty '16.3 refusal cleanup kept stdout empty' "$refusal_cleanup_out"
check_file_empty '16.3 refusal cleanup kept stderr empty' "$refusal_cleanup_err"

# ---------------------------------------------------------------------------
# 16.4 Compatibility: the legacy writers keep the streams the CLI expects.
# ---------------------------------------------------------------------------

status_err="$work/print-status.err"
status_out=$(print_status 'unlocking the bootloader' 2>"$status_err")
check_equal '16.4 print_status still writes its line to stdout' \
    "$(printf '%b' "${BLUE}[INFO]${NC} unlocking the bootloader")" "$status_out"
check_file_empty '16.4 print_status writes nothing to stderr' "$status_err"

success_err="$work/print-success.err"
success_out=$(print_success 'backup verified' 2>"$success_err")
check_equal '16.4 print_success still writes its line to stdout' \
    "$(printf '%b' "${GREEN}[OK]${NC} backup verified")" "$success_out"
check_file_empty '16.4 print_success writes nothing to stderr' "$success_err"

step_err="$work/print-step.err"
step_out=$(print_step 'pulling partitions' 2>"$step_err")
check_equal '16.4 print_step still writes its line to stdout' \
    "$(printf '%b' "${PURPLE}[STEP]${NC} pulling partitions")" "$step_out"
check_file_empty '16.4 print_step writes nothing to stderr' "$step_err"

warning_err="$work/print-warning.err"
warning_out=$(print_warning 'battery is low' 2>"$warning_err")
check_empty '16.4 print_warning keeps stdout clean' "$warning_out"
printf '%b\n' "${YELLOW}[WARN]${NC} battery is low" > "$work/print-warning.expected"
check_bytes '16.4 print_warning still writes to stderr' \
    "$work/print-warning.expected" "$warning_err"

perror_err="$work/print-error.err"
perror_out=$(print_error 'device not found' 2>"$perror_err")
check_empty '16.4 print_error keeps stdout clean' "$perror_out"
printf '%b\n' "${RED}[ERROR]${NC} device not found" > "$work/print-error.expected"
check_bytes '16.4 print_error still writes to stderr' \
    "$work/print-error.expected" "$perror_err"

# The delegating names must land on the same stream as what they delegate to.
check_equal '16.4 human_size delegates to render_size on stdout' 1KB "$(human_size 1536)"
check_equal '16.4 print_section delegates to render_section on stdout' \
    "$section_expected" "$(print_section Contract)"
check_equal '16.4 print_header delegates to render_header on stdout' \
    "$header_expected" "$(print_header T)"

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed"
if [[ "$failed" != 0 ]]; then
    printf 'Retained sandbox: %s\n' "$work"
    exit 1
fi
rm -rf "$work"
