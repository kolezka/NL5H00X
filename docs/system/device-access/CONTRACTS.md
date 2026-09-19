---
block: device-access
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## Device and root guard

### Root is probed, never assumed

`scripts/lib/common.sh::check_root_access()` tries `su -c` first and falls back to the piped form, setting `scripts/lib/common.sh::SU_MODE` to `direct`, `piped`, or empty on failure. [verified]

Callers reach it through `scripts/lib/common.sh::require_device()`, which takes one argument and only probes root when that argument is the string `true`. [verified]

enforcement: `scripts/lib/common.sh::require_device()` (exits 1 when root was required and not found)

### Root helpers refuse to run before the probe

Both `scripts/lib/common.sh::adb_root_exec()` and `scripts/lib/common.sh::adb_root_stream()` return 125 when `SU_MODE` is empty, so a caller that skipped `require_device true` fails loudly instead of running as the shell user. [verified]

enforcement: `tests/run-tests.sh::"remote failure is not mistaken for success"` (test suite, runs the backup with no working su and asserts a non-zero exit)

## Remote command execution

### The returned status is the device's, not adb's

`scripts/lib/common.sh::adb_root_exec()` appends an `__RC__=` sentinel line on the far side, strips it from the payload, and returns the parsed number as its own status. [verified]

A missing sentinel is treated as a failure and returns 125 rather than a silent success. [verified]

enforcement: `scripts/lib/common.sh::adb_root_exec()` (call time, parses the sentinel and returns 125 when absent)

### Root helpers reject a single quote in the command

The command is embedded in a single-quoted string on the device side, so both root helpers return 125 when the command contains a single quote rather than sending a truncated command. [verified]

enforcement: `scripts/lib/common.sh::adb_root_stream()` (call-time guard, no regression test covers it, see GAPS.md)

## Bulk data streams

### Binary comes back over exec-out with remote stderr dropped

`scripts/lib/common.sh::adb_root_stream()` uses `adb exec-out` rather than a shell, and appends the stderr redirect itself instead of trusting each call site to remember it. [verified]

enforcement: `tests/run-tests.sh::"device diagnostics cannot pass as image data"` (test suite)

### A stalled transfer is killed and reported as 124

`scripts/lib/common.sh::adb_root_stream_watched()` polls the output file every two seconds and returns 124 after the size has not grown for `stall_secs`, which defaults to 30. [verified]

Any other outcome returns 0, including a stream that failed, so a caller must judge success from the bytes it got rather than from this status. [verified]

enforcement: `tests/run-tests.sh::"a HUNG transfer is killed and retried, not waited on forever"` (test suite)

### The watched helper truncates its output before each attempt

`adb_root_stream_watched` opens the target with a truncating redirect at entry, so one call always writes a whole block from zero and resume is the caller's job. [verified]

enforcement: `scripts/lib/common.sh::adb_root_stream_watched()` (call time)

## Backup manifest format

### File shape

`scripts/lib/common.sh::MANIFEST_NAME` fixes the filename as `backup-manifest.txt`, and `scripts/lib/common.sh::write_backup_manifest()` writes exactly four `key=value` lines: `device_size`, `device_block`, `method` and `created`, where `created` is a UTC timestamp. [verified]

`scripts/lib/common.sh::read_manifest_field()` takes a directory and a field name, matches the first line with that key anchored at the start, and returns everything after the first `=`. [verified]

enforcement: `scripts/lib/common.sh::read_manifest_field()` (parse time, returns 1 when the file or field is absent)

### Completeness is size equality, not a floor

`scripts/lib/common.sh::verify_backup_dir()` returns 0 only when the image byte count equals the manifest `device_size`, and reports why it failed through distinct statuses: 1 for a missing image, 2 for a missing or unusable manifest, 3 for a size mismatch. [verified]

enforcement: `tests/run-tests.sh::"require_backup rejects a truncated image"` (test suite, a 2 GB image against a 7.65 GB manifest)

### The gate exits, it does not return

`scripts/lib/common.sh::require_backup()` prints a per-directory reason for every candidate and then calls exit, so a caller cannot accidentally continue past a failed check by ignoring a return value. [verified]

enforcement: `scripts/UNLOCK.sh::require_backup` (the single call site, guarded only by the status mode check)

## Library conventions

### Sourcing is idempotent and safe under set -u

The include guard reads `scripts/lib/common.sh::_COMMON_SH_LOADED` through a `:-` default, which is required because entry scripts enable `set -u` before sourcing. [verified]

enforcement: `tests/run-tests.sh::"common.sh loads under set -u"` (test suite, sources once and twice under `set -euo pipefail`)

### Payload on stdout, diagnostics on stderr

Helpers that return a value are called through command substitution, so `scripts/lib/common.sh::print_warning()` and the error printer write to stderr while progress printers write to stdout. [verified]

enforcement: `tests/run-tests.sh::"diagnostics reach the operator, not the caller's variable"` (test suite, asserts both that the capture is empty and that the text reached stderr)

### Sizes are decimal

`scripts/lib/common.sh::human_size()` divides by powers of 1000 and prints two fractional digits above 1 GB, matching what `blockdev` reports and what the manifest stores. [verified]

enforcement: `tests/run-tests.sh::check_size()` (test suite, three fixed conversions)

### Backup directories are found by glob in the current directory

`scripts/lib/common.sh::find_backup_dir()` and `scripts/lib/common.sh::find_incomplete_backup_dir()` both iterate the unanchored glob `projector-backup-*`, so the caller's working directory selects the candidate set. [verified]

enforcement: convention (no code checks that the caller changed directory first, see GAPS.md)
