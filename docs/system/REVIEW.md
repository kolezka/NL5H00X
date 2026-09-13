---
block: _root
doc: REVIEW
verified_against: f04ee86
verified_on: 2026-09-14
---

# Review record

This page records two things: the draft corrections raised on 2026-09-12, with where each one landed, and the source findings this campaign produced that need code work rather than a documentation edit. [verified] Nothing here was established by running the toolkit or by touching the projector. [verified]

## Draft corrections, now applied

The four findings were first raised against drafts held outside this tree. [historical: 2026-09-12, docs/system/REVIEW.md] Each was re-read at the pin during this campaign and written into the integrated pages, so the correction is in the text rather than in a pending list. [verified]

| Finding | Where it landed |
|---|---|
| A blocked launcher step has two causes, and `scripts/lib/unlock.sh::launcher_default_state()` reports the missing package before it queries the interceptor, so chooser advice cannot clear the first cause. | [unlock CONTRACTS](unlock/CONTRACTS.md) and [unlock OPERATIONS](unlock/OPERATIONS.md). [verified] |
| Not every device call in the unlock block uses `scripts/lib/common.sh::adb_root_exec()`: `scripts/UNLOCK.sh::check_supported_device()`, `scripts/UNLOCK.sh::interactive()`, `scripts/lib/unlock.sh::launcher_present_apply()` and `scripts/lib/unlock.sh::repair_run()` call `adb` directly. | [unlock README](unlock/README.md) boundary section. [verified] |
| The return value 125 is not enforced by `tests/run-tests.sh::"remote failure is not mistaken for success"`, whose run exits at the `scripts/lib/common.sh::require_device()` gate before a root helper runs. | [device-access CONTRACTS](device-access/CONTRACTS.md) cites the helper bodies as the runtime guard, and [device-access GAPS](device-access/GAPS.md) records the missing assertion. [verified] |
| `scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS` covers transfer block reads only, while both md5 probes use a fixed 20 seconds. | [backup OPERATIONS](backup/OPERATIONS.md). [verified] |

## Source findings that need code work

These are defects in the toolkit, not in the documentation. They are described where their block owns the code and repeated here so one page carries the list. [verified]

### The full-device restore writes nothing on the success path

In `scripts/MAKE_BACKUP.sh::create_restore_scripts()` the raw `dd` write sits inside the failure branch of `adb push`. [verified] A push that reports success copies the image to `/sdcard`, never writes the block device, and then reboots, immediately after the script printed its verification line and took a typed confirmation. [verified] No suite runs the generated `RESTORE.sh`. [verified] See [backup GAPS](backup/GAPS.md).

### The streaming give-up message contradicts its caller

`scripts/MAKE_BACKUP.sh::backup_full_device_stream()` reports that the partial image is kept for a resumed run. [verified] The caller in `scripts/MAKE_BACKUP.sh::main()` deletes `full-system-backup.img` as its next action on that return. [verified] An operator who follows the message resumes nothing.

### A successful `/system` write is reported as a failure

`scripts/lib/unlock.sh::launcher_present_apply()` returns 1 after it has remounted `/system`, copied the APK and confirmed the copy, because the package only registers after a restart. [verified] `scripts/UNLOCK.sh::run_step()` renders that return with a message stating that nothing further was changed, which is false on this path. [verified] See [unlock GAPS](unlock/GAPS.md).

### One menu entry writes to the device with no confirmation

`scripts/TOOLS.sh::reset_default_launcher()` changes the home activity through `cmd package set-home-activity`. [verified] The string `confirm` does not occur in either front-end file, `scripts/lib/common.sh::require_backup()` is never called from this block, and `main()` passes `false` to `require_device`. [verified] Reproduce with `git grep -c -i confirm f04ee86 -- scripts/PROJECTOR.sh scripts/TOOLS.sh`, which reports no match. [verified] See [front-ends GAPS](front-ends/GAPS.md).

### The installer continues without root

`scripts/INSTALL_APP.sh::main()` runs `check_root_access >/dev/null 2>&1 || true` after a reboot, so a run can continue with an empty `SU_MODE` and take the untested 125 refusal path in the shared helpers. [verified] See [app-install GAPS](app-install/GAPS.md) and [device-access GAPS](device-access/GAPS.md).

## Open scope

app-root stays blocked, so `root/` is a reserved unassigned path and not a documented block. [verified] The pin `f04ee86` is an ancestor of the current branch head, and source added after it, including the root daemon scripts and the newer test trees, is not described anywhere in this tree. [verified] Covering that source needs a full refresh on a new pin, which re-verifies every active page rather than adding a block. [verified]

A clean linter run is a structure gate. [verified] It does not check whether a claim is true, whether an owner is the right one, or whether a contract is really enforced. [verified]
