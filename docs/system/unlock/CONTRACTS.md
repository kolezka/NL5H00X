---
block: unlock
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Contracts

## A step is four functions sharing one name

`scripts/lib/unlock.sh::UNLOCK_STEPS` lists the step names in apply order: `dev_options`, `launcher_present`, `launcher_default`, `cleanup_leftovers`. [verified] Each name must have `<step>_describe`, `<step>_state`, `<step>_apply` and `<step>_revert`, the shape the file's own header states. [verified] Nothing enumerates the quadruple; the CLI dispatches by building the function name from the step name, so a missing function is a command that does not exist rather than a checked error. [verified]

Adding a step means adding four functions and one array entry. [inferred]

enforcement: `tests/unlock-tests.sh::"the full unlock works and survives a restart"` and `tests/unlock-tests.sh::"undo puts the stock launcher back"` (every step's describe, state, apply and revert is reached end to end)

## The state vocabulary is three values, and only two are recognised

A state function returns `applied`, `not-applied`, or `blocked:` followed by a reason. [verified] `scripts/UNLOCK.sh::run_step()` matches only `applied` and `blocked:*`; everything else, including `not-applied` and any unexpected string, falls through to apply. [verified] `scripts/UNLOCK.sh::step_line()` renders an unrecognised value as a question mark rather than refusing it, and `scripts/UNLOCK.sh::all_applied()` requires the literal `applied`. [verified]

enforcement: `scripts/UNLOCK.sh::run_step()` and `scripts/UNLOCK.sh::step_line()` (dispatch and rendering); no test asserts on an out-of-vocabulary value, see [Gaps](GAPS.md)

## Blocked carries a cause, and there is more than one cause

The text after `blocked:` is operator-facing. `scripts/UNLOCK.sh::step_line()` appends it to the description in the status table and `scripts/UNLOCK.sh::run_step()` prints it after `cannot run`. [verified]

`scripts/lib/unlock.sh::launcher_default_state()` has two blocked paths and they do not have the same fix. Its first line returns `blocked:install the launcher first` when `scripts/lib/unlock.sh::package_installed()` says the package is absent, and that check runs before the interceptor is ever queried. [verified] Only when the package is present does it ask `scripts/lib/unlock.sh::home_owner()`, and only then can it return the longer block naming the component that `owns the home intent on this firmware`. [verified] Guidance that offers the device chooser answers the second cause and not the first: no chooser selection installs a package that is not there. [inferred] Recovery for both is in [Operations](OPERATIONS.md).

enforcement: `scripts/lib/unlock.sh::launcher_default_state()` (ordering of the two returns); `tests/unlock-tests.sh::"a firmware that owns HOME is handed back to the user, not fought"` covers the interceptor cause only

## Apply is not believed, the state function is

`scripts/UNLOCK.sh::run_step()` re-runs the state function after a successful apply and fails the step when the answer is not `applied`, printing that the step `reported success but the device still says` the state it read. [verified] The library repeats the pattern inside each apply: `scripts/lib/unlock.sh::dev_options_apply()` reads each setting back, and `scripts/lib/unlock.sh::launcher_default_apply()` re-asks `scripts/lib/unlock.sh::home_owner()` after writing the preference. [verified]

A zero return from an apply function is therefore never sufficient to call a step done. [inferred]

enforcement: `scripts/UNLOCK.sh::run_step()` (post-apply read-back)

## The `/system/app` fallback reports not-done on purpose

`scripts/lib/unlock.sh::launcher_present_apply()` tries `adb install` first and drops to a staged copy into `LAUNCHER_SYSTEM_DIR` when the device refuses. [verified] It returns 1 after a successful copy, warning that the launcher `will only register after a restart`, because the package is not registered until the next boot and `scripts/lib/unlock.sh::launcher_present_state()` would still read `not-applied`. [verified]

So a non-zero exit from this step is not proof that nothing changed on the device. [inferred]

enforcement: `tests/unlock-tests.sh::"a device that refuses installs still gets the launcher"` (asserts the APK lands in `/system/app`, that a restart is mentioned, and that the run does not report success)

## Failure stops the apply, failure does not stop the revert

`scripts/UNLOCK.sh::apply_all()` returns on the first failing step. [verified] `scripts/UNLOCK.sh::revert_all()` walks `UNLOCK_STEPS` backwards, runs every revert regardless of the previous one's result, records that at least one failed, prints the state table, and returns that flag. [verified]

enforcement: `scripts/UNLOCK.sh::apply_all()` and `scripts/UNLOCK.sh::revert_all()` (loop control)

## Operator-facing message text is a contract surface

`tests/unlock-tests.sh` asserts on message fragments rather than on state in most scenarios, so the wording of a refusal is part of this block's interface and rewording one breaks the suite without changing behaviour. [verified] The fragments pinned at the pin include `not usable as a home screen` from `scripts/lib/unlock.sh::launcher_runs()`, `owns the home intent on this firmware` and `CATEGORY_SETUP_WIZARD` and the chooser instruction beginning `press HOME on the device, pick` from `scripts/lib/unlock.sh::launcher_default_state()` and `scripts/lib/unlock.sh::launcher_default_apply()`, the install failure relayed by `scripts/lib/unlock.sh::"The device refused a normal install"`, the restart warning in `scripts/lib/unlock.sh::launcher_present_apply()`, `is disabled - this is what stops the device booting` and `Nothing to repair` from `scripts/lib/unlock.sh::repair_run()`, `Unsupported device` from `scripts/UNLOCK.sh::check_supported_device()`, and `CURRENT STATE` from `scripts/UNLOCK.sh::show_status()`. [verified]

One matched fragment is not produced here at all: the backup refusal comes from the shared helper, so that scenario pins wording owned by [`device-access`](../device-access/README.md). [verified]

enforcement: `tests/unlock-tests.sh::"a launcher that does not actually run is never trusted"`, `tests/unlock-tests.sh::"a firmware that owns HOME is handed back to the user, not fought"`, `tests/unlock-tests.sh::"a device that refuses installs still gets the launcher"`, `tests/unlock-tests.sh::"a different projector model is refused"`, `tests/unlock-tests.sh::"--repair fixes a projector that will not finish booting"` and `tests/unlock-tests.sh::"--repair says so when there is nothing to repair"` (substring matches on captured output)

## The command line and its modes

`scripts/UNLOCK.sh::main()` accepts `--status`, `--apply-all`, `--revert`, `--repair`, `--yes` or `-y`, and `-h` or `--help`; with no mode flag it runs the interactive menu. [verified] An unknown option prints an error, prints `scripts/UNLOCK.sh::usage()` and exits 1. [verified] `--yes` sets `scripts/UNLOCK.sh::ASSUME_YES`, which skips the confirmation prompts in apply and revert but changes nothing else. [verified]

enforcement: `scripts/UNLOCK.sh::main()` (argument loop); `tests/unlock-tests.sh::"--status changes nothing and needs no backup"` covers the read-only mode

## Preconditions run in a fixed order, and repair runs before all of them

`scripts/UNLOCK.sh::main()` dispatches repair and exits before any precondition, by design for a failure that leaves no adb. [verified] Every other mode then runs `scripts/lib/common.sh::require_device()` with root required, then `scripts/UNLOCK.sh::check_supported_device()`, then `scripts/lib/common.sh::require_backup()` unless the mode is `--status`. [verified]

`scripts/UNLOCK.sh::check_supported_device()` matches `ro.product.model` or `ro.product.device` against `scripts/UNLOCK.sh::SUPPORTED_DEVICES`, which holds `NL5H00X` and `NL5H00X_TP`, and exits 1 on no match. [verified] It reads those two properties with plain `adb shell getprop`, not through the shared root helper, so it is outside that helper's root handling even though root has already been established by the preceding call. [verified]

enforcement: `tests/unlock-tests.sh::"a different projector model is refused"` and `tests/unlock-tests.sh::"applying without a backup is refused"` (precondition refusals); `tests/unlock-tests.sh::"--status changes nothing and needs no backup"` (the backup exemption)

## Repair returns three distinct codes

`scripts/lib/unlock.sh::repair_run()` returns 2 when `adb devices` lists no device, after printing the serial-console instructions. [verified] It returns 1 when the home dispatcher component cannot be re-enabled, and also when nothing answers the vendor home intent, printing `Nothing answers the vendor home intent` and the instructions again. [verified] It returns 0 both when it repaired something and when there was nothing to repair. [verified] `scripts/UNLOCK.sh::main()` passes that value through with an explicit exit. [verified]

Only the two zero paths are exercised by the suite; see [Gaps](GAPS.md). [verified]

enforcement: `tests/unlock-tests.sh::"--repair fixes a projector that will not finish booting"` and `tests/unlock-tests.sh::"--repair says so when there is nothing to repair"` (return 0 paths only)

## Launcher and dispatcher identity is configuration, not code

`LAUNCHER_PKG`, `LAUNCHER_NAME`, `LAUNCHER_APK_GLOB`, `LAUNCHER_SYSTEM_DIR`, `HOME_DISPATCHER_PKG` and `HOME_DISPATCHER_COMP` all read an environment value before falling back to a default, so a different replacement launcher needs no edit. [verified] `scripts/lib/unlock.sh::STOCK_LAUNCHER` and `scripts/lib/unlock.sh::FALLBACK_HOME_COMP` are plain assignments with no override, so the launcher being replaced and the rescue home component are fixed at the pin. [verified] Precedence and defaults are in [Operations](OPERATIONS.md).

enforcement: `scripts/lib/unlock.sh::LAUNCHER_PKG` and `scripts/lib/unlock.sh::STOCK_LAUNCHER` (assignment form, load time)

## The library expects its caller to have loaded the shared helpers and set APK_DIR

`scripts/lib/unlock.sh::_UNLOCK_SH_LOADED` makes the file load once. [verified] It defines no helper of its own for output, root access or backups: it calls `scripts/lib/common.sh::adb_root_exec()`, `scripts/lib/common.sh::require_device()` and the `print_*` family without sourcing that file, so a caller must load `scripts/lib/common.sh` first. [verified] All three callers at the pin do. [verified]

`scripts/lib/unlock.sh::launcher_apk()` reads `APK_DIR` with no default of its own, and the library never sets it. [verified] `scripts/UNLOCK.sh` and `scripts/PROJECTOR.sh` define it before sourcing; `scripts/INSTALL_APP.sh` does not. [verified]

enforcement: `scripts/lib/unlock.sh::_UNLOCK_SH_LOADED` (include-once guard); the load order and `APK_DIR` requirement are `convention`, see [Gaps](GAPS.md)
