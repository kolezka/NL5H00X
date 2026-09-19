---
block: device-access
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## get_script_dir is dead and would not do what its name says

`scripts/lib/common.sh::get_script_dir()` has no caller anywhere in the tree at the pin, only its own definition. [verified]

It reads `BASH_SOURCE[0]` from inside the library, which resolves to the library file itself, so it would return the `scripts/lib` directory rather than the entry script's directory. [inferred]

It also runs `cd` outside a subshell, so calling it changes the caller's working directory, and the backup resolvers in this same file select their candidates by a working-directory-relative glob. [verified]

## adb_exec has no callers and does not check the remote status

`scripts/lib/common.sh::adb_exec()` is defined but called nowhere outside its own definition and usage comment at the pin. [verified]

It judges success from the local `eval` status, which is exactly the signal the sibling root helper exists to distrust, so promoting it to general use would reintroduce the failure that `__RC__=` was added to prevent. [inferred]

## Exit code 125 is overloaded

Both root helpers return 125 for a command containing a single quote and for root not yet being established. [verified]

A caller cannot tell a malformed command from a missing root probe by status alone and has to read stderr. [inferred]

## No test covers the single-quote guard

The regression suite has sections for the loader, diagnostics, sizes, resume, stalls and the backup gate, but none exercises a command containing a single quote. [verified]

The guard in `scripts/lib/common.sh::adb_root_exec()` is therefore enforced only by the code itself, and removing it would keep the suite green. [inferred]

## The manifest writer cannot target a directory

`scripts/lib/common.sh::write_backup_manifest()` writes to a bare relative filename, while `scripts/lib/common.sh::read_manifest_field()` takes a directory argument. [verified]

The write side only works when the caller has already changed into the backup directory, so the two halves of one format have different interfaces. [inferred]

## A second parser for this format lives outside the block

The restore path in `scripts/MAKE_BACKUP.sh` reads `device_size` with its own grep and cut rather than through `read_manifest_field`, and sizes the image with its own `stat` pair rather than through `local_size`. [verified]

A change to the manifest format has to be made in two places, and only one of them is in the block that owns the format. [inferred]

## Backup resolution depends on the working directory

`scripts/lib/common.sh::find_backup_dir()` and `scripts/lib/common.sh::find_incomplete_backup_dir()` glob `projector-backup-*` relative to wherever the caller happens to be. [verified]

Nothing checks that the caller is in the right place, so running the unlock gate from a different directory reports no backup rather than reporting a wrong directory. [inferred]

## The two resolvers have opposite precedence

`find_backup_dir` returns the first verified directory the glob yields and `find_incomplete_backup_dir` keeps the last match it sees. [verified]

Glob order is lexicographic and the names carry sortable timestamps, so one sibling resolver answers with the oldest candidate and the other with the newest. [inferred]

## The connection check does not require exactly one device

`scripts/lib/common.sh::check_device_connected()` greps `adb devices` for any line ending in `device`. [verified]

Two attached devices satisfy that grep, and every later `adb` call then fails for a reason the guard already had the information to name. [inferred]

## The watched stream reports only stalls

`scripts/lib/common.sh::adb_root_stream_watched()` returns 124 for a stall and 0 for everything else, discarding the background job's status. [verified]

A transfer that failed fast is indistinguishable from one that succeeded, so every caller has to verify the bytes independently. [verified]

## Only MD5 is available for content checks

`scripts/lib/common.sh::local_md5()` is the only hash helper, and there is no device-side hash helper at all. [verified]

Any stronger check, and any comparison against a hash computed on the device, is written per call site rather than shared here. [verified]

## Small parsers with thin input validation

`scripts/lib/common.sh::adb_remote_size()` takes field 5 of the first `ls -l` line and falls back to 0 when the result is not numeric, so an unreadable path and a zero-byte file give the same answer. [verified]

`scripts/lib/common.sh::adb_start_action()` prints success unconditionally after firing the intent, without inspecting the output the way its activity counterpart does. [verified]
