---
block: front-ends
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Contracts

The durable surfaces here are unusual: the operator's keystrokes are the input format and the rendered screen is the output format, so menu order and numbering are as much an interface as a function signature. [verified]

## Menu numbering in TOOLS.sh runs continuously across sections

`scripts/TOOLS.sh::main_menu()` renders four arrays in a fixed order, `MENU_SYSTEM`, `MENU_PROJECTOR`, `MENU_MEDIA` then `MENU_LAUNCHER`, passing a running start number into `scripts/TOOLS.sh::show_menu_section()` and advancing it by each array's length. [verified] The arrays hold 8, 5, 4 and 2 entries at the pin, so the visible range is 1 to 19 and entry 19 is the launcher reset. [verified] `scripts/TOOLS.sh::get_menu_entry()` walks the same four arrays in the same order to turn a typed number back into an entry, so the render and the lookup share one ordering and cannot disagree unless the two section lists are edited apart. [verified]

The suite asserts both halves: a floor on how many numbered lines render, and that the string `tests/ui-tests.sh::"Reset to Default Launcher"` appears against number 19. [verified] Inserting an entry anywhere before the end renumbers the launcher reset and fails the suite without changing any behaviour. [inferred]

enforcement: `tests/ui-tests.sh::"numbering runs continuously across sections"` (test suite)

## The keystroke stream is the front end's input format

`tests/ui-tests.sh::ui()` supplies a whole session as one here string on stdin and never types interactively, so each scenario encodes an exact sequence of keys. [verified] `scripts/lib/common.sh::pause()` and `scripts/lib/common.sh::confirm()` both consume a line from that same stdin, which means a prompt added or removed anywhere in a dispatched child shifts every later keystroke in the sequence. [verified] The unlock scenario feeds `2`, `y`, an empty line and `q`: the `y` is answered by `scripts/UNLOCK.sh::"Apply all steps now?"` in the child process, not by anything in this block. [verified]

enforcement: `tests/ui-tests.sh::ui()` (test suite, here string on stdin)

## PROJECTOR.sh option numbers are an input contract only

`scripts/PROJECTOR.sh::main()` maps `1` to backup, `2` to unlock, `3` to revert, `4` to detailed status, `5` to refresh and `q` or `Q` to exit. [verified] `scripts/PROJECTOR.sh::draw_menu()` prints those numbers in brackets rather than the `N.` form `scripts/TOOLS.sh` uses, so the suite's numbered line counter does not match them and no scenario asserts on a rendered PROJECTOR entry number. [verified] The coupling is still real but runs the other way: scenarios type `1` and `2` to select actions, so reassigning a number silently points a test at a different action instead of failing on a rendered string. [inferred]

enforcement: `tests/ui-tests.sh::"PROJECTOR.sh refuses to unlock without a backup"` (test suite, selection by typed number)

## The dispatch surface is four child command lines

`scripts/PROJECTOR.sh` starts other blocks only through these four invocations, each in a subshell that first changes into the working directory captured at startup. [verified]

| Menu entry | Child command | Owner |
|---|---|---|
| 1 | `bash "$SCRIPT_DIR/MAKE_BACKUP.sh"`, backgrounded, stdout and stderr to a log | [`backup`](../backup/README.md) |
| 2 | `bash "$SCRIPT_DIR/UNLOCK.sh" --apply-all` | [`unlock`](../unlock/README.md) |
| 3 | `bash "$SCRIPT_DIR/UNLOCK.sh" --revert` | [`unlock`](../unlock/README.md) |
| 4 | `bash "$SCRIPT_DIR/UNLOCK.sh" --status` | [`unlock`](../unlock/README.md) |

None of the four passes `--yes`, so each child keeps whatever confirmation it defines for itself. [verified] `scripts/PROJECTOR.sh::run_unlock()`, `scripts/PROJECTOR.sh::run_revert()` and `scripts/PROJECTOR.sh::run_details()` each discard the child's exit status and call `pause` instead of branching on it. [verified]

enforcement: `tests/ui-tests.sh::"PROJECTOR.sh drives a real unlock and reflects it afterwards"` (test suite, end to end through the child)

## Backups are discovered by glob and by name order

`scripts/PROJECTOR.sh::detect_state()` iterates `projector-backup-*` under the startup working directory, skips anything without a `full-system-backup.img`, and keeps the last match the glob yields rather than comparing timestamps. [verified] Bash sorts a glob lexicographically, so the last match is the newest only while the directory names stay zero padded and time ordered. [inferred] Completeness is then decided by `scripts/lib/common.sh::verify_backup_dir()`, run from that directory, and only a zero status sets the flag the unlock entry reads. [verified]

The fixture that satisfies this contract is `tests/ui-tests.sh::add_backup()`, which creates one such directory with an image and a manifest. [verified]

