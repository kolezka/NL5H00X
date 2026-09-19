---
block: backup
doc: DECISIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Decisions

## Stream to the host first, stage on the device only as a fallback

The whole-device capture tries the streaming path before either staged path, and the staged paths exist only to catch a run where streaming fails. [verified] Streaming reads the block device and writes straight to the host, so it needs no free space on the device at all. [verified] The chosen strategy is recorded in the manifest so a restore knows how the image was assembled. [verified]

### Rejected alternative: stage the whole image on device storage

Writing the full image to `/sdcard` and pulling it afterwards needs as much free space as the device is large, which this hardware does not have. [historical: 2026-07-28, source comment in `scripts/MAKE_BACKUP.sh::main()` recording 7.65 GB of device against 3.74 GB free] The path is kept as a fallback rather than deleted, because it only needs a working pull and not a working exec stream, and the test suite exercises it with the stream disabled. [verified]

## Move the image in bounded blocks with a retry per block

`scripts/MAKE_BACKUP.sh::backup_full_device_stream()` reads the device in blocks whose size is a tunable, retries a block that comes back short or stalls, and resumes from the last completed block when a run dies anyway. [verified] Each block is short enough that a single remote read does not have to survive long. [verified]

### Rejected alternative: one transfer for the whole device

A single whole-device read has to survive many minutes. Measured on hardware, it did not: the remote read was reaped partway through, the host side kept waiting on a stream that would never produce another byte, and the entire run was lost while the link stayed healthy. [historical: 2026-07-28, source comment in `scripts/MAKE_BACKUP.sh::backup_full_device_stream()`]

A retry loop alone was also rejected, and the source says why. A retry around a call that never returns is decoration, so the retry is paired with a watchdog that kills a silent transfer. [verified] The test suite records that the first block-retry implementation passed its tests and still hung on the device, because the fake returned short instantly instead of hanging. [verified]

## Discard a partial tail on resume instead of trusting it

When an existing image is not a whole number of blocks, the trailing partial block is truncated away before the transfer continues. [verified]

### Rejected alternative: keep the partial tail and continue from its end

A partial tail cannot be told apart from a complete one after the fact. [verified] Keeping it risks a gap or an overlap at the join, and the final length assertion would not catch either, since the assembled file would still reach the expected size. [verified]

## Delete chunk files only after the combined image is checked

The chunked path concatenates its chunks, compares the combined length against the device size, and deletes the chunks only when that check passes. [verified]

### Rejected alternative: delete each chunk once it has been concatenated

Deleting before the check destroys the only evidence of what actually came off the device, which is the material an operator needs when the combined image is the wrong size. [verified] The test suite asserts the chunks are still on disk after a failed run. [verified]
