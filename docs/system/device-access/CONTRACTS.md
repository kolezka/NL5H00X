---
block: device-access
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Contracts

## The library loads once and survives `set -u`

The include guard reads `scripts/lib/common.sh::_COMMON_SH_LOADED` through a `:-` default, so a first load under `set -u` does not abort on an unset variable and a second load returns immediately. [verified] The colour constants are `readonly`, which is why the early return matters: re-running that block in the same shell would be an error. [verified]

enforcement: `tests/run-tests.sh::"common.sh loads under set -u"` (suite scenario)

## Payload on stdout, diagnostics on stderr

`scripts/lib/common.sh::print_warning()` and `scripts/lib/common.sh::print_error()` write to stderr; `print_status()`, `print_success()` and `print_step()` write to stdout. [verified] The split is load bearing because helpers such as `adb_root_exec()` return their payload on stdout and are called inside a command substitution, so a diagnostic on stdout would land in the caller's variable instead of reaching the operator. [verified]

enforcement: `tests/run-tests.sh::"diagnostics reach the operator, not the caller's variable"` (suite scenario)

## Root is a handshake, and `SU_MODE` is its whole state

`scripts/lib/common.sh::check_root_access()` probes `su -c 'whoami'` first and sets `SU_MODE` to `direct` on a `root` answer, then probes the piped form and sets `piped`, otherwise clears `SU_MODE` and returns 1. [verified] The variable is a plain global, not exported and not passed as an argument, so it is shared by every helper in that process and by nothing outside it. [verified]

enforcement: `scripts/lib/common.sh::check_root_access()` (probe at call time)

## The root helpers return 125 when root is not established

Both `scripts/lib/common.sh::adb_root_exec()` and `scripts/lib/common.sh::adb_root_stream()` match an empty or unknown `SU_MODE` in their `case`, print a diagnostic naming `require_device true` and return 125 without contacting the device. [verified] `adb_root_exec()` also returns 125 for a command holding a single quote, when the reply carries no sentinel, and when the parsed status is empty. [verified] So 125 means the helper refused or could not read a status, and it is never a status the far side produced. [inferred]

No suite asserts this value; the enforcement is the helper bodies themselves, and the gap is recorded in [Gaps](GAPS.md). [verified]

enforcement: `scripts/lib/common.sh::adb_root_exec()` and `scripts/lib/common.sh::adb_root_stream()` (runtime guard, untested)

## A command containing a single quote is refused, not sent

Each helper embeds the command inside a single-quoted string on the far side, so both reject an argument containing a single quote before any ADB call. [verified] Without the check the remote string would be truncated into a different command rather than failing. [verified]

enforcement: `scripts/lib/common.sh::adb_root_exec()` (argument check before dispatch)

## `adb_root_exec` returns the remote status, not ADB's

The far side appends `scripts/lib/common.sh::"__RC__"` with the command's status, the helper strips carriage returns, and it returns 125 when that sentinel is missing. [verified] Everything ahead of the sentinel is printed as the command's output, so the caller gets the payload on stdout and the true status in `$?`. [verified] ADB's own exit status is discarded, because `adb shell` can exit 0 whatever happened remotely. [verified]

enforcement: `scripts/lib/common.sh::"__RC__"` (sentinel parse)

## `adb_root_stream` returns the transport status and drops remote stderr

The streaming helper uses `adb exec-out` and appends `2>/dev/null` inside the remote command itself, so the caller cannot forget it. [verified] There is no sentinel on this path: the value the caller sees is the status of the local ADB invocation, not the remote command's. [verified] A stream therefore has to be judged by its bytes, not by its exit status. [inferred]

enforcement: `scripts/lib/common.sh::adb_root_stream()` (helper body)

## A stalled transfer is killed and reported as 124

`scripts/lib/common.sh::adb_root_stream_watched()` truncates the output file, runs the stream in a background subshell and samples the file size every two seconds. [verified] When the size does not grow for `stall_secs`, default 30, it warns, calls `kill_tree()` on the subshell and returns 124; otherwise it returns 0 once the subshell ends. [verified] The stall timeout is the third argument, so the caller decides it per call. [verified]

enforcement: `tests/run-tests.sh::"a HUNG transfer is killed and retried, not waited on forever"` (suite scenario)

## The backup manifest is `key=value` lines in a fixed filename

`scripts/lib/common.sh::write_backup_manifest()` writes `device_size`, `device_block`, `method` and a UTC `created` stamp into the file named by `scripts/lib/common.sh::MANIFEST_NAME`, in the current working directory. [verified] `read_manifest_field()` takes a directory plus a field name, matches on a leading `field=`, takes the first match and prints everything after the first `=`. [verified] Presence of the manifest is also the completion marker: `find_incomplete_backup_dir()` treats a directory holding an image but no manifest as an unfinished run. [verified]

enforcement: `scripts/lib/common.sh::read_manifest_field()` (read path)

## `verify_backup_dir` distinguishes its three failure modes

The function returns 0 when the image length equals the manifest's `device_size`, 1 when no image exists, 2 when the manifest is missing or its size field is not a positive integer, and 3 when the image length disagrees. [verified] The distinction is what lets `require_backup()` tell an operator whether a backup is absent, unverifiable or short. [verified] Length equality against a recorded device size is the whole test: no checksum is computed here. [verified]

enforcement: `tests/run-tests.sh::"require_backup rejects a truncated image"` (suite scenario)

## The gates exit the process, they do not return

`scripts/lib/common.sh::require_device()` calls `exit 1` when ADB is missing, when no device is connected, and when root was requested but not obtained. [verified] `require_backup()` prints a per-directory diagnosis and then calls `exit 1` when no directory verifies. [verified] Neither can be used as a test inside a conditional: a caller that wants a status calls the underlying `check_*` or `verify_*` function instead. [inferred]

The scenario below runs the backup script with no working su and asserts a nonzero exit. [verified] Because `scripts/MAKE_BACKUP.sh::main()` calls `require_device true` before any other device work, that nonzero exit is the root gate firing, not a root helper's return value. [inferred]

enforcement: `tests/run-tests.sh::"remote failure is not mistaken for success"` (suite scenario, gate exit only)

## Sizes are decimal and checksums are local

`scripts/lib/common.sh::human_size()` divides by powers of 1000 and prints two fraction digits for gigabytes, matching what `blockdev` reports and what the manifest stores. [verified] `local_size()` returns 0 for an absent file and tries the BSD `stat` form before the GNU one; `local_md5()` tries `md5` before `md5sum`. [verified] `adb_remote_size()` returns 0 rather than failing when the remote path is absent. [verified]

enforcement: `tests/run-tests.sh::"sizes are reported in the same units the device uses"` (suite scenario)
