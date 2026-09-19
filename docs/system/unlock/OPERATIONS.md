---
block: unlock
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

There is no daemon. `scripts/UNLOCK.sh` runs once, does what the mode asks, and exits. [verified]

| Invocation | What it does | Gates it passes |
|---|---|---|
| no argument | Prints state, then the interactive menu | device, hardware, backup |
| `--status` | Prints state and changes nothing | device, hardware |
| `--apply-all` | Applies every step in order, stops at the first failure | device, hardware, backup |
| `--revert` | Walks the steps backwards restoring the stock launcher | device, hardware, backup |
| `--repair` | Diagnoses a projector that never finishes booting | none |
| `--yes` or `-y` | Skips confirmation prompts, for scripting | modifier, not a mode |

The gates run in a fixed order inside `scripts/UNLOCK.sh::main()`: repair is dispatched first and exits, then root and device, then the hardware check, then the backup check for every mode except status. [verified] All three gates exit the process rather than returning a status. [verified]

The interactive menu adds one action the flags do not have: option 5 reboots the projector after a confirmation. [verified] Option 2 runs a single step through the same driver as apply-all, so a single step is verified the same way. [verified]

Applying does not take effect on screen until the projector restarts, and `scripts/UNLOCK.sh::apply_all()` says so at the end rather than implying the home screen has already changed. [verified]

## Observe

`--status` is the observability surface. It prints one line per step with a state label and the step's own description, then a "home screen now" line. [verified] A `blocked:` step prints its reason inline next to the description, so the reason a step cannot run is visible without running it. [verified]

Read the per-step lines, not the headline. The headline comes from the recorded preference while the launcher_default step decides on the resolver's answer, and the two can disagree; see GAPS. [verified]

Step output during a run is prefixed by the shared print helpers, and warnings and errors go to stderr while status and success go to stdout. [verified] A failing step prints which read-back disagreed with the command, not just that something failed. [verified]

## Configuration and paths

Every configurable value is an environment-first shell default, read at the time the library is sourced unless noted. [verified]

| Variable | Precedence | Default |
|---|---|---|
| `scripts/lib/unlock.sh::LAUNCHER_PKG` | environment, else default | com.spocky.projengmenu |
| `scripts/lib/unlock.sh::LAUNCHER_NAME` | environment, else default | Projectivy |
| `scripts/lib/unlock.sh::LAUNCHER_APK_GLOB` | environment, else default | projectivy*.apk |
| `scripts/lib/unlock.sh::LAUNCHER_SYSTEM_DIR` | environment, else default | /system/app/Projectivy |
| `scripts/lib/unlock.sh::LAUNCHER_SETTLE_SECS` | environment, else default, read at call time | 3 |
| `scripts/lib/unlock.sh::HOME_DISPATCHER_PKG` | environment, else default | com.newlink.wtprovision |
| `scripts/lib/unlock.sh::HOME_DISPATCHER_COMP` | environment, else default | com.newlink.wtprovision/.MainActivity |
| `scripts/UNLOCK.sh::APK_DIR` | environment, else the directory beside the script | the apks directory next to scripts |

Four values are fixed and cannot be overridden: `scripts/lib/unlock.sh::STOCK_LAUNCHER`, `scripts/lib/unlock.sh::FALLBACK_HOME_COMP`, `scripts/lib/unlock.sh::LEFTOVERS` and `scripts/UNLOCK.sh::SUPPORTED_DEVICES`. [verified]

Three resolvers compute a value rather than holding one:

`scripts/lib/unlock.sh::launcher_apk()` expands the glob inside the APK directory and returns the first regular file that matches, so a version bump needs no edit. [verified] It returns failure when nothing matches, and the step reports which directory and which glob it looked for. [verified]

`scripts/lib/unlock.sh::launcher_component()` asks the device which component the chosen package registers for HOME, by way of `scripts/lib/unlock.sh::home_component_of()`. [verified] Nothing is hardcoded, and that matters: on this firmware the stock launcher's HOME entry is not the activity a user sees, so a hardcoded component would have broken the revert path on the first device it was tried on. [historical: recorded in scripts/lib/unlock.sh]

`scripts/lib/unlock.sh::system_mountpoint()` reads /proc/mounts and answers /system when /system is its own mount, otherwise /. [verified] This projector is system-as-root, so the answer is / and a remount aimed at /system fails outright. [verified] `scripts/lib/unlock.sh::system_is_rw()` reads the positional options field of the same file rather than matching "rw" anywhere in the output of `mount`. [verified]

## Failure and recovery

**A step reports `blocked:`.** Only launcher_default produces this, and only when a component owns the vendor home intent. [verified] Nothing was changed. The route out is on the device: press HOME, pick the launcher, confirm "Always". [verified] Re-run `--status` afterwards to confirm. [verified]

**The device refuses a normal install.** `scripts/lib/unlock.sh::launcher_present_apply()` falls back to copying the APK into the system app directory, staging it through /data/local/tmp first because the shell user cannot write there even after a remount. [verified] It then returns failure on purpose, because the package only registers on the next boot and reporting success would be a lie. [verified] Restart the projector and re-run. [verified]

**A step reports success and the device disagrees.** `scripts/UNLOCK.sh::run_step()` stops the run and names the state the device actually reports. [verified] Nothing further is attempted. [verified]

**The unlock needs undoing.** `--revert` restores the stock launcher first and removes the replacement's files afterwards. [verified] One step cannot be undone: `scripts/lib/unlock.sh::cleanup_leftovers_revert()` says so rather than pretending, because the folders it deleted were duplicates of files that remain elsewhere on the device. [verified]

**The projector stops at the vendor logo and never boots.** This is the failure the block is built to avoid and the one `--repair` exists for. [verified] Run `--repair` with the projector connected: it checks whether the home dispatcher component is disabled, re-enables it, and then confirms the vendor home intent resolves to something. [verified] When adb cannot reach the device, it prints the serial console procedure instead of acting, including where the pads are and the exact commands to type. [verified] Do not reboot before the resolve check names a component; recovery is confirmed by a human watching the screen, not over adb. [verified]
