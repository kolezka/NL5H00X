---
block: backup
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Invariants

Behaviour a rewrite of `scripts/MAKE_BACKUP.sh` must keep, with the defect each one was bought with. [verified] The defects are recorded in source comments at the pin; reading a comment proves the rationale was written down, not that the event can be reproduced from this repository. [verified]

## 1. Completeness is length against the device, never non-empty

`scripts/MAKE_BACKUP.sh::verify_backup()` treats a zero-length image as missing and any other length that differs from the device size as `scripts/MAKE_BACKUP.sh::"TRUNCATED"`, printing both numbers. [verified] The comment beside it records why the older non-empty test was not enough: a third of an image is non-empty and will brick the projector on restore. [historical: undated, comment in scripts/MAKE_BACKUP.sh]

The same rule reaches into the generated restore script, which compares the image length against the manifest before it will overwrite anything. [verified] `tests/run-tests.sh::"require_backup rejects an image smaller than the manifest"` covers the gate on the consuming side. [verified]

## 2. A failing run must leave nothing that vouches for it

The manifest is written in exactly one place, the passing branch of `scripts/MAKE_BACKUP.sh::verify_backup()`, and the failing branch removes `scripts/lib/common.sh::MANIFEST_NAME` before printing `scripts/MAKE_BACKUP.sh::"BACKUP INCOMPLETE"`. [verified] The comment records the reasoning: the manifest is what the unlock CLI's `require_backup` checks, so writing it only here means a failed run can never vouch for its own output. [historical: undated, comment in scripts/MAKE_BACKUP.sh]

Removal matters as much as writing, because a resumed run enters a directory that may already hold a manifest from an earlier pass. [inferred] `tests/run-tests.sh::"did not print BACKUP COMPLETE"` locks the operator-facing half of the same rule. [verified]

## 3. Reuse and resume are decided by content, not by length

`scripts/MAKE_BACKUP.sh::backup_partition()` skips a re-pull only when the local file has the exact expected length and the last mebibyte matches what the device returns for the same offset, compared through `scripts/lib/common.sh::local_md5()`. [verified] The comment states the reason directly: length alone cannot tell one 1.93 GB file from another. [historical: undated, comment in scripts/MAKE_BACKUP.sh]

`scripts/MAKE_BACKUP.sh::backup_full_device_stream()` applies the same test at the resume point, because a mismatched prefix would sail through the final size assertion. [verified] `tests/run-tests.sh::"a same-size file that is not the partition is re-pulled"` plants a same-size impostor to prove the check is real. [verified]

The reuse this buys was measured: a resumed run used to re-pull every partition from scratch, about three minutes for the 1.93 GB system partition, every time. [historical: undated, comment in scripts/MAKE_BACKUP.sh]

## 4. A partial tail is discarded, never extended

Streaming resume rounds the existing image down to a whole block and rewrites the file at that boundary before continuing. [verified] The comment records why the tail is not simply appended to: a partial tail cannot be told apart from a complete one after the fact, so it is discarded rather than trusted. [historical: undated, comment in scripts/MAKE_BACKUP.sh]

## 5. Every remote read is bounded in time, not just in size

The streaming path exists because a single 7.65 GB `dd` has to survive roughly twelve minutes and did not: the remote `dd` was reaped at 26 percent, the host side kept waiting on a stream that would never produce another byte, and the whole run was lost while the link stayed healthy. [historical: 2026-07-28, comment in scripts/MAKE_BACKUP.sh] Blocks bound that exposure, so each remote `dd` is short lived and a reaped one is retried rather than fatal. [verified]

Bounding the size alone is not sufficient. Every block read and both md5 probes go through `scripts/lib/common.sh::adb_root_stream_watched()`, and the comment at the call site states the consequence plainly: a retry loop around a call that never returns is decoration. [verified] `tests/run-tests.sh::"run completes despite a transfer that never returns"` is the scenario that only passes if the transfer is actually killed. [verified]

## 6. Contamination is rejected at the block, not absorbed into the image

A block that comes back longer than requested is treated as a failed attempt and retried, and an assembled image longer than the device is reported as `scripts/MAKE_BACKUP.sh::"larger than the device"` with the cause named as device diagnostics in the stream. [verified] This matters because the device's `su` merges the child's stderr into stdout, which is a `device-access` mechanism, so an unsuppressed `dd` summary would otherwise land inside the image bytes. [verified] `tests/run-tests.sh::"over-sized block is named at the point it arrives"` asserts the earlier of the two signals. [verified]

## 7. Evidence outlives a failed chunked run

`scripts/MAKE_BACKUP.sh::backup_full_device_chunked()` concatenates the chunks, checks the combined length, and removes `scripts/MAKE_BACKUP.sh::"backup_chunk_"` files only after that check passes; on failure it prints `scripts/MAKE_BACKUP.sh::"Chunk files kept for inspection"`. [verified] The comment records the risk: deleting them before the check destroys the only evidence of what actually came off the device. [historical: undated, comment in scripts/MAKE_BACKUP.sh] `tests/run-tests.sh::"chunk files kept as evidence after a failed run"` guards it. [verified]

## 8. A short chunk is a failure, not a warning

The chunked path compares each chunk's length on the device before pulling it, and names the failure as a silent short write rather than a warning: `scripts/MAKE_BACKUP.sh::"silent short write"`. [verified] The reason is in the surrounding comment and in the harness scenario heading alike, that `dd` writes short and reports success, so a size-blind script concatenates non-empty chunks and declares victory. [verified]

## 9. The long-running dd keeps its own exit status reachable

`scripts/MAKE_BACKUP.sh::backup_full_device_direct()` runs the remote `dd` in the foreground and reports progress from a background subshell it later kills. [verified] The comment states the constraint that forces this shape: putting the `dd` in the background would put its exit status out of reach. [historical: undated, comment in scripts/MAKE_BACKUP.sh] Progress polling reads the staged file's length on the device rather than parsing output. [verified]

## 10. Streaming is preferred because the device may not have room for the alternative

`main()` tries streaming first because it stages nothing on the device, and the comment records the measurement that makes this decisive on this hardware: `/sdcard` has 3.74 GB free against a 2.93 GB chunk. [historical: undated, comment in scripts/MAKE_BACKUP.sh] Both fallbacks write a staging file to `/sdcard` first, so on a device with less free space than one chunk neither can run. [inferred]

## 11. The method that actually ran is recorded, not the one that was attempted

`scripts/MAKE_BACKUP.sh::BACKUP_METHOD` is reassigned at the moment a fallback is selected, not when the run starts, so a stream that failed and a chunked run that succeeded produce `method=chunked`. [verified] The comment gives the purpose: the value is recorded so a restore knows how the image was assembled. [historical: undated, comment in scripts/MAKE_BACKUP.sh] `tests/run-tests.sh::"manifest records the staged fallback, not the stream that failed"` is the scenario that would catch a stale value. [verified]

## 12. Reuse of an unfinished directory is what makes resume reachable

`main()` prefers an existing unfinished run directory over a fresh timestamped one. [verified] The comment records the failure mode this prevents: without it, the streaming resume can never fire, because every run would get its own empty timestamped directory. [historical: undated, comment in scripts/MAKE_BACKUP.sh] A finished run has a manifest and is deliberately skipped, so a completed backup is never reopened. [verified]
