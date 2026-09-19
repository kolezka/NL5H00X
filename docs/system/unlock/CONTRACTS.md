---
block: unlock
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## Step function quadruple

Every step is four shell functions with the same shape, named from the step id: `_describe` prints one line, `_state` prints the current state, `_apply` makes the change, `_revert` puts it back. [verified] The driver builds the function name from the id and calls it, so adding a step means defining the four functions and adding the id to the list, with no change to the driver. [verified]

enforcement: `scripts/UNLOCK.sh::run_step()` (runtime dispatch by constructed name)

## Step list and apply order

`scripts/lib/unlock.sh::UNLOCK_STEPS` is the whole set and the apply order: dev_options, launcher_present, launcher_default, cleanup_leftovers. [verified] Apply walks it forwards and stops at the first failure; revert walks the same array backwards so the stock launcher is restored before the replacement's files are removed. [verified]

enforcement: `scripts/UNLOCK.sh::revert_all()` (reverse iteration over the same array)

## Step state vocabulary

A state function prints exactly one of three things: `applied`, `not-applied`, or `blocked:` followed by a human readable reason. [verified] The driver treats an unrecognised value as an error rather than as progress. [verified]

enforcement: `scripts/UNLOCK.sh::step_line()` (renders each case, unknown falls through to an error label)

## Command line surface

The tool accepts `--status`, `--apply-all`, `--revert`, `--repair`, `--yes` or `-y`, and `-h` or `--help`. [verified] No argument means the interactive menu. [verified] An unknown option prints usage and exits 1. [verified]

enforcement: `scripts/UNLOCK.sh::main()` (argument loop with an explicit unknown-option branch)

## Repair exit status

`--repair` exits with the status of its own run: 0 when the device is healthy or was repaired, 1 when the home intent still has no candidate or the component could not be re-enabled, 2 when no device answers adb. [verified] Status 2 is the case that prints serial console instructions instead of acting. [verified]

enforcement: `scripts/lib/unlock.sh::repair_run()` (explicit return values on every path)

## Launcher selection is overridable

The launcher choice is four environment-overridable variables: `scripts/lib/unlock.sh::LAUNCHER_PKG`, `scripts/lib/unlock.sh::LAUNCHER_NAME`, `scripts/lib/unlock.sh::LAUNCHER_APK_GLOB` and `scripts/lib/unlock.sh::LAUNCHER_SYSTEM_DIR`. [verified] Nothing else in either owned file names Projectivy, so a different launcher needs no edit. [verified]

enforcement: `scripts/lib/unlock.sh::LAUNCHER_PKG` (environment-first default assignment)

## Home dispatcher identity is overridable, the stock launcher is not

`scripts/lib/unlock.sh::HOME_DISPATCHER_PKG` and `scripts/lib/unlock.sh::HOME_DISPATCHER_COMP` read from the environment first, so repair can be pointed at a different vendor component. [verified] `scripts/lib/unlock.sh::STOCK_LAUNCHER` and `scripts/lib/unlock.sh::FALLBACK_HOME_COMP` are plain assignments and are not overridable. [verified]

enforcement: `scripts/lib/unlock.sh::HOME_DISPATCHER_COMP` (environment-first default assignment)

## Supported hardware gate

Every mode except `--repair` refuses hardware it was not written for. A device passes only when ro.product.model or ro.product.device matches an entry in `scripts/UNLOCK.sh::SUPPORTED_DEVICES`, otherwise the tool exits 1 before any change. [verified]

enforcement: `scripts/UNLOCK.sh::check_supported_device()` and `tests/unlock-tests.sh::"refuses hardware it was not written for"`

## Backup precondition

Any mode that can change the device requires a verified backup first. [verified] `--status` is exempt because it only reads, and `--repair` is exempt because the failure it exists for leaves no working device to have made a backup from. [verified]

enforcement: `scripts/UNLOCK.sh::main()` and `tests/unlock-tests.sh::"refuses to modify anything without a verified backup"`