enforcement: `scripts/lib/common.sh::verify_backup_dir()` (per refresh, in `detect_state`)

## Progress is parsed out of the backup block's log text

While the child runs, `scripts/PROJECTOR.sh::run_backup()` strips ANSI codes from the log and matches three literal shapes: `scripts/PROJECTOR.sh::"Transfer stalled"` counts retries, `scripts/PROJECTOR.sh::"Streaming in "` yields the total block count, and a per block percentage line is counted to get blocks done. [verified] Completion is decided by a separate search for `scripts/PROJECTOR.sh::"BACKUP COMPLETE"` in the log, not by the child's exit status, which is captured into a variable and used only inside the failure message. [verified] These are text contracts owned by [`backup`](../backup/README.md): rewording any of those lines degrades this screen without failing the backup. [inferred]

The bar itself does not depend on that text. It is computed from the image file's size against the device size read at detection, which is why the comment in the source calls the file the thing being produced. [verified]

enforcement: `tests/ui-tests.sh::"Backup complete and verified"` (test suite, completion string only)

## Menu command strings are literals and the operator supplies only an index

Every command `scripts/TOOLS.sh` sends is the part of an array entry before the first `|`, and the arrays are literals in the file. [verified] `scripts/TOOLS.sh::section_items()` expands an array whose name arrives in a variable using `eval`, and the source comment records that the array names are literals from the loop below it and never operator input. [verified] The typed value reaches the dispatcher only as a number matched against `[1-9]` or `[1-9][0-9]`, and an out of range number falls through to an invalid option message. [verified]

The one place device output is interpolated into a command is `scripts/TOOLS.sh::reset_default_launcher()`, and it is filtered to a component shaped string before use. [verified]

enforcement: `scripts/TOOLS.sh::get_menu_entry()` (index lookup, per selection)

## The launcher reset is the one device write this block performs itself

Entry 19 carries the sentinel `scripts/TOOLS.sh::"@reset-launcher"` rather than a command, and `scripts/TOOLS.sh::main_menu()` routes it to a handler instead of sending it like the other 18. [verified] The handler refuses when the stock launcher appears in `pm list packages -d`, otherwise it queries the device for the component that registers for `CATEGORY_HOME` and sends `cmd package set-home-activity` with it. [verified] The source comment above the array states the distinction plainly: everything above only opens screens, this one changes which launcher the device boots into. [verified]

No confirmation guards it. `scripts/TOOLS.sh` never calls `scripts/lib/common.sh::confirm()` and never calls `scripts/lib/common.sh::require_backup()`, and `scripts/TOOLS.sh::main()` passes `false` to the device check so root is not required either. [verified] The disabled launcher check is therefore the only thing between a typed `19` and a persistent change to the device's home screen, and it is a check about one specific failure mode, not a prompt. [inferred] See [Gaps](GAPS.md). [verified]

enforcement: `scripts/TOOLS.sh::reset_default_launcher()` (disabled package check only, no confirmation)

## The unlock gate in PROJECTOR.sh is a duplicate, not the gate

`scripts/PROJECTOR.sh::run_unlock()` refuses with `scripts/PROJECTOR.sh::"A verified backup is required before unlocking"` when the verified backup flag is not set. [verified] The child it would otherwise start runs `scripts/lib/common.sh::require_backup()` independently, because `scripts/UNLOCK.sh::main()` demands it for every mode except status. [verified] So the front end check controls what the menu offers and what the refusal text says, while the block on the device write itself lives in the unlock block. [inferred] `scripts/PROJECTOR.sh::run_revert()` has no equivalent front end check at all and relies entirely on `scripts/UNLOCK.sh::"Restore the stock launcher?"`. [verified]

enforcement: `tests/ui-tests.sh::"device untouched"` (test suite, asserts the fixture is unchanged after a refusal)

## Exit behaviour differs between the two front ends

`scripts/PROJECTOR.sh::main()` guards its prompt with `read -r -p "  > " choice || { echo; exit 0; }`, so end of input leaves with status 0, the same as `q`. [verified] `scripts/TOOLS.sh::main_menu()` leaves its `read` unguarded under `set -euo pipefail`, so end of input terminates the script through errexit instead of through the `q` branch. [verified] Measured on this host with GNU bash 5.3.15 by running the two shapes against `/dev/null`: the guarded form exits 0, the unguarded form exits 1 and never reaches the code after the loop. [verified] `scripts/TOOLS.sh` also accepts `0` as a quit key, which the rendered menu does not mention. [verified]

Before the menu, `scripts/PROJECTOR.sh::main()` exits 1 when `adb` is absent from `PATH`, and `scripts/TOOLS.sh::main()` delegates the same class of refusal to `scripts/lib/common.sh::require_device()`. [verified]

enforcement: convention (no scenario feeds end of input without `q`; see [Gaps](GAPS.md))
