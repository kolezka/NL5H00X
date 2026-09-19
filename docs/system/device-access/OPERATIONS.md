---
block: device-access
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

Nothing here runs on its own. The library is sourced, not executed, and its include guard makes a second source a no-op. [verified]

The lifecycle entry point is `scripts/lib/common.sh::require_device()`, which checks for the adb binary, then for a connected and authorized device, and then optionally for root. [verified]

Its argument is compared against the literal string `true`, so any other value, including the empty string, skips the root probe and leaves `scripts/lib/common.sh::SU_MODE` empty. [verified]

Every failure in that chain calls exit rather than returning, so `require_device` terminates the entry script instead of handing back a status. [verified]

`scripts/lib/common.sh::require_backup()` is the second gate and also exits. It is called from one place at the pin, `scripts/UNLOCK.sh::require_backup`, and only when the run is not in status mode. [verified]

The interactive helpers `scripts/lib/common.sh::confirm()` and `scripts/lib/common.sh::pause()` read from stdin, so any caller wrapped in a pipeline or run unattended blocks or consumes piped data. [inferred]

## Observe

There is no log file. Progress goes to stdout through the status, success and step printers, and diagnostics go to stderr through the warning and error printers. [verified]

That split is load-bearing rather than cosmetic: helpers return their payload on stdout and are called through command substitution, so a diagnostic on stdout ends up inside the caller's variable instead of in front of the operator. [verified]

A stalled transfer announces itself with the word stalled, the elapsed threshold and the byte count reached, formatted by `scripts/lib/common.sh::human_size()`. [verified]

`require_backup` is the richest status surface in the block. On failure it walks every `projector-backup-*` directory and prints a distinct line per failure mode: missing image, unusable manifest, or a byte count that does not match the manifest. [verified]

## Configuration and paths

Root form resolves at probe time, not from configuration. `scripts/lib/common.sh::check_root_access()` tries `su -c` first, falls back to the piped form, and leaves `SU_MODE` empty when neither returns root. Both root helpers branch on that value and refuse with 125 when it is empty. [verified]

The manifest filename is a single constant, `scripts/lib/common.sh::MANIFEST_NAME`, and is not configurable. `write_backup_manifest` writes it relative to the current directory, while `read_manifest_field` joins it onto a directory argument. [verified]

Backup directory resolution is a glob over `projector-backup-*` in the current directory, with two different precedences. `scripts/lib/common.sh::find_backup_dir()` returns the first entry that verifies, and `scripts/lib/common.sh::find_incomplete_backup_dir()` returns the last entry that has an image but no manifest. Glob order is lexicographic and the timestamped names sort chronologically, so the first is the oldest and the last is the newest. [verified]

The stall threshold is the third argument to `scripts/lib/common.sh::adb_root_stream_watched()` and defaults to 30 seconds. The watchdog samples every two seconds and accumulates quiet time in two second steps, so the effective threshold rounds up to an even number. [verified]

The backup block passes its own value through `scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS`, which is where an operator changes it. [verified]

`scripts/lib/common.sh::local_size()` and `scripts/lib/common.sh::local_md5()` each try the BSD form first and fall back to the GNU form, so both work on macOS and Linux without configuration. [verified]

`scripts/lib/common.sh::get_script_dir()` resolves a symlink chain before printing a directory, but it has no callers and reads the library's own path rather than the entry script's, so it is not a working path resolver. See GAPS.md. [verified]

## Failure and recovery

Status 125 from either root helper means the call never reached the device: root was not established, or the command contained a single quote. Read stderr to tell them apart. [verified]

Status 124 from the watched stream means the transfer stopped producing bytes and was killed. The caller is expected to retry, and the block's own consumers do so while ignoring the status and judging the result by content. [verified]

Recovery from a killed transfer starts from zero for that block, because the watched helper truncates its output file at entry. Resuming a partial image is the caller's job, done by choosing the next offset, not by appending to what the helper left behind. [verified]

A killed transfer leaves no orphaned processes, because `scripts/lib/common.sh::kill_tree()` recurses into grandchildren before killing. [verified]

`scripts/lib/common.sh::verify_backup_dir()` distinguishes three failure modes by status: 1 means no image, 2 means no usable manifest, 3 means a size mismatch. Only 3 indicates a truncated image; 2 means completeness could not be judged at all. [verified]

A backup made before manifests existed can be vouched for by hand. `require_backup` prints the exact line to write, and states that it should only be done after independently confirming the image is complete. [verified]
