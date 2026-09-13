---
block: unlock
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Invariants

These were read off the two owned files at the pin. [verified] Most carry a comment recording the incident that paid for them; those dates are the comment's own and cannot be rerun from this repository, so they are tagged as history rather than as measurement. [verified]

## 1. The unlock disables nothing

`scripts/lib/unlock.sh::launcher_default_apply()` writes a home preference and stops there. [verified] The comment above the write states in capitals that nothing is disabled and why: the step used to run a disable on the stock launcher, the firmware dispatches home with an extra category that a vendor component answers, disabling that component left the intent with no candidate, and the device stopped booting. [historical: undated, comment in scripts/lib/unlock.sh, citing docs/BOOT_DEADLOCK.md] The recovery is described as three days and a soldered UART console. [historical: undated, comment in scripts/lib/unlock.sh]

The consequence is the safety property of the whole block: a preference that goes stale degrades to booting the stock launcher, not to not booting. [verified] See [BOOT_DEADLOCK](../../BOOT_DEADLOCK.md).

## 2. Ask the resolver, not the recorded preference

`scripts/lib/unlock.sh::home_owner()` asks `scripts/lib/unlock.sh::home_interceptor()` first and only falls back to `scripts/lib/unlock.sh::home_activity()` when nothing intercepts. [verified] The comment marks this as a correction: the recorded preference is a different question from what wins the boot intent, so the preference could read back perfectly while the next boot ignored it. [historical: 2026-07-30, comment in scripts/lib/unlock.sh]

Both the state function and the post-write check in apply use `home_owner()`, so the question that decides the next boot is the one asked in both places. [verified]

## 3. Installed is not usable

`scripts/lib/unlock.sh::launcher_runs()` starts the component, greps the output for an error because `am start` exits 0 even when it refuses, sleeps `LAUNCHER_SETTLE_SECS`, then checks the process is still alive with `pidof`. [verified] The comment gives the failure it prevents: a launcher that crashes on start still appears in the package list. [verified] `scripts/lib/unlock.sh::launcher_default_apply()` runs this check before writing anything, so a launcher that cannot start costs a failed step and nothing else. [verified]

## 4. The home component is looked up, never spelled out

`scripts/lib/unlock.sh::home_component_of()` queries the activities that declare the home category and extracts the match for the package. [verified] The comment records why hardcoding fails here: the stock launcher's home entry is a misspelled activity name while the activity a user actually sees carries no home filter at all, and the revert path had been pointed at the wrong one. [historical: undated, comment in scripts/lib/unlock.sh] `scripts/lib/unlock.sh::launcher_component()` and `scripts/lib/unlock.sh::launcher_default_revert()` both go through it. [verified]

## 5. The read path must be a command the platform has

`scripts/lib/unlock.sh::home_activity()` parses the preferred-activity dump instead of asking for the home activity directly. [verified] The comment records that `scripts/lib/unlock.sh::"Unknown command: get-home-activity"` is what API 28 answers, that the write command does exist so only the read path was fiction, and that the status screen printed that error string as the name of the home screen. [historical: 2026-07-29, comment in scripts/lib/unlock.sh]

## 6. A pinned preference wins, but a pin is not required

The parser in `scripts/lib/unlock.sh::home_activity()` prefers a pinned entry and falls back to the first home entry it saw. [verified] The comment records the reason for the second pass: the write command records the preference unpinned on this firmware, so demanding a pin read back empty immediately after a successful write. [historical: undated, comment in scripts/lib/unlock.sh]

## 7. Refuse before writing

When an interceptor other than the target launcher owns the intent, `scripts/lib/unlock.sh::launcher_default_apply()` prints the reason and returns 1 without issuing any command. [verified] The comment states the cost of the alternative: a preference the vendor intent ignores leaves a stale record, and a stale record started the incident. [verified] The suite also asserts the device is unchanged after that refusal, including that the interceptor itself was never touched. [verified]

## 8. Re-running is a no-op

The file header states idempotence as a rule because people re-run a finished unlock. [verified] `scripts/UNLOCK.sh::run_step()` returns early on `applied`, `scripts/lib/unlock.sh::launcher_present_apply()` returns 0 immediately when the package is installed, and `scripts/UNLOCK.sh::main()` exits before prompting when `scripts/UNLOCK.sh::all_applied()` is true. [verified]

`tests/unlock-tests.sh::"running it twice changes nothing the second time"` compares settings, home activity and the disabled-package list across two full runs. [verified]

## 9. A disabled component is not a disabled package

`scripts/lib/unlock.sh::component_disabled()` reads the disabled-components section of the package dump rather than the disabled-package list. [verified] The comment records the distinction and its cost: the package is enabled while one component inside it is not, and reading the wrong one cost a day of believing nothing was disabled. [historical: undated, comment in scripts/lib/unlock.sh] The suite asserts the package-level query sees nothing in exactly that state. [verified]

## 10. Revert runs backwards and re-enables before it reads

`scripts/UNLOCK.sh::revert_all()` iterates the step array in reverse so the launcher preference is restored before the launcher's files are removed. [verified] Inside `scripts/lib/unlock.sh::launcher_default_revert()`, the stock launcher is re-enabled before its home component is looked up, because a disabled package registers no activities and the lookup would return empty. [verified]

## 11. The mountpoint is asked for, and put back

`scripts/lib/unlock.sh::system_mountpoint()` reads the mount table and returns the root filesystem when `/system` is not a mount of its own, because this device is system-as-root and remounting `/system` is refused. [historical: undated, comment in scripts/lib/unlock.sh] `scripts/lib/unlock.sh::system_is_rw()` matches the options field positionally rather than grepping mount output, so the read-write flag cannot be matched out of a device name or a path. [verified] `scripts/lib/unlock.sh::system_rw()` verifies the remount took effect instead of trusting it, and every caller pairs it with `scripts/lib/unlock.sh::system_ro()`, including the two early-return paths in `scripts/lib/unlock.sh::launcher_present_apply()`. [verified]

`tests/unlock-tests.sh::"a device that refuses installs still gets the launcher"` asserts the filesystem is read-only again after the fallback. [verified]

## 12. A launcher that shipped with the firmware is not removed

`scripts/lib/unlock.sh::launcher_present_revert()` looks up the package path and leaves it alone when it lives under `/system` but outside the directory this toolkit created. [verified] The comment gives both reasons: it is not this tool's to remove, and uninstalling a system package only strips an update. [verified] The same function removes the fallback directory first, whether or not the package ever registered. [verified]

## 13. Repair works when nothing else does

`scripts/lib/unlock.sh::repair_run()` deliberately does not use the shared device gate as its first check, because that gate exits and this mode exists for a device with no adb. [verified] It probes with `adb devices` itself and prints `scripts/lib/unlock.sh::repair_manual_instructions()` when none is found. [verified] Once a device is present it does call `scripts/lib/common.sh::require_device()` with root required, because without root the shared helper answers every query with silence, which reads exactly like nothing being disabled and is how this check first passed on a broken device. [verified]

`scripts/UNLOCK.sh::main()` dispatches repair before the preconditions for the same reason. [verified]
