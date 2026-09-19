---
block: front-ends
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

Start the guided front end from the directory that holds the backups, because that directory is where it looks and writes: `bash scripts/PROJECTOR.sh`. [verified]

It checks for adb first and exits 1 with an install hint if adb is missing. It does not require a connected device: with nothing attached it draws the header, reports the device as not connected, and offers the menu with the connect hint `adb connect <ip>:5555`. [verified]

`bash scripts/TOOLS.sh` behaves differently at startup. It calls the shared guard with root not required, which still exits 1 when adb is missing or no device answers, so the menu never opens without a device. No entry in it elevates: there is no su call anywhere in the file, and every command goes through a plain `adb shell`. [verified]

Quit with q from either menu. `scripts/PROJECTOR.sh` also exits 0 on end of input, while `scripts/TOOLS.sh` exits 1 there without a message. [verified]

There is no stop for a running backup other than signalling it. While `run_backup` is polling, the menu does not read input, and the child shares the front end's process group, so a Ctrl-C or a closed terminal reaches both. See [GAPS](GAPS.md) for what that costs. [verified]

## Observe

The header is the status surface: device model, root yes or no, backup verified, incomplete or none with its size and directory, and the launcher state. [verified]

During a backup the screen shows a percentage bar against the device size, bytes pulled, the current block out of the total, a rate with an estimate, and a stall count when the transfer has been killed and retried. [verified]

The full child output is in `.backup-progress.log` in the invocation directory, and the last eight tagged lines are shown live. On failure the screen prints the last five ERROR lines, the log path and the fact that re-running resumes. [verified]

Sizes are printed in decimal units on purpose, so that the number matches the manifest and the docs for the same device rather than reading as a different one. [verified]

The minutes shown next to the backup menu entry are a pre flight estimate derived from the device size and a fixed rate, not a measurement. [verified]

## Configuration and paths

The script directory is resolved from `BASH_SOURCE` at startup, and both front ends locate their libraries and the scripts they delegate to from it. [verified]

Since every internal path is built from that value and none is absolute, the scripts work from a copy in another location provided `lib/` and the delegated scripts move with them. [inferred]

The working directory is separate from that. `scripts/PROJECTOR.sh::WORK_DIR` is the current directory at startup, captured once, and it is where backup directories matching `projector-backup-*` are read, where the progress log is written, and the directory both subprocesses are started in. [verified]

`APK_DIR` has one resolver with two steps: the environment value if set, otherwise the `apks` directory beside the script directory. `scripts/PROJECTOR.sh` sets it before sourcing the unlock library, which is the consumer, so a launcher APK kept outside the repo works without editing anything. [verified]

Nothing else is configurable from this block. The launcher package, its name, its APK glob and its system directory are the unlock block's environment surface, and the chunk size is the backup block's. Both are inherited by the subprocesses because they are started as plain children. [verified]

`scripts/TOOLS.sh` reads no environment at all. Its stock launcher package and all nineteen device commands are literals in the file. [verified]

## Failure and recovery

A backup that does not finish leaves its directory and partial image in place, and the front end says so along with the log path. Re-running entry 1 resumes from the last completed block rather than starting over. [verified]

An unlock refused for a missing or incomplete backup changes nothing, and the fix is to run the backup first. A revert or a status driven from the menu is subject to the unlock block's own gates, so a revert without a verified backup exits there instead. [verified]

A launcher shown as blocked in the header carries its reason in the same line, and the detailed view behind key 4 is the read only expansion of it. Neither is fixable from this block. [verified]

When the launcher reset in `scripts/TOOLS.sh` refuses because the stock launcher is disabled, the recovery is the command it names, `UNLOCK.sh --revert`, which re-enables the package first and then verifies the home screen. [verified]
