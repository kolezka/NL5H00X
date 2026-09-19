---
block: front-ends
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## PROJECTOR.sh key map

Key 1 runs the backup, 2 the unlock, 3 the revert, 4 the detailed unlock state, 5 a refresh that only redraws, and q quits with status 0. [verified]

Anything else is read and ignored, so the loop redraws instead of erroring, and end of input is handled explicitly and also exits 0. [verified]

enforcement: `scripts/PROJECTOR.sh::main()` (dispatch), `tests/ui-tests.sh::"verified backup is required"` (test suite)

## PROJECTOR.sh header fields

The header always shows four rows in one order: device, root, backup and launcher. [verified]

Device absent prints a connect hint instead of a model. Backup is one of verified, incomplete or none. Launcher is unlocked, locked, blocked with the reason, or unknown, which is what it stays at when there is no root to read it with. [verified]

enforcement: `scripts/PROJECTOR.sh::draw_header()` (renderer), `tests/ui-tests.sh::"reports the launcher as locked"` (test suite)

## TOOLS.sh menu numbering

Nineteen entries are numbered continuously from 1 across four sections, 8 then 5 then 4 then 2, so 19 is the launcher reset. [verified]

Diagnostics are lettered i, h, l and s, and quit accepts q, Q or 0. Numbers are accepted only in the range 1 to 99 and an unmapped number prints an invalid option. [verified]

enforcement: `tests/ui-tests.sh::"numbering runs continuously across sections"` (test suite)

## TOOLS.sh entry format

Each array element is one string: the device command, a pipe, then the description shown in the menu. The description is everything after the first pipe and the command is everything before it. [verified]

One sentinel exists. An element whose command field is `@reset-launcher` is routed to the guarded handler rather than passed to adb, which is how the only state changing entry gets a check in front of it. [verified]

enforcement: `scripts/TOOLS.sh::get_menu_entry()` (dispatch), `scripts/TOOLS.sh::"@reset-launcher"` (sentinel)

## Delegated invocations

`scripts/PROJECTOR.sh` invokes `scripts/UNLOCK.sh` with exactly one flag per action: `--apply-all` to unlock, `--revert` to restore the stock launcher, `--status` for detail. [verified]

It never passes `--yes`, so the unlock's own confirmation prompt is inherited and the person answers it in the same terminal. [verified]

enforcement: `scripts/PROJECTOR.sh::"--apply-all"` (call site), `tests/ui-tests.sh::"All steps applied and verified"` (test suite)

## Invocation directory

The working directory is captured once at startup and never re-read, and both delegated subprocesses are started inside it. [verified]

Backups are therefore found and created next to wherever the front end was launched from, not next to the script. The menu sees only backup directories matching the `projector-backup-*` glob in that one directory. [verified]

enforcement: `scripts/PROJECTOR.sh::WORK_DIR` (single assignment)

## Backup progress log

The backup writes its full output to `.backup-progress.log` in the invocation directory, truncated at the start of every run. [verified]

The progress screen renders the last eight lines tagged INFO, OK, WARN, ERROR or STEP, cut to 70 columns, and on failure prints the last five ERROR lines and the log path. [verified]

enforcement: `scripts/PROJECTOR.sh::run_backup()` (writer)

## No argument surface

Both scripts pass their arguments to `main` and neither parses them, so every argument is ignored, including `--help`. [verified]

The only interface is the interactive menu. Automation has to call `scripts/UNLOCK.sh` or `scripts/MAKE_BACKUP.sh` directly, which is what `tests/ui-tests.sh` does when it needs a non-interactive unlock. [verified]

enforcement: convention
