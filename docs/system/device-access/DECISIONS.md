---
block: device-access
doc: DECISIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Decisions

## Carry the remote exit status in the payload

`scripts/lib/common.sh::adb_root_exec()` appends an `__RC__=` line on the device side, strips it off, and returns the parsed number as its own status. [verified]

### Rejected alternative: trust adb's exit status

Older shell protocols make `adb shell` exit 0 no matter what happened on the far side, and `su -c` does not reliably pass the child's status either. [verified]

The stand-in device defaults to the non-propagating behaviour precisely because that is the case the toolkit has to survive. [verified]

## Stream binary over exec-out

`scripts/lib/common.sh::adb_root_stream()` uses `adb exec-out` for bulk data. [verified]

### Rejected alternative: adb shell

Some builds run the far side on a pty, which translates line endings and silently corrupts binary data. [verified]

## Suppress remote stderr inside the helper

The stderr redirect is appended by `adb_root_stream` itself rather than being part of the command each caller passes. [verified]

### Rejected alternative: let each call site add the redirect

This device's `su` merges the child's stderr into stdout, so an unsuppressed `dd` writes its summary into the image. A call site can forget the redirect; the helper cannot. [verified]

The cost of forgetting was measured at 95 extra bytes on a 67108864 byte read. [historical: 2026-07-28, comment in scripts/lib/common.sh]

## Reap the process tree recursively

`scripts/lib/common.sh::kill_tree()` recurses through `pgrep -P` before killing each pid. [verified]

### Rejected alternative: pkill -P

`pkill -P` reaches only direct children. The subshell's child is `adb`, so anything `adb` spawned survives as a grandchild, and repeated stall kills left dozens of orphans behind. [verified]

## Verify a backup by size equality

`scripts/lib/common.sh::verify_backup_dir()` requires the image byte count to equal the manifest `device_size`. [verified]

### Rejected alternative: a size floor

The previous rule accepted any image over 1 GB, which passes a backup that stopped a third of the way through, and that is the one that bricks the device on restore. [verified]

## Report sizes in decimal units

`scripts/lib/common.sh::human_size()` divides by powers of 1000 and prints two fractional digits above 1 GB. [verified]

### Rejected alternative: binary divisor labelled GB

Dividing by 1073741824 and calling the result GB made the same device read as 7GB here and 7.65 GB in the manifest, the vendor's material and every document. Truncation compounded it, turning 1932525568 into 1GB rather than 1.93. [verified]

## Probe both su forms rather than hardcoding one

`scripts/lib/common.sh::check_root_access()` tries the direct form, then the piped form, and both root helpers keep a branch for each. [verified]

### Rejected alternative: hardcode the piped form

The target hardware rejects `su -c` and accepts only the piped form, so a hardcoded piped helper would work on the device on the desk. [historical: 2026-07-28, comment in tests/fake-adb/adb]

The code keeps the probe anyway, which is what lets the same library drive a device with the opposite behaviour and what lets the stand-in device at `tests/fake-adb/adb::unwrap_su()` exercise both paths from one environment variable. [inferred]
