---
block: unlock
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Operations

## Start and stop

`scripts/UNLOCK.sh` is the only entry point. [verified] With no argument it prints the status table and then the interactive menu; `--status` reports and changes nothing, `--apply-all` runs every step and stops, `--revert` restores the stock launcher, `--repair` diagnoses a device that will not finish booting, and `--yes` suppresses the confirmations in the first two. [verified]

`--status` is the only mode exempt from the backup requirement, so it is the safe way to look at a device. [verified] Every other mode except `--repair` requires a device with root and a verified backup before it does anything, and `--repair` requires neither because the failure it addresses leaves no adb at all. [verified]

There is nothing to stop. A run is one pass: `scripts/UNLOCK.sh::apply_all()` returns on the first failing step, and the only deliberate wait is the settle sleep in `scripts/lib/unlock.sh::launcher_runs()`. [verified] The interactive loop ends on `q` and also returns cleanly when its prompt reaches end of input. [verified] Menu entry 5 issues a reboot directly rather than through the shared helpers, after a confirmation. [verified]

## Observe

All output goes through the shared `print_*` helpers, so stream routing and colour are decided in [`device-access`](../device-access/README.md); a caller capturing only one stream can lose refusals. [verified]

`scripts/UNLOCK.sh::show_status()` prints a section header, one line per step from `scripts/UNLOCK.sh::step_line()`, and a final line naming the current home screen. [verified] A step line carries one of four labels: done, todo, blocked with the cause appended to the description, or a question mark for a value the CLI does not recognise. [verified]

Read the last line carefully. It comes from `scripts/lib/unlock.sh::home_activity()`, the recorded preference, while the `launcher_default` row above it comes from `scripts/lib/unlock.sh::home_owner()`, which asks what actually wins the boot intent. [verified] On a device with an interceptor the two disagree by design: the row reads blocked while the home-screen line can still name a launcher. [inferred] The line is also empty when the preferred-activity dump yields no home entry, because the parser prints an empty result rather than a placeholder. [verified]

After a successful apply the run prints that all steps were applied and verified, followed by a warning that a restart is needed before the new home screen appears. [verified] `scripts/UNLOCK.sh::revert_all()` prints either a clean result or a note that the revert finished with errors, and then the status table in both cases. [verified]

Exit status is the summary an unattended caller should read: a failing step makes the script exit non-zero, and `--repair` exits with the value from `scripts/lib/unlock.sh::repair_run()`. [verified]

## Configuration and paths

Every override in the library resolves the same way: environment value if set and non-empty, otherwise the built-in default, evaluated once when the file is sourced. [verified]

| Name | Default at the pin | Evidence |
|---|---|---|
| `LAUNCHER_PKG` | the Projectivy package | `[verified]` |
| `LAUNCHER_NAME` | the name used in messages | `[verified]` |
| `LAUNCHER_APK_GLOB` | a glob matching the shipped APK | `[verified]` |
| `LAUNCHER_SYSTEM_DIR` | a directory under `/system/app` | `[verified]` |
| `HOME_DISPATCHER_PKG`, `HOME_DISPATCHER_COMP` | the vendor component that owns the home intent | `[verified]` |

`LAUNCHER_SETTLE_SECS` is the exception: it is read inside `scripts/lib/unlock.sh::launcher_runs()` at call time rather than at load, and defaults to three seconds. [verified]

`scripts/lib/unlock.sh::STOCK_LAUNCHER` and `scripts/lib/unlock.sh::FALLBACK_HOME_COMP` are plain assignments with no environment form, so the launcher being replaced and the rescue home component cannot be changed without editing the file. [verified]

`APK_DIR` is resolved by the entry script, not the library: `scripts/UNLOCK.sh` takes the environment value if set, otherwise a sibling directory of the script's own location derived from `BASH_SOURCE`. [verified] The library reads it with no default of its own. [verified]

Two paths are derived rather than configured. The staged copy goes to a temporary directory on the device, because a push runs as the shell user and cannot write `/system` even when it is mounted writable. [verified] The destination filename is built from the basename of `LAUNCHER_SYSTEM_DIR`, so renaming that directory renames the installed APK with it. [verified]

The mountpoint to remount is resolved, never assumed: `scripts/lib/unlock.sh::system_mountpoint()` returns `/system` when the mount table lists it and the root filesystem otherwise. [verified]

## Failure and recovery

**A step shows blocked.** There are two causes and they need different actions, so read the reason rather than the label. [verified]

`blocked:install the launcher first` means `scripts/lib/unlock.sh::package_installed()` did not find the target package. [verified] This check is the first line of `scripts/lib/unlock.sh::launcher_default_state()` and runs before the interceptor is queried, so this cause is reported whether or not an interceptor exists. [verified] The fix is the `launcher_present` step, either by running the whole unlock or by selecting that step from the menu. [inferred] Nothing done at the device's own home-screen chooser can clear this one: a chooser selects among installed launchers and cannot install a missing package. [inferred]

The longer block, naming a component that `owns the home intent on this firmware`, means the package is present and something else wins the intent. [verified] No command on this platform writes a preference covering the category the firmware adds, which is why the step refuses instead of trying. [verified] The fix is at the device: press home, pick the launcher, confirm the always option, exactly as the message says. [verified] Do not disable the component named in that message. Disabling it is what leaves the home intent with no candidate and stops the device booting; see [BOOT_DEADLOCK](../../BOOT_DEADLOCK.md) and [Invariants](INVARIANTS.md). [verified]

**The install was refused and the step failed.** The failure line from `scripts/UNLOCK.sh::run_step()` says nothing further was changed, and on this path that is wrong. [verified] Check the warning above it: if the fallback copy succeeded, the APK is in place under `/system`, the launcher registers only on the next boot, and the correct action is to restart the projector and run the unlock again. [verified] If the copy itself failed the run says so separately, naming either the staging step or the copy. [verified]

**The launcher started and then died.** The run stops before any preference is written and says so; the stock launcher is untouched and the device still has a home screen. [verified] This is a launcher problem, not a toolkit one. [inferred]

**The projector stops at the vendor logo and never finishes booting.** This is the failure `--repair` exists for, and the one that cannot be diagnosed from the disabled-package list. [verified] With a device on adb, repair checks the dispatcher component, re-enables it if it is disabled, then confirms something answers the vendor home intent, and returns 0 whether it fixed anything or found nothing to fix. [verified] It returns 1 when it cannot re-enable the component or when nothing answers that intent. [verified]

With no device on adb it returns 2 and prints the recovery procedure for a serial console, including where the pads are on this board. [verified] Those printed commands are for a human at the console, not for this toolkit to run, and neither that path nor the instructions themselves are exercised by any suite. [verified] A device that is listed but cannot give root does not reach them: the run ends at the shared root gate instead. [verified] See [BOOT_DEADLOCK](../../BOOT_DEADLOCK.md) for the console setup and photographs.

**After a revert.** Developer options stay enabled, because `scripts/lib/unlock.sh::dev_options_revert()` restores three of its four settings. [verified] `cleanup_leftovers` cannot be undone at all and says so while still counting as a successful revert, so a clean revert summary does not mean every step was restored. [verified] Both are in [Gaps](GAPS.md).
