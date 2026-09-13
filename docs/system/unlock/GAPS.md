---
block: unlock
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Gaps

## The two blocked causes are not equally helpful

`scripts/lib/unlock.sh::launcher_default_state()` returns `blocked:install the launcher first` for a missing package and a full paragraph naming the component and the chooser steps for an interceptor. [verified] `scripts/UNLOCK.sh::run_step()` prints both the same way, after `cannot run`. [verified] The short one names no step and no command, so an operator reading the status table sees the same `[blocked]` label for a cause fixed by running `launcher_present` and for a cause no CLI can fix at all. [inferred] Recovery for each is in [Operations](OPERATIONS.md).

Only the interceptor cause is covered by a scenario; nothing asserts the missing-package wording. [verified]

## A successful copy is reported as nothing having changed

When `adb install` is refused, `scripts/lib/unlock.sh::launcher_present_apply()` copies the APK into `LAUNCHER_SYSTEM_DIR` and then returns 1 so the run does not claim a launcher that is not registered yet. [verified] `scripts/UNLOCK.sh::run_step()` turns any non-zero apply into `FAILED - stopping, nothing further was changed`. [verified] On that path the message is false: the filesystem was remounted, an APK was written under `/system`, and a restart is now required. [verified] The correct next action is in the warning above it, not in the failure line. [inferred]

## Reverting developer options leaves developer options on

`scripts/lib/unlock.sh::DEV_SETTINGS` contains four settings and `scripts/lib/unlock.sh::dev_options_revert()` writes three of them back. [verified] `development_settings_enabled` is never set to 0, so the step cannot return to the state it found. [verified] The same function reads nothing back and returns 0 unconditionally, which is the opposite of the rule the file's own header states and of what `scripts/lib/unlock.sh::dev_options_apply()` does for every write. [verified]

## Revert runs against steps that were never applied

`scripts/UNLOCK.sh::revert_all()` calls every step's revert without consulting its state. [verified] On a device that was never unlocked this still enables the stock launcher and rewrites the home preference through `scripts/lib/unlock.sh::launcher_default_revert()`, and that function returns 1 when the stock launcher registers no home activity, which the summary then reports as a revert that finished with errors. [verified]

`scripts/lib/unlock.sh::cleanup_leftovers_revert()` warns that it cannot be undone and returns 0, so a revert that genuinely could not restore one step is still counted as clean. [verified]

## Repair does not check the hardware it is repairing

`scripts/UNLOCK.sh::main()` dispatches repair before `scripts/UNLOCK.sh::check_supported_device()`, correctly, since the failure leaves no adb. [verified] The consequence is that `scripts/lib/unlock.sh::repair_run()` will run against any device that answers. [inferred] On unrelated hardware the dispatcher component does not exist, so the checks fall through to the branch that reports nothing answering the vendor home intent and prints `scripts/lib/unlock.sh::repair_manual_instructions()`, which describes pad locations on this projector's board. [verified]

## The repair paths that matter most are unexercised

No scenario sets the emulator's absent-device knob together with `--repair`: the only use of `FAKE_ADB_NO_DEVICE` in the tree is in `tests/ui-tests.sh` against a front end. [verified] So the return of 2, and `scripts/lib/unlock.sh::repair_manual_instructions()` with it, is never run by the suite. [verified] The branch where nothing answers the vendor home intent is not covered either, because the repair scenario leaves the interceptor resolvable. [verified] The two covered scenarios both end in a return of 0. [verified]

A device listed on adb that cannot give root ends the run at the shared root gate instead, so the serial-console instructions are not reached in that case either. [verified] See [`device-access`](../device-access/README.md).

## An unrecognised state is applied rather than refused

`scripts/UNLOCK.sh::run_step()` names only `applied` and `blocked:*`. [verified] A state function that returned an error string, or an empty line because a device query came back silent, would fall through to apply. [inferred] `scripts/UNLOCK.sh::step_line()` does render such a value distinctly, so the status table and the dispatcher disagree about what is unrecognised. [verified]

## Package matching does not escape package names

`scripts/lib/unlock.sh::home_component_of()` escapes the dots in a package name before matching. [verified] `scripts/lib/unlock.sh::package_installed()`, `scripts/lib/unlock.sh::package_disabled()` and `scripts/lib/unlock.sh::package_path()` do not, and none of them anchors the start of the name. [verified] A package whose name is a suffix of another installed package's name would satisfy these checks. [inferred]

## The APK is whichever one sorts first

`scripts/lib/unlock.sh::launcher_apk()` returns the first existing match for `LAUNCHER_APK_GLOB` and stops. [verified] Glob expansion is ordered, not versioned, so with two versions of the launcher in the directory the lexicographically earlier filename is installed rather than the newer one. [inferred]

## Liveness is a fixed wall-clock guess

`scripts/lib/unlock.sh::launcher_runs()` waits `LAUNCHER_SETTLE_SECS`, three seconds by default, then checks once whether the process exists. [verified] A launcher that takes longer to crash passes, and a slow device that has not finished starting fails; there is no retry and no upper bound beyond that single sleep. [inferred]

## The library relies on a load order nothing checks

`scripts/lib/unlock.sh` calls the shared root helper and the `print_*` family without sourcing `scripts/lib/common.sh`, and reads `APK_DIR` with no default. [verified] `scripts/INSTALL_APP.sh` sources this library for its filesystem and package helpers and never defines `APK_DIR`, so the launcher-install path is not safe to call from there. [verified] Nothing in the library states or checks either requirement. [verified]

## Assertions are coupled to message text

Most scenarios in `tests/unlock-tests.sh` match substrings of operator output rather than device state. [verified] Rewording a refusal breaks the suite with no behaviour change, which trains a reader to edit the assertion instead of investigating. [inferred] This is recorded as a contract in [Contracts](CONTRACTS.md) because at the pin it is one, not because it is desirable. [inferred]

## One apply branch has no scenario

`scripts/lib/unlock.sh::launcher_default_apply()` refuses when the target launcher registers no home activity. [verified] Every sandbox in `tests/unlock-tests.sh` writes a sidecar that declares a home activity, so that branch is never entered. [verified]
