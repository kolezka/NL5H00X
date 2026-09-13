---
block: backup
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Contracts

These are the surfaces other blocks, the test harness and an operator depend on. Each was read from `scripts/MAKE_BACKUP.sh` at the pin; none was observed running against the projector. [verified]

## The CLI takes no arguments and its exit status is the verdict

`scripts/MAKE_BACKUP.sh` ends with `main "$@"` and nothing in the file parses an option or a positional argument, so the whole interface is the environment plus the working directory. [verified] `scripts/MAKE_BACKUP.sh::main()` returns the verdict computed by `scripts/MAKE_BACKUP.sh::verify_backup()` and nothing else, so a zero exit means the assembled image matched the device size and a manifest was written. [verified]

Partition capture cannot change that verdict: `main()` calls `scripts/MAKE_BACKUP.sh::backup_partition()` twice with a trailing `|| true`, and the staged fallbacks are called the same way. [verified] A passing run therefore does not promise that `scripts/MAKE_BACKUP.sh::"boot.img"` or `scripts/MAKE_BACKUP.sh::"system.img"` is present. [inferred]

enforcement: `tests/run-tests.sh::"exits non-zero when chunks come back short"` (test suite)

## The run directory is chosen by a three-way precedence

`scripts/MAKE_BACKUP.sh::main()` takes `BACKUP_DIR` when it is set and nonempty, otherwise the directory returned by `scripts/lib/common.sh::find_incomplete_backup_dir()`, otherwise a fresh `scripts/MAKE_BACKUP.sh::"projector-backup-"` name suffixed with a local `%Y%m%d_%H%M%S` timestamp. [verified] It then creates the directory and `cd`s into it, so every path in the rest of the script is relative to that directory and the parent working directory is the search root for resume candidates. [verified]

The middle arm is what makes resume reachable at all: without it every run would create its own empty timestamped directory and start from zero. [verified] The rule that decides which directory qualifies belongs to [`device-access`](../device-access/README.md).

enforcement: `scripts/MAKE_BACKUP.sh::main()` (run start)

## The run directory holds a fixed set of names

The names are hard coded, not derived, so a consumer may match them literally. [verified] A run writes `system-properties.txt`, `installed-packages.txt`, `enabled-packages.txt`, `disabled-packages.txt`, `partition-info.txt` and `scripts/MAKE_BACKUP.sh::"current-home-activity.txt"` in `scripts/MAKE_BACKUP.sh::backup_system_info()`, `scripts/MAKE_BACKUP.sh::"complete-app-backup.ab"` in `scripts/MAKE_BACKUP.sh::backup_app_data()`, `boot.img` and `system.img` from partition capture, `scripts/MAKE_BACKUP.sh::"full-system-backup.img"` from whichever full-device path ran, and both generated scripts from `scripts/MAKE_BACKUP.sh::create_restore_scripts()`. [verified]

Two names are transient and belong to the block's internals rather than its output: `scripts/MAKE_BACKUP.sh::"stream_block.tmp"` for the current streaming block, and `scripts/MAKE_BACKUP.sh::"backup_chunk_"` files that the chunked path removes only after the combined image passes its size check. [verified]

enforcement: `tests/run-tests.sh::run_backup()` (test suite locates outputs by these names)

## The manifest is the durable success marker and records the method

`scripts/MAKE_BACKUP.sh::verify_backup()` calls `scripts/lib/common.sh::write_backup_manifest()` only on the passing branch and removes `scripts/lib/common.sh::MANIFEST_NAME` on the failing one, so a manifest can never be vouched for by the run that failed to produce it. [verified]

The manifest's third line is `method=` followed by the value of `scripts/MAKE_BACKUP.sh::BACKUP_METHOD` at the moment of the write, which `main()` sets to `stream` before attempting the stream and to `chunked` or `direct` when it falls back. [verified] The harness asserts that literal line, both its exact stream form and the staged alternatives, so the token set is a contract and not an implementation detail. [verified]

enforcement: `tests/run-tests.sh::"^method=stream$"` and `tests/run-tests.sh::"manifest records the staged method actually used"` (test suite)

## Streaming is the default path and the staged paths are the fallback

`main()` always sets `scripts/MAKE_BACKUP.sh::BACKUP_METHOD` to stream and calls `scripts/MAKE_BACKUP.sh::backup_full_device_stream()` first, because that path stages nothing on the device and so needs no free space there. [verified] Only when it returns nonzero does `main()` print `scripts/MAKE_BACKUP.sh::"Streaming failed - falling back to a staged backup"`, delete the partial image, and choose between `scripts/MAKE_BACKUP.sh::backup_full_device_chunked()` and `scripts/MAKE_BACKUP.sh::backup_full_device_direct()` by comparing the device size against the free space reported by `scripts/MAKE_BACKUP.sh::get_device_free_space()`. [verified] More free space than the device selects the direct path; anything else selects chunked, including a free-space reading that did not parse as a number. [verified]

