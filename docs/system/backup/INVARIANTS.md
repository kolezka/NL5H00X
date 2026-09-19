---
block: backup
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

## 1. Every byte count is checked against the device, never against zero

A backup is only ever accepted by comparing a length to the size the device reported, never by checking that a file is non-empty. [verified] The device size itself comes from a length query rather than a scan, and `scripts/MAKE_BACKUP.sh::get_device_size()` refuses a result that is not a positive integer. [verified] The staged paths compare the size on the device, then the size after pulling, against the same expected value, and the streaming path compares each block. [verified]

The defect this pays for is named in the source and in the test suite: `dd` on this device writes short and reports success, so every chunk comes back non-empty and a size-blind script concatenates them and declares victory. [verified] `scripts/MAKE_BACKUP.sh::"silent short write"` marks the chunked check as the one guarding that case. [verified]

A rewrite may change how bytes are moved. It may not replace a length comparison with a presence check. [inferred, since a present but short image is exactly the input that passes a presence check and bricks the device on restore]

## 2. A failed run leaves no manifest

The manifest is written only inside the passing branch of `scripts/MAKE_BACKUP.sh::verify_backup()`, and the failing branch removes it. [verified] Any earlier write would let a run that died halfway vouch for its own output, because the gate other blocks use reads only the manifest and the image length. [verified]

The ordering matters and is easy to break: `scripts/MAKE_BACKUP.sh::create_restore_scripts()` runs before verification, so a failed run still leaves a `RESTORE.sh` on disk. [verified] The absent manifest is what makes that script refuse the dangerous option. [verified]

## 3. A resumed image is proved against the device before it is extended

Resuming trusts nothing it finds on disk. A partial trailing block is truncated away rather than kept, because a partial tail cannot be told apart from a complete one after the fact. [verified] The megabyte before the resume point is then re-read from the device and compared by checksum, and a mismatch aborts with `scripts/MAKE_BACKUP.sh::"Resume check FAILED"` and an instruction to delete the image rather than continue. [verified]

Without that content check a wrong prefix would sail through the final length assertion, since the assembled file would still reach the right size. [verified] The same idea guards partition reuse: `scripts/MAKE_BACKUP.sh::backup_partition()` accepts an existing file only when the length matches and a probe of its last megabyte matches the device. [verified]

## 4. A stalled or short block costs one block, not the run

Inside `scripts/MAKE_BACKUP.sh::backup_full_device_stream()` the retry counter is declared inside the per-block loop, so the budget of `STREAM_RETRIES` attempts applies to each block and resets when the next block starts. [verified] There is no run-wide retry ceiling. [verified]

A stalled transfer being killed and retried is expected behaviour on this hardware, not a fault. [verified] The watchdog call is deliberately allowed to fail without aborting, and the decision is made afterwards by comparing the received length to the expected length, so a killed transfer and a short transfer are handled by the same path. [verified] Only after the attempts are exhausted does the block fail, and the bytes already assembled are kept so a re-run resumes from there. [verified]

The measurement that paid for this: a single whole-device transfer was reaped partway through, the host side kept waiting on a stream that would never produce another byte, and the run was lost while the link itself stayed healthy. [historical: 2026-07-28, source comment in `scripts/MAKE_BACKUP.sh::backup_full_device_stream()`]

## 5. Evidence survives a failed assembly

`scripts/MAKE_BACKUP.sh::backup_full_device_chunked()` concatenates the chunks, checks the combined length, and only then deletes them. [verified] On a mismatch it keeps them and says so with `scripts/MAKE_BACKUP.sh::"Chunk files kept for inspection"`, because deleting them first destroys the only evidence of what actually came off the device. [verified] The test suite asserts the chunks are still present after a failed run. [verified]

## 6. An image larger than the device is treated as contamination, not as success

The streaming path fails when the assembled length is not exactly the device size and calls out the over-size case separately as device diagnostics contaminating the stream. [verified] Extra bytes are a corruption signal here, not a harmless surplus, so an equality test is required and a minimum-length test is not enough. [verified]

## 7. Block sizes passed to dd are numeric byte counts

Every `dd` invocation in the script passes a plain byte count, either the `DD_BLOCK_SIZE` value whose default is 1048576 or the literal 1048576, and no suffixed form such as the megabyte shorthand appears anywhere in the file. [verified] The repository records that the device's `dd` rejects the suffixed form and produced a zero-byte dump that read as success, which is what makes the numeric form load bearing. [verified]

Note the attribution differs between sources. The comment on the constant in `scripts/MAKE_BACKUP.sh::"DD_BLOCK_SIZE=${DD_BLOCK_SIZE:-1048576}"` says busybox, while `docs/BOOT_BRANDING.md` and the repository instructions say toybox. [verified] The behaviour to preserve is the same either way. [inferred, because both accounts describe the same rejected argument form on the same device]

## 8. The streaming path stages nothing on the device

Streaming reads the block device and writes to the host, so it needs no free space on `/sdcard`. [verified] Both staged paths write a file on the device first and remove it afterwards. [verified] Preserving this distinction is what makes streaming the first choice, because the device has less free space than its own total size and a whole staged copy cannot fit. [historical: 2026-07-28, source comment in `scripts/MAKE_BACKUP.sh::main()` recording 7.65 GB of device against 3.74 GB free and a 2.93 GB chunk]
