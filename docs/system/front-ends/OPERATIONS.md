---
block: front-ends
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Operations

## Start and stop

Both front ends are started directly and take no arguments. `scripts/PROJECTOR.sh::main()` and `scripts/TOOLS.sh::main()` both pass `"$@"` but neither parses an option, so anything supplied on the command line is ignored. [verified]

```sh
bash scripts/PROJECTOR.sh
bash scripts/TOOLS.sh
```

Both must be run from the directory that holds, or should hold, the backup directories. `scripts/PROJECTOR.sh` captures the working directory once at load into `WORK_DIR` and uses it for backup discovery, the progress log and the working directory of every child; it never re-reads it, so a directory change during a session has no effect. [verified]

Preconditions differ. `scripts/PROJECTOR.sh::main()` checks only that `adb` is on `PATH` and exits 1 with an install hint otherwise, then enters the loop and degrades its own display when no device answers. [verified] `scripts/TOOLS.sh::main()` calls `scripts/lib/common.sh::require_device()` with `false`, which exits before the menu when ADB or the device is missing and does not require root. [verified] Neither front end requires a backup to start. [verified]

Exit paths at the pin: `q` or `Q` in either, `0` additionally in `scripts/TOOLS.sh`, end of input in `scripts/PROJECTOR.sh` (status 0), and end of input in `scripts/TOOLS.sh` through errexit (status 1). [verified] Interrupting during a `scripts/PROJECTOR.sh` backup leaves the child's fate to signal delivery, since nothing detaches it; see [Gaps](GAPS.md). [verified]

Option `5` in `scripts/PROJECTOR.sh` is a deliberate no-op: the loop calls `scripts/PROJECTOR.sh::detect_state()` at the top of every iteration, so returning to the menu is the refresh. [verified]

## Observe

The `scripts/PROJECTOR.sh` header is the block's main status surface and is redrawn from scratch each iteration. [verified] It reports four things, each from a named source:

| Field | Source | Evidence |
|---|---|---|
| device presence and model | `adb devices` matched against a trailing `device`, then `getprop ro.product.model` | `[verified]` |
| root | `scripts/lib/common.sh::check_root_access()` | `[verified]` |
| backup, as none, incomplete or verified, with size and directory | glob of `projector-backup-*` plus `scripts/lib/common.sh::verify_backup_dir()` | `[verified]` |
| launcher, as unknown, locked, unlocked or blocked with a reason | `scripts/lib/unlock.sh::launcher_default_state()`, with `scripts/lib/unlock.sh::home_activity()` shown when applied | `[verified]` |

The launcher and root fields are only populated when root is available, because `scripts/PROJECTOR.sh::detect_state()` computes them inside the root branch; without root the launcher reads unknown even on a connected device. [verified] The blocked state is displayed with its reason text taken from everything after the first colon, so the explanation the unlock block produces is what an operator reads here. [verified]

During a backup, the screen shows a bar, pulled and total bytes, a block counter, a transfer rate, an estimate, a stall count when non-zero, and the last eight log lines matching the INFO, OK, WARN, ERROR or STEP prefixes truncated to 70 columns. [verified] It refreshes every two seconds, and the rate is computed as the byte delta over that fixed interval. [verified]

`scripts/TOOLS.sh` echoes the exact command it is about to send before sending it, then prints the device's combined output, then a result line. [verified] Its four diagnostic keys are read only: `i` for properties, storage and memory, `h` for CPU and display, `l` for launcher activities, `s` for three named services checked with `ps`. [verified]

## Configuration and paths

Both scripts resolve their own location the same way, by `cd`-ing to the directory of `BASH_SOURCE[0]` and taking `pwd`, then sourcing `lib/common.sh` beneath it. [verified] Neither consults `TOOLKIT_SCRIPTS`; that variable is a test harness resolver applied from outside when choosing which checkout to launch. [verified]

`scripts/PROJECTOR.sh` sets `APK_DIR` with the precedence: existing environment value, otherwise `<script dir>/../apks`. [verified] It does this before sourcing `scripts/lib/unlock.sh`, so the library observes the resolved value. [verified] The unlock and backup children are separate processes and inherit the exported environment, not this assignment, unless `APK_DIR` was already exported by the caller. [inferred]

The backup progress log is a fixed name, `.backup-progress.log`, in the startup working directory, truncated at the start of each run. [verified] Backup directories are discovered by the fixed glob `projector-backup-*` and must contain `full-system-backup.img` to be considered at all. [verified]

`scripts/TOOLS.sh` has one configuration constant, `scripts/TOOLS.sh::STOCK_LAUNCHER_PKG`, written as a literal rather than read from `scripts/lib/unlock.sh::STOCK_LAUNCHER`, which holds the same package name in the block that owns launcher identity. [verified] The two are independent copies and nothing checks that they agree. [inferred]

Colour is unconditional in both front ends: the constants from [`device-access`](../device-access/README.md) are emitted with no terminal or `NO_COLOR` test, which is why the harness strips ANSI codes from captured output before matching. [verified] `scripts/PROJECTOR.sh` also strips ANSI from the backup log before parsing it, since the child writes coloured output into a file. [verified]

## Failure and recovery

A failed backup leaves the log in place and the screen names it. The recovery instruction is printed by the front end itself: `scripts/PROJECTOR.sh::"Re-running resumes from the last completed block."` [verified] Whether a resume is possible is decided by [`backup`](../backup/README.md), not here. [inferred]

The stall counter is informational and the front end takes no action on it; the retry behaviour it counts belongs to the backup block. [verified] A stall count above zero is labelled as expected on this device. [verified]

When the menu offers no unlock, the cause is one of two states and the header distinguishes them: no verified backup, shown as the backup field reading none or incomplete, or an already applied launcher, shown as unlocked. [verified] A blocked launcher state carries its own reason string and is not something this block can clear. [verified]

If `scripts/TOOLS.sh` refuses to reset the launcher, it is because the stock launcher is disabled, and the remedy it prints is to run the revert in [`unlock`](../unlock/README.md) rather than to retry here. [verified]

Two stuck states have no handling in this block. A child process that blocks on a prompt this block did not anticipate will consume the next queued keystroke rather than hang, because stdin is shared with the foreground children. [inferred] A backgrounded backup whose parent has exited is not tracked anywhere: there is no pid file and no recovery path, so identify such a process before acting on it rather than matching on a command pattern. [inferred]