enforcement: `tests/run-tests.sh::"streaming is the path taken by default"` and `tests/run-tests.sh::"still completes without exec-out"` (test suite)

## Resume is offered only for the streamed image, and only after a content check

`scripts/MAKE_BACKUP.sh::backup_full_device_stream()` rounds the existing image length down to a whole block, discards any partial tail past that boundary, then re-reads the last mebibyte before the resume point off the device and compares md5 with the same range of the local file. [verified] A mismatch, or a probe that returned nothing, produces `scripts/MAKE_BACKUP.sh::"Resume check FAILED"` and a nonzero return rather than an extended image. [verified]

The two staged paths have no resume of their own: chunked capture restarts its loop from chunk zero and direct capture recreates the whole device file. [verified]

enforcement: `tests/run-tests.sh::"resume point is checked against the device, not assumed"` and `tests/run-tests.sh::"mismatched prefix is detected and named"` (test suite)

## Every transferred length is checked against a device-reported expectation

No path accepts a nonempty file as evidence of a complete one. Partition capture compares the pulled length with `blockdev --getsize64` for that partition, chunked capture compares each chunk on the device and again after the pull against a computed expectation with a legitimately short final chunk, direct capture compares the staged file and the pulled file against the device size, and streaming compares each block and then the assembled image. [verified] The assembled-image check is two sided: a result larger than the device is reported as `scripts/MAKE_BACKUP.sh::"larger than the device"` rather than trimmed or accepted. [verified]

enforcement: `scripts/MAKE_BACKUP.sh::verify_backup()` (end of run) and `tests/run-tests.sh::"image is exactly device size"` (test suite)

## The block writes to stdout and stderr, never to a log file

Nothing in `scripts/MAKE_BACKUP.sh` opens a log. Progress goes to stdout through the shared print helpers and diagnostics go to stderr, and callers redirect the combined stream where they want it. [verified] Two consumers depend on the text of that stream: `scripts/PROJECTOR.sh::run_backup()` counts stall reports in `scripts/PROJECTOR.sh::".backup-progress.log"`, and the harness matches message fragments such as `scripts/MAKE_BACKUP.sh::"partial tail"` and `scripts/MAKE_BACKUP.sh::"already present and verified"`. [verified] Rewording an operator message is therefore a breaking change for both. [inferred]

enforcement: `tests/run-tests.sh::"partial tail past the block boundary is dropped"` (test suite)

## The generated restore script gates the whole-device write on the manifest

`scripts/MAKE_BACKUP.sh::create_restore_scripts()` emits `RESTORE.sh` with four numbered options plus quit: launcher reset, app-data restore, system-partition restore, and full device restore. [verified] Option 4 refuses with `scripts/MAKE_BACKUP.sh::"No backup-manifest.txt - cannot confirm this image is complete."` when the manifest is missing or carries no `device_size`, refuses as `scripts/MAKE_BACKUP.sh::"TRUNCATED"` when the image length differs from that value, and otherwise requires the operator to type the literal word demanded by `scripts/MAKE_BACKUP.sh::"Type RESTORE to confirm"`. [verified]

The gate is length against the manifest, nothing more. No checksum of the image is recorded anywhere, so an image of exactly the right length whose contents are wrong passes every check the restore script can make. [verified] Options 1 to 3 carry no manifest gate and no typed confirmation at all. [verified]

enforcement: convention (no suite executes `RESTORE.sh`; see `GAPS.md`)

## Behaviour is tuned entirely through the environment

Seven variables are read with a `${VAR:-default}` default and none is validated: `scripts/MAKE_BACKUP.sh::CHUNK_SIZE_MB`, `scripts/MAKE_BACKUP.sh::DEVICE_BLOCK`, `scripts/MAKE_BACKUP.sh::DD_BLOCK_SIZE`, `scripts/MAKE_BACKUP.sh::STREAM_CHUNK_MB`, `scripts/MAKE_BACKUP.sh::STREAM_RETRIES`, `scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS`, and `BACKUP_DIR` read in `main()`. [verified] Their scopes and the values they do not reach are set out in `OPERATIONS.md`.

enforcement: `tests/run-tests.sh::run_backup()` (test suite overrides them through `env`)
