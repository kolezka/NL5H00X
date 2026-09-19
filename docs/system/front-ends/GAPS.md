---
block: front-ends
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## The backup screen promises more than the code arranges

The progress screen prints `scripts/PROJECTOR.sh::"the backup keeps running even if you close this"`, but nothing detaches the child. `run_backup` starts a plain background subshell, with no nohup, no setsid and no disown. [verified]

Measured on this machine: a background subshell started from a non-interactive bash script shares the script's process group, so anything delivered to that group, a terminal hangup or a Ctrl-C, reaches the backup too. [verified]

What does survive is the work, not the process. The partial image and the log stay on disk, and `scripts/MAKE_BACKUP.sh::find_incomplete_backup_dir()` lets the next run continue from the last completed block, which is what the failure text tells the person. [verified]

The honest version of that line would promise resume rather than survival. No test in `tests/ui-tests.sh::"PROJECTOR.sh runs a backup to a verified result"` signals the front end or closes its terminal, so the claim as printed is unchecked. [verified]

## The refusal text describes an unlock that no longer exists

`run_unlock` justifies its gate with `scripts/PROJECTOR.sh::"the unlock disables your only working home screen"`. At this pin the unlock disables nothing: it reaches its goal with a preference alone, recorded in `scripts/lib/unlock.sh::"nothing is disabled"`. [verified]

The gate itself is still right, because the unlock still changes which launcher the device boots into. Since the quoted cause is a disable that no longer happens, only the reason is stale, and a stale reason in a safety message is what a reader discounts the next time. [inferred]

## count_menu_items is computed and never used

`main_menu` assigns the result of `scripts/TOOLS.sh::count_menu_items()` to a local and never reads it. Section numbering is driven by the raw array lengths instead. [verified]

So the toolkit has two ways to count the menu, and the one that skips empty entries is the one nothing exercises outside the test suite. [verified]

## Menu numbering and dispatch count differently

`show_menu_section` and `get_menu_entry` both skip empty array elements, while `main_menu` advances the starting number by the raw array length. [verified]

The two paths disagree only when an element is empty, so an empty element would leave a hole between what is printed and what a number dispatches to, and every entry after it would run the wrong command. [inferred]

No test in `tests/ui-tests.sh` builds a menu array with an empty element, so nothing would catch it. [verified]

## The stock launcher package name lives in two blocks

`scripts/TOOLS.sh::STOCK_LAUNCHER_PKG` repeats the value that `scripts/lib/unlock.sh::STOCK_LAUNCHER` already holds, because `scripts/TOOLS.sh` does not source the unlock library. [verified]

The home component lookup is duplicated with it: `reset_default_launcher` runs the same query that `scripts/lib/unlock.sh::home_component_of()` provides. Two places to change, and the front end copy is unprivileged while the library copy goes through the root helper. [verified]

The vendor component names in the four menu arrays have the same shape of problem and no override at all, unlike the launcher package in the unlock block, which reads from the environment. A missing component is reported per entry rather than being configurable. [verified]

## Arguments and end of input are handled unevenly

Neither script parses arguments, so a mistyped flag is silently ignored rather than reported. [verified]

At end of input the two differ. `scripts/PROJECTOR.sh` guards its read and exits 0. `scripts/TOOLS.sh` runs under `scripts/TOOLS.sh::"set -euo pipefail"` with an unguarded read, so end of input exits 1 with no message. Measured both patterns on this machine against empty input: status 0 and status 1. [verified]

## The backup estimate hardcodes a transfer rate

The minutes shown next to the backup entry divide the device size by a fixed constant that works out to about 10 MB per second, with no derivation recorded in the code. [verified]

The live screen computes a real rate from the file growth, so only the pre flight estimate on the menu is affected, and it drifts silently on a slower link. [verified]
