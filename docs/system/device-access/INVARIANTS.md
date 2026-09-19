---
block: device-access
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

## 1. Both su forms stay in the probe

`scripts/lib/common.sh::check_root_access()` tries `su -c` and then the piped form, and `scripts/lib/common.sh::adb_root_exec()` keeps a branch for each. [verified]

The hardware this toolkit targets rejects `su -c` with an invalid uid error and accepts only the piped form, recorded in the stand-in device at `tests/fake-adb/adb::unwrap_su()`. [historical: 2026-07-28, comment in tests/fake-adb/adb]

Collapsing this to the piped form alone would look correct against the one device on the desk while removing the only evidence that the direct form was ever tried, so a rewrite must keep the probe rather than the measured outcome. [inferred]

## 2. A remote failure never reads as success

`adb shell` returns 0 regardless of what happened on the far side on older shell protocols, which is why the remote status travels back as an `__RC__=` line inside stdout. [verified]

Without this a failed `dd` is indistinguishable from a successful one, and the caller writes a short image believing it is complete. [verified]

## 3. Remote stderr never lands inside image data

This device's `su` merges the child's stderr into stdout, so `scripts/lib/common.sh::adb_root_stream()` appends the suppression itself rather than leaving it to each call site. [verified]

A 67108864 byte read came back as 67108959 bytes when the `dd` summary was not suppressed, which is a 95 byte corruption that no size check of the obvious kind would catch. [historical: 2026-07-28, comment in scripts/lib/common.sh]

## 4. A hung transfer must be killable

A reaped remote `dd` does not close the `exec-out` stream, so the host waits for bytes that never arrive and a retry loop around a bare stream never regains control. [verified]

A 256 MB block stopped at 113 MB and hung indefinitely with the link still healthy, which is the failure `scripts/lib/common.sh::adb_root_stream_watched()` exists to break. [historical: 2026-07-28, comment in scripts/lib/common.sh]

## 5. The reaper recurses

`scripts/lib/common.sh::kill_tree()` walks children with `pgrep -P` and recurses before killing, because the subshell's child is `adb` and anything `adb` spawned is a grandchild that `pkill -P` leaves running. [verified]

Repeated stall kills left dozens of orphans behind, which turns a clean test suite red for reasons unrelated to the code under test. [historical: undated, comment in scripts/lib/common.sh]

## 6. Backup completeness is equality, never a floor

`scripts/lib/common.sh::verify_backup_dir()` compares the image size to the manifest `device_size` exactly. [verified]

The earlier rule was a size floor, which passes an image that stopped a third of the way through, and that is the image that bricks the device on restore. [verified]

## 7. A resumable run is the one without a manifest

`scripts/lib/common.sh::find_incomplete_backup_dir()` skips any directory that already has a manifest, so only an unfinished run is offered for reuse. [verified]

Without it every run creates a fresh timestamped directory and the streaming resume can never fire. [verified]

## 8. Diagnostics stay out of the caller's variable

Helpers that return a payload are called through command substitution, so a diagnostic written to stdout is swallowed into the caller's variable and the operator sees nothing. [verified]

The warning printer moved to stderr in the same change as the error printer, and the test asserts both so that reverting half the fix goes red. [verified]

## 9. One device, one set of units

`scripts/lib/common.sh::human_size()` uses decimal units because `blockdev`, the manifest and the vendor all describe the same device that way. [verified]

A binary divisor labelled GB reported the same device as 7GB here and 7.65 GB elsewhere, and truncation turned 1932525568 into 1GB instead of 1.93, which is how an operator starts doubting a backup that is fine. [verified]

## 10. The library survives set -u at source time

The include guard reads its own flag through a `:-` default. [verified]

Every entry script enables `set -u` before sourcing, so a bare reference aborts the script on first load before anything runs. [verified]
