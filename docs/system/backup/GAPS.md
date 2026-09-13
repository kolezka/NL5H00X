---
block: backup
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Gaps

Debt found by reading `scripts/MAKE_BACKUP.sh` at the pin. The restore-path items are listed first because they concern the one operation that can end the projector. [verified] Nothing here was observed running on hardware. [verified]

## The full device restore does not write the image on its success branch

Option 4 of the generated `RESTORE.sh` runs `scripts/MAKE_BACKUP.sh::"adb push full-system-backup.img /sdcard/"`, and the `dd` that writes the block device is inside the `||` fallback attached to that push. [verified] `scripts/MAKE_BACKUP.sh::"adb reboot"` then runs unconditionally. [verified] So a push that reports success leaves a copy of the image sitting in `/sdcard`, never writes `/dev/block/mmcblk0`, and reboots a device the operator has just been told is being restored. [inferred]

The verification block immediately above it prints that the image was verified and demands a typed confirmation, which makes the outcome read as a completed restore. [verified] This is the highest-value item on this page: the recovery path most likely to be used in an emergency has a branch that silently does nothing. [inferred]

## The restore path uses the su form this device rejects

Both writing paths in `RESTORE.sh` wrap their command as `su -c '...'`: option 3 for the system partition and the streaming fallback of option 4 for the whole device. [verified] The capture side never assumes that form, it probes for a working one in `scripts/lib/common.sh::check_root_access()` and stores the result in `scripts/lib/common.sh::SU_MODE`. [verified]

The recorded measurement for this hardware is that the direct form is refused: `tests/fake-adb/adb::"su: invalid uid/gid '-c'"`, with only the piped form accepted. [historical: 2026-07-28, comment in tests/fake-adb/adb] If that still holds, neither restore write can run as root, and because `adb shell` does not carry the far-side status the failure is not visible to the script. [inferred]

## The streaming restore writes binary through adb shell, not exec-out

The fallback in option 4 pipes the image into `scripts/MAKE_BACKUP.sh::"dd of=/dev/block/mmcblk0 bs=1048576"` over `adb shell`. [verified] The capture side deliberately avoids `adb shell` for bulk binary and uses `exec-out` instead, because some builds run the far side on a pty and translate line endings; the reason is recorded on `scripts/lib/common.sh::adb_root_stream()` and belongs to [`device-access`](../device-access/README.md). [verified]

That recorded reason concerns reading from the device. Whether the same translation corrupts a write into the device over this transport is not established anywhere in this repository, so this is an open risk rather than a demonstrated defect. [inferred]

## The system partition restore has no gate at all

Option 3 checks only that `system.img` exists. [verified] It does not compare the file against any recorded length, does not ask for confirmation, does not check whether the push succeeded before the `dd`, and writes a hard coded `scripts/MAKE_BACKUP.sh::"/dev/block/mmcblk0p20"`. [verified]

The partition number appears twice with no shared definition, once in the capture call in `scripts/MAKE_BACKUP.sh::main()` and once in the restore heredoc, so the two can drift apart without any signal. [verified] A stale or short `system.img` written over the real system partition is the failure this leaves open. [inferred]

## No suite ever runs the generated restore scripts

`git grep -n -i 'RESTORE.sh\|reset-launcher' f04ee86 -- tests/` returns nothing. [verified] Every statement about restore behaviour, on this page and in `CONTRACTS.md`, is a reading of the heredoc text in `scripts/MAKE_BACKUP.sh::create_restore_scripts()` and not a record of the script being executed. [verified]

The manifest gate on option 4 should therefore be read as an intent expressed in code, not as a tested safeguard. [inferred] `RESTORE.sh` also sets no shell options, so it has neither `set -e` nor `pipefail` and continues past a failed command. [verified]

## Nothing records what the image contains, only how long it is

The manifest carries `device_size`, `device_block`, `method` and `created`, written by `scripts/lib/common.sh::write_backup_manifest()`. [verified] No checksum of the assembled image is computed or stored by any path in this block. [verified]

Content is checked while the transfer runs, per block and at the resume point, but that evidence is discarded with the temporary files. [verified] Once the run ends, the strongest statement any consumer can make about the image is that its length matches the manifest, which is exactly what `scripts/lib/common.sh::verify_backup_dir()` does. [verified] An image of the right length whose bytes are wrong passes the restore gate. [inferred]

## The manifest records the method and nothing reads it

The comment in `main()` says the method is recorded so a restore knows how the image was assembled. [verified] `RESTORE.sh` greps `scripts/MAKE_BACKUP.sh::"backup-manifest.txt"` for `device_size` only, and `scripts/lib/common.sh::read_manifest_field()` is called nowhere in this block. [verified] The field is currently written for the test harness and for a human reader. [inferred]

## The streaming failure message promises a resume that main() then deletes

When a block fails every retry, `scripts/MAKE_BACKUP.sh::backup_full_device_stream()` prints `scripts/MAKE_BACKUP.sh::"re-run to resume from here"` and returns 1. [verified] The caller's very next action on that return is `rm -f full-system-backup.img`, before it starts the staged fallback. [verified] The partial image the message points at is gone by the time the operator reads the message. [inferred]

If the staged fallback then also fails, the run ends with no image and the transferred prefix has been discarded, so the next run starts from zero. [inferred]

