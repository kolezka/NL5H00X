---
block: device-access
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Gaps

## The 125 return value is asserted nowhere

Two scenarios look like they cover it and neither does. `tests/run-tests.sh::"remote failure is not mistaken for success"` runs the backup script with `FAKE_ADB_SU_MODE=none` and asserts only that the script exits nonzero. [verified] `scripts/MAKE_BACKUP.sh::main()` calls `require_device true` before any other device work, and that gate exits 1 when `check_root_access()` fails, so no root helper is reached in that run. [verified] The scenario therefore enforces the gate, not the helper. [inferred]

`tests/run-tests.sh::"diagnostics reach the operator, not the caller's variable"` does call `adb_root_exec` with `SU_MODE` set empty, but it asserts that the captured value is empty and that an error reaches stderr; the helper runs inside a command substitution whose status is never read. [verified] So the value 125 is unasserted on both paths, and the only thing holding it is the helper body. [inferred] A change to 1 or to 0 would keep every current suite green. [inferred]

## A failed stream is reported as success by the watchdog

`scripts/lib/common.sh::adb_root_stream_watched()` returns 124 only for a stall. [verified] Every other outcome returns 0, because the background subshell's status is discarded by `wait "$pid" 2>/dev/null || true`. [verified] A stream that refuses immediately, for example the 125 path when `SU_MODE` is empty, leaves an empty output file and a return of 0. [inferred] Callers in [`backup`](../backup/README.md) therefore have to judge the result by bytes, and a future caller that trusts the status gets a silent no-op. [inferred]

## The streaming path cannot recover the remote status at all

`adb_root_exec()` smuggles the far-side status back through a sentinel, but `adb_root_stream()` has no equivalent, since the payload is raw binary. [verified] The value it returns is the local ADB invocation's, and the remote stderr is discarded on the device. [verified] A remote command that fails halfway leaves a short file and no error text anywhere. [inferred]

## Only the piped su form is ever exercised

The fake ADB defaults to the piped form and the only suite override sets `FAKE_ADB_SU_MODE=none`, confirmed by `git grep -n 'FAKE_ADB_SU_MODE' f04ee86 -- tests/` returning one assignment in the fake and one use in the suite. [verified] The `direct` branch of both root helpers is therefore never taken under test, including its different quoting shape. [inferred] The device this toolkit targets accepts only the piped form, so the untested branch is the one that would be needed on different hardware. [assumption]

## The manifest writer takes no directory

`scripts/lib/common.sh::write_backup_manifest()` redirects into `MANIFEST_NAME` with no path, so it writes into whatever the current working directory is. [verified] `read_manifest_field()`, `verify_backup_dir()` and `find_incomplete_backup_dir()` all take or build a directory argument instead. [verified] The write path works because `scripts/MAKE_BACKUP.sh::main()` changes into the backup directory first. [verified] Calling the writer from any other working directory produces a manifest in the wrong place while reporting nothing. [inferred]

## Backup discovery is relative to the current directory

`find_backup_dir()` and `find_incomplete_backup_dir()` glob `projector-backup-*` in the process's working directory, and `require_backup()` builds its whole diagnosis from that glob. [verified] Running an unlock from a different directory reports no backup rather than reporting that it looked elsewhere. [inferred] The newest unfinished run is chosen by lexicographic glob order, which tracks time only while the timestamped naming holds. [verified]

## Verification is length equality, nothing more

`verify_backup_dir()` compares the image length against the manifest's `device_size`. [verified] `local_md5()` exists in this library but no function here feeds it into verification, so a same-length corrupt image passes this block's gate. [verified] The harness plants a same-size impostor to cover the backup script's own byte comparison, which is a different mechanism owned by [`backup`](../backup/README.md). [verified]

## A missing checksum tool returns an empty string, not an error

`local_md5()` is written as `md5 ... || md5sum ... | awk ...`, and the shell binds that as the first command or else the pipeline. [verified] When neither tool exists, `awk` still exits 0 on empty input, so the function returns success with no output. [inferred] A caller comparing two empty strings finds them equal. [inferred]

## Absence and zero are the same answer

`adb_remote_size()` returns 0 for a missing remote path, an unparsable `ls -l` line or a failed ADB call, and its comment states that it never fails the caller. [verified] `local_size()` behaves the same way locally. [verified] Size zero is thus not evidence that a file exists and is empty. [inferred]

## Four helpers are defined and never called

`adb_exec()`, `adb_start_activity()`, `adb_start_action()` and `get_script_dir()` have no caller anywhere in the tree at the pin, confirmed with `git grep -n '<name>' f04ee86` for each and discarding hits inside their own definitions and usage comments. [verified] `adb_exec()` in particular runs its argument through `eval` and prints a success message from a zero status, which is the pattern the root helpers exist to avoid, so a future caller that picks it up by name inherits the bug. [verified]

## The watchdog samples on a fixed two second tick

The quiet counter advances in steps of two seconds, so a stall timeout is effectively rounded up to the next even value, and detection is delayed by up to one tick. [verified] A transfer that keeps growing by a single byte per tick never trips the watchdog at all. [inferred]
