---
block: backup
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## DD_BLOCK_SIZE is a tunable in name only

The constant is overridable, but the offsets computed around it are not. Both staged and streamed reads pass `bs` as the tunable while computing `skip` and `count` in fixed units of 1048576 bytes, so any value other than the default puts the read at the wrong offset and asks for the wrong number of bytes. [verified] Several other reads, including the resume probe, the partition tail probe and the two `dd` calls inside the generated restore script, pass the literal 1048576 and ignore the tunable completely. [verified]

The practical consequence is bounded rather than silent. A wrong block size changes the byte count of a read, and every read is followed by a length assertion, so the run fails loudly instead of producing a shifted image. [inferred, since the expected length is computed from the device size and the chunk size in bytes, independently of the block size passed to dd] Treat the constant as fixed and change the arithmetic with it if it ever needs to move. [verified]

## Completeness is proved by length, not by content

Nothing compares the assembled image against the device as a whole. The verdict in `scripts/MAKE_BACKUP.sh::verify_backup()` is a length equality, and the generated restore script repeats the same length check before writing. [verified] The only content comparisons in the block are one megabyte at the resume point and one megabyte at the tail of a reused partition file. [verified]

A device that returns correct lengths while serving wrong bytes outside those two probes would pass. [inferred, since no other read in the block is compared against a device-side digest] The test suite does a full byte comparison against its stand-in device, so the gap is in production runs, not in the tests. [verified]

## The staged direct path can leave a full image on the device

`scripts/MAKE_BACKUP.sh::backup_full_device_direct()` removes the staged file on a failed `dd` and on a device-side size mismatch, but the two failure paths after that, a failed pull and a pulled image of the wrong length, return without removing it. [verified] That leaves a copy the size of the whole device sitting on `/sdcard`, on the one path that was chosen because free space looked sufficient. [inferred, from the resolver picking direct only when free space is at least the device size] A later run then sees less free space than it should. [inferred, from the same free-space probe being read on every run]

## The generated restore script is never parsed or tested

The refusal logic in `RESTORE.sh` is the last guard before an operator overwrites the whole device, and no test loads it. [verified] The suite that parses every entry script under the system bash covers `scripts/MAKE_BACKUP.sh` itself, not the text it emits, because that text lives inside a quoted heredoc and is never evaluated during a test run. [verified] Its enforcement is recorded as convention in [CONTRACTS](CONTRACTS.md). [verified]

## The restore script ignores the manifest fields it could use

The manifest records which block device was captured, but the generated script writes to hardcoded node names for both the system partition and the whole device. [verified] An operator who captured a run with an overridden `DEVICE_BLOCK` would get a manifest that records one target and a restore script that writes to another. [inferred, from the tunable feeding only the capture side while the emitted text is a fixed string]

## The system partition option has no completeness check

The full-device option in the generated script refuses three ways before it writes. The system partition option checks only that `system.img` exists, with no manifest lookup and no size comparison. [verified] A truncated system image can therefore be written over the system partition without any of the guards that protect the whole-device path. [inferred, from the file-existence test being the only condition on that branch]

## A verified backup covers the full image only

`scripts/MAKE_BACKUP.sh::verify_backup()` reports the boot partition, system partition and app backup as warnings when they are missing, and they do not affect the verdict. [verified] A run can therefore be verified and still contain no `boot.img`, no `system.img` and no app backup, which is worth knowing before relying on the partition-level options of the restore script. [verified]

## Small rough edges in the generated script

The launcher option assigns the saved activity to the shell variable `HOME`, overwriting the operator's home directory for the rest of that script invocation. [verified] The value is used on the next line, so the current blast radius is one command. [verified]

The saved launcher value is also never normalized. The successful path writes whatever the platform command prints, while the fallback writes a bare package name, and both are passed straight back on restore. [verified]

## The free-space probe degrades to zero in silence

`scripts/MAKE_BACKUP.sh::get_device_free_space()` parses a column out of `df` without root and without checking the command succeeded, and the caller coerces any non-numeric result to zero. [verified] A failed probe is indistinguishable from a full device, which sends the staged fallback down the chunked path. [inferred, from zero being below any positive device size in the resolver's comparison] The outcome is the safer of the two strategies, so this is a readability gap rather than a correctness one. [inferred, since chunked stages one chunk while direct stages the whole image]
