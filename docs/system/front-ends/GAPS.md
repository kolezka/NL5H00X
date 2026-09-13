---
block: front-ends
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Gaps

## Neither front end ever asks for confirmation

`scripts/lib/common.sh::confirm()` exists and is used by `scripts/UNLOCK.sh`, but neither owned file calls it. The string `confirm` does not occur anywhere in either script at the pin, not in code and not in a comment, reproduced with `git show f04ee86:scripts/TOOLS.sh | grep -c confirm` and the same against `scripts/PROJECTOR.sh`. [verified] Every yes or no question an operator answers while using `scripts/PROJECTOR.sh` is printed by a child process: `scripts/UNLOCK.sh::"Apply all steps now?"` and `scripts/UNLOCK.sh::"Restore the stock launcher?"`. [verified] `scripts/lib/common.sh::pause()` is used six times in each front end, but a pause acknowledges a result, it does not gate an action. [verified]

For the dispatched paths this is defensible, since the child owns both the prompt and the write. [inferred] It is not defensible for the one write this block makes itself, which is the next gap. [inferred]

## The launcher reset writes to the device with nothing but a narrow check in front of it

Typing `19` in `scripts/TOOLS.sh` reaches `cmd package set-home-activity` through `scripts/TOOLS.sh::reset_default_launcher()` and then `scripts/TOOLS.sh::run_adb_command()`, which sends the command immediately. [verified] The only thing between the keystroke and that write is the test for the stock launcher appearing in `pm list packages -d`, which refuses one specific state and passes everything else through. [verified] There is no confirmation, no backup requirement (`scripts/lib/common.sh::require_backup()` is never called from this block) and no root requirement (`scripts/TOOLS.sh::main()` passes `false` to the device check). [verified]

This is the one place in the block where the front end is the last line of defence rather than a menu in front of another block's gate. [inferred] The change is a persistent one to which launcher owns the home intent, which on this device is the operator's only interactive surface; whether it is recoverable depends on the state it leaves behind and is not established by reading this code. [inferred] A single mistyped `19` at the `Select option:` prompt is sufficient to trigger it, and the suite scenario that exercises it types exactly that. [verified]

The matching entry in `scripts/PROJECTOR.sh` is not comparable: its revert path hands the work to [`unlock`](../unlock/README.md), which prompts. [verified]

## PROJECTOR.sh option 3 has no front end gate at all

`scripts/PROJECTOR.sh::run_revert()` prints a blank line and starts the child, with no check on device state, backup state or launcher state, unlike `scripts/PROJECTOR.sh::run_unlock()` next to it. [verified] The revert is safe only because `scripts/UNLOCK.sh::main()` applies `scripts/lib/common.sh::require_backup()` to every mode except status and then prompts. [verified] Dropping `--yes` was what made that true; adding it here to remove a keystroke would leave the entry with no gate of any kind. [inferred]

## The block bypasses the shared ADB helpers

`scripts/TOOLS.sh` issues 10 direct `adb shell` invocations and uses none of `scripts/lib/common.sh::adb_exec()`, `scripts/lib/common.sh::adb_start_activity()` or `scripts/lib/common.sh::adb_start_action()`, confirmed by counting both at the pin. [verified] Two of those helpers exist for exactly the job this menu does, starting an activity and starting an action. [verified] The consequence is that the error handling in `scripts/TOOLS.sh::run_adb_command()` is a second implementation which can drift from the shared one, and that no command from this file passes through the root escalation path in [`device-access`](../device-access/README.md). [inferred]

## Dead code that can still abort the menu

`scripts/TOOLS.sh::main_menu()` assigns the result of `scripts/TOOLS.sh::count_menu_items()` to a local `total` which is never read afterwards, confirmed by searching the file for the name at the pin. [verified] The function is not harmless dead weight: it runs `grep -c .` inside a command substitution under `set -euo pipefail`, and `grep -c` exits 1 when it counts nothing. [verified] `scripts/TOOLS.sh::main_menu()` is called unguarded from `scripts/TOOLS.sh::main()`, so emptying any one of the four arrays would abort the program before a menu is drawn, for a value nothing uses. [inferred]

## End of input behaves differently in the two front ends and is untested

