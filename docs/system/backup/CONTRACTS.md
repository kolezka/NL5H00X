---
block: backup
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## Entry point and exit status

The script takes no arguments and is run directly, ending in a call to `scripts/MAKE_BACKUP.sh::main()` whose return value becomes the process exit status. [verified] Exit 0 means verification passed and a manifest was written; any other status means the run produced nothing another block may rely on. [verified]

enforcement: `tests/run-tests.sh::"healthy device produces a complete backup"` (test suite), `tests/run-tests.sh::"truncated chunk is caught"` (test suite)

## Backup directory contents

Every artifact is written relative to the resolved backup directory, because `scripts/MAKE_BACKUP.sh::main()` changes into it before any capture starts. [verified] The durable names are `full-system-backup.img`, `boot.img`, `system.img`, `complete-app-backup.ab`, `backup-manifest.txt`, `RESTORE.sh`, `reset-launcher.sh`, `system-properties.txt`, `installed-packages.txt`, `enabled-packages.txt`, `disabled-packages.txt`, `partition-info.txt` and `current-home-activity.txt`. [verified] Other blocks and the test harness locate a backup by these names, not by scanning content. [verified]

enforcement: `tests/run-tests.sh::"healthy device produces a complete backup"` (test suite), `scripts/lib/common.sh::verify_backup_dir()` (consumer, owned by device-access)

## Whole-device capture strategy resolver

Three strategies exist and one run may use more than one. [verified] Streaming is always attempted first and sets the method to stream, because `scripts/MAKE_BACKUP.sh::backup_full_device_stream()` needs no free space on the device at all. [verified] If it returns non-zero the partial image is deleted and one staged strategy is chosen: `scripts/MAKE_BACKUP.sh::backup_full_device_chunked()` when the device size exceeds the free space reported for `/sdcard`, otherwise `scripts/MAKE_BACKUP.sh::backup_full_device_direct()`. [verified] A free-space probe that returns anything non-numeric is coerced to zero, which sends the fallback to the chunked path, so an unreadable probe biases toward the strategy that needs less room. [inferred, because zero is below any positive device size and the comparison is a strict greater-than]

The chosen strategy is recorded as the `method=` field of the manifest, so a later restore can tell how the image was assembled. [verified]

enforcement: `scripts/MAKE_BACKUP.sh::main()` (runtime), `tests/run-tests.sh::"falls back to a staged backup when exec-out is unavailable"` (test suite)

## Environment tunables

Seven inputs are read from the environment with a literal default, so an override is set in the caller's environment and nothing else changes behaviour: `CHUNK_SIZE_MB`, `DEVICE_BLOCK`, `DD_BLOCK_SIZE`, `STREAM_CHUNK_MB`, `STREAM_RETRIES`, `STREAM_STALL_SECS` and `BACKUP_DIR`. [verified] Defaults and precedence are in [OPERATIONS](OPERATIONS.md). [verified] `BACKUP_METHOD` looks similar but is not an input, since `scripts/MAKE_BACKUP.sh::"BACKUP_METHOD=unknown"` assigns unconditionally and the strategy resolver overwrites it at runtime. [verified]

enforcement: `tests/run-tests.sh::run_backup()` (test suite, which drives a small stand-in device by setting `CHUNK_SIZE_MB`, `STREAM_CHUNK_MB` and `STREAM_STALL_SECS`)

## Generated RESTORE.sh refuses an unprovable full-device image

`scripts/MAKE_BACKUP.sh::create_restore_scripts()` writes `RESTORE.sh` into the backup directory, not into `scripts/`, so a reader looking for it in the repository will not find it. [verified] The generated text guards the full-device option three ways. It exits when `full-system-backup.img` is absent, printing `scripts/MAKE_BACKUP.sh::"No full-system-backup.img here"`. [verified] It exits when no `device_size` line can be read from `backup-manifest.txt`, which covers a missing manifest, printing `scripts/MAKE_BACKUP.sh::"No backup-manifest.txt"` and refusing to restore. [verified] It exits when the image size differs from the manifest value, naming the image as `scripts/MAKE_BACKUP.sh::"TRUNCATED"`. [verified] Only past all three does it ask the operator to type the confirmation word. [verified]

enforcement: convention (no test loads or runs the generated script, see [GAPS](GAPS.md))

## A verified backup is one whose image matches the device size

`scripts/MAKE_BACKUP.sh::verify_backup()` is the single place that decides pass or fail, and it passes only when the local image size equals the size reported for the device block. [verified] On pass it writes the manifest; on fail it removes the manifest and returns non-zero, so a failed run can never vouch for its own output. [verified] This is the definition the unlock and front-ends blocks gate on, both through the library helpers that read the manifest back. [verified]

enforcement: `scripts/MAKE_BACKUP.sh::verify_backup()` (end of run), `scripts/UNLOCK.sh::require_backup` (consumer gate), `scripts/PROJECTOR.sh::verify_backup_dir` (consumer gate), `tests/run-tests.sh::"require_backup rejects a truncated image"` (test suite)

## Narrower artifacts are captured but never fail the run

`scripts/MAKE_BACKUP.sh::backup_system_info()` captures properties, package lists, partition table and the current home activity. [verified] `scripts/MAKE_BACKUP.sh::backup_app_data()` captures an adb app backup and downgrades a cancelled or empty result to a warning. [verified] `scripts/MAKE_BACKUP.sh::backup_partition()` pulls the boot and system partitions with a full size check, and both calls are suffixed so a failure cannot abort the run. [verified] None of these affect the verdict. [verified]

enforcement: `scripts/MAKE_BACKUP.sh::main()` (runtime), `tests/run-tests.sh::"a resumed run does not re-pull partitions it already has"` (test suite)

## Parses and runs under the system bash

The script must parse under `/bin/bash`, which is 3.2 on macOS, rather than a newer bash found on PATH. [verified]

enforcement: `tests/ui-tests.sh::"every entry script runs under the system bash"` (test suite)