## A failed resume probe is reported as a corrupt image

The resume probe is called with `|| true`, and `scripts/lib/common.sh::adb_root_stream_watched()` truncates its output file before it starts, so a probe that was killed or returned nothing still leaves a readable empty file. [verified] The md5 of that empty file is a real value that will not match, so the transport failure takes the same branch as genuine corruption and prints `scripts/MAKE_BACKUP.sh::"Resume check FAILED"` together with advice to delete the image and start over. [inferred]

The probe has a fixed 20 second stall budget that `scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS` does not raise, so a link slow enough to go quiet for 20 seconds turns a good image into that message. [verified] The same shape in `scripts/MAKE_BACKUP.sh::backup_partition()` is cheaper, costing only a re-pull. [verified]

## The captured home activity can be an error string

`scripts/MAKE_BACKUP.sh::backup_system_info()` writes `scripts/MAKE_BACKUP.sh::"current-home-activity.txt"` from `cmd package get-home-activity`, falling back to the stock launcher name only when that command reports failure. [verified] On this API level the command does not exist and answers `tests/fake-adb/adb::"Unknown command: get-home-activity"` with status 0. [verified] The redirect captures that text and the fallback never fires. [inferred]

Option 1 of `RESTORE.sh` reads the file, finds it nonempty, and passes its contents to `set-home-activity`, so the recovery action most likely to be reached first would be handed an error message as a component name. [inferred] The same option assigns the value to the variable `HOME`, overwriting the operator's home directory for the rest of that script. [verified]

## reset-launcher.sh ignores what the run captured

The second generated script hard codes the stock launcher package rather than reading `current-home-activity.txt`. [verified] It also passes a bare package name, while the home activity the toolkit elsewhere models is a component with an activity suffix, as in the default of the emulator's `tests/fake-adb/adb::"dumpsys package preferred-activities"` reply. [verified] Which form the device accepts is not established here. [inferred]

## The root fallback in system info is unreachable

`backup_system_info()` captures `/proc/partitions` by trying `su -c` and falling back to the piped form when the first command fails. [verified] The fallback is guarded by the exit status of `adb shell`, which is the exact signal that `scripts/lib/common.sh::adb_root_exec()` exists because it cannot be trusted to carry the far-side status. [verified] Whenever `adb shell` reports success regardless of what `su` did, the piped form is never tried and `partition-info.txt` keeps whatever the first attempt produced. [inferred]

## The restore scripts are written before the verdict and are not withdrawn

`main()` calls `create_restore_scripts()` in phase 5 and `verify_backup()` in phase 6, and the failing branch removes only the manifest. [verified] A failed run therefore leaves an executable `RESTORE.sh` next to a short image. [verified] Option 4 refuses in that state because the manifest is gone, but options 1 to 3 read their own files and have no such gate. [verified]

## App data capture is best effort and not exercised

`scripts/MAKE_BACKUP.sh::backup_app_data()` treats a failed or empty `adb backup` as a warning, and `main()` does not check its result. [verified] The transfer needs an on-device confirmation that no automated run can give, which the code itself warns about. [verified] The harness models the command by writing a four line header into the output file, so no scenario exercises the cancelled or failed branches. [verified]

## The unknown method value cannot be written

`scripts/MAKE_BACKUP.sh::BACKUP_METHOD` is initialised to `unknown`, and `main()` always assigns `stream` before the only call path that reaches `verify_backup()`. [verified] The initial value is unreachable in the manifest and is dead as written. [inferred]

## An overridable block size is not safely overridable

`scripts/MAKE_BACKUP.sh::DD_BLOCK_SIZE` sits under a comment that presents the configuration block as overridable for the test harness. [verified] It is used as the remote `bs` in the streaming, chunked and partition reads, but the `skip` and `count` arguments around it are computed in mebibytes with the literal 1048576, and the expected block length is computed the same way. [verified]

At any value other than the default the requested range and the expected length disagree, so every streaming block fails its size check, exhausts `scripts/MAKE_BACKUP.sh::STREAM_RETRIES` and drops the run to the staged path, where the chunked loop has the same coupling. [inferred] The variable should be treated as fixed until the arithmetic is expressed in terms of it. [inferred]

## The direct path can leave a device-sized file on /sdcard

`scripts/MAKE_BACKUP.sh::backup_full_device_direct()` removes `scripts/MAKE_BACKUP.sh::"full_backup.img"` from the device after a failed remote `dd`, after a short staged copy and after a successful pull, but not on the two branches that return after a failed pull or a short pulled image. [verified] The comparable branches in `scripts/MAKE_BACKUP.sh::backup_partition()` and `scripts/MAKE_BACKUP.sh::backup_full_device_chunked()` all clean up. [verified]

The leftover is the size of the whole device, so the next run reads less free space and may be pushed onto a path that cannot stage either. [inferred]

## Free space is read once, unvalidated, and only steers the choice

`scripts/MAKE_BACKUP.sh::get_device_free_space()` parses the fourth column of `df /sdcard/` without root and multiplies it, and `main()` replaces any result that is not a plain integer with zero. [verified] Zero selects the chunked path, which is the more conservative of the two, so a misparse fails safe. [inferred] Neither staged path checks free space again before staging, so a device with less room than one chunk fails later as a short or failed `dd` rather than as a space problem. [verified]