`scripts/PROJECTOR.sh` treats end of input as quit and exits 0; `scripts/TOOLS.sh` has no guard on its `read` and terminates through errexit with status 1, reaching neither `scripts/TOOLS.sh::"Goodbye!"` nor any cleanup. [verified] Measured on this host with GNU bash 5.3.15 against `/dev/null`, the two shapes exit 0 and 1 respectively. [verified] Every suite scenario ends its input with `q`, so this difference is never exercised: a caller piping input into `scripts/TOOLS.sh` sees a non-zero status for an ordinary end of session. [verified]

## An operator promise the code does not keep

The progress screen prints `scripts/PROJECTOR.sh::"the backup keeps running even if you close this"`. [verified] Nothing in the file detaches the child: `nohup`, `disown` and `setsid` do not appear at the pin, and the backup runs as a plain background job of the script with no separate process group, since job control is off in a non-interactive shell. [verified] Whether the backup survives closing the terminal therefore depends on how the hangup is delivered rather than on anything this block does, and the message states it as a fact. [inferred] No scenario tests it. [verified]

## Failure is announced but not signalled

`scripts/PROJECTOR.sh::run_backup()` prints `scripts/PROJECTOR.sh::"Backup did not complete"` with the child's exit status and then returns 0. [verified] The three unlock wrappers discard the child status entirely. [verified] `scripts/PROJECTOR.sh::main()` ignores the return value of all four in any case, so the loop redraws identically after a success and after a failure, and the only lasting signal is the log file and the refreshed header. [verified] The script's own exit status can never report that an operation failed. [inferred]

## The entry count assertion is a floor, not an equality

`tests/ui-tests.sh::"all $count entries render"` passes on any count at or above 19 and only the failure branch names the expected number, in `tests/ui-tests.sh::"only $count entries rendered, expected 19"`. [verified] Appending an entry to `MENU_LAUNCHER` therefore passes the count check, and is caught only by the separate assertion that pins the launcher reset to number 19. [verified] Appending to any earlier array is caught by that same assertion, so the numbering is guarded at one point rather than across the menu. [inferred]

## The harness reads an ordinary refusal as a crash

The runtime smoke check in `tests/ui-tests.sh` fails a front end when its output matches `tests/ui-tests.sh::"fails at runtime under /bin/bash"` conditions, and the pattern it matches includes the literal text `invalid option` alongside genuine shell failures such as unbound variable and syntax error. [verified] `scripts/TOOLS.sh::"Invalid option"` is normal output for an out of range number. [verified] The scenario types only `q`, so the collision is latent; a future scenario that types a bad number into that check would report an interpreter failure that did not happen. [inferred]

## Invalid input is handled inconsistently

`scripts/PROJECTOR.sh::main()` maps any unrecognised key to a no-op, silently redrawing the menu, while `scripts/TOOLS.sh::main_menu()` prints an error and sleeps. [verified] `scripts/TOOLS.sh` additionally accepts `0` as a quit key which its rendered menu never mentions, since the menu offers only `q`. [verified] An operator moving between the two front ends gets no feedback in one and an error in the other for the same mistake. [inferred]

## Backup discovery parses `ls` output

`scripts/PROJECTOR.sh::run_backup()` locates the growing image with `ls` on a glob piped into `tail -1`, inside the progress loop, while `scripts/PROJECTOR.sh::detect_state()` iterates the same glob directly for the same purpose. [verified] The `ls` form breaks on a path containing a newline and depends on the command's output formatting rather than on the shell's own sorted glob expansion. [inferred] Both forms also assume lexicographic order equals chronological order, which holds only while the backup block keeps its zero padded timestamp naming. [inferred]

## A refusal cites behaviour the unlock no longer has

`scripts/PROJECTOR.sh::run_unlock()` tells the operator the unlock disables their only working home screen. [verified] The suite records the opposite and asserts it: `tests/ui-tests.sh::"the unlock left the stock launcher enabled"` is a passing expectation, and the scenario comment states the unlock reaches its goal with a preference alone and disables nothing. [verified] The refusal is still correct to make, because a verified backup is genuinely required before the unlock, but the reason it gives is stale and would mislead someone deciding how urgent the backup is. [inferred]
