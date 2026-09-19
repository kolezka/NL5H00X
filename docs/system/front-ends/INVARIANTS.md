---
block: front-ends
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

## 1. Both front ends run on bash 3.2

macOS ships bash 3.2 and the shebang picks `/bin/bash`, so 3.2 is the floor for both scripts. Measured on this machine at the pin: `/bin/bash` reports 3.2.57 and both files pass a parse check under it. [verified]

This was paid for. `scripts/TOOLS.sh` read an array whose name was in a variable using `local -n`, which needs bash 4.3, so the script died on its first menu draw for every Mac user while testing with a Homebrew bash showed nothing wrong. [verified]

The current code reaches the same indirection with an eval in `scripts/TOOLS.sh::section_items()`, and `get_menu_entry` and `count_menu_items` go through it rather than taking a reference. The array names passed in are literals from the loops in those functions, never input. [verified]

The enforcement lives in the [`test-harness`](../test-harness/README.md) block: `tests/ui-tests.sh::"local -n"` records the defect, and the suite both parse checks and runs each front end under `/bin/bash` rather than whatever bash is first in PATH. [verified]

## 2. No unlock from the menu without a verified backup

`run_unlock` refuses and explains when the backup state is not verified, and it refuses before running anything, so the device is untouched. [verified]

The state it checks is not its own guess: it comes from `scripts/lib/common.sh::verify_backup_dir()`, which compares the image size against the manifest, so a backup that stopped part way through does not open the gate. [verified]

## 3. No root read before the root probe

`detect_state` reads the device size and the launcher state only inside the branch where `check_root_access` succeeded. [verified]

That ordering is required rather than tidy. The root exec helper refuses with status 125 when the su mode has not been established, so a launcher read moved outside that branch would report an error string instead of a state. [verified]

## 4. The front ends hold no second copy of backup or unlock logic

Every write path is a separate bash process: `scripts/MAKE_BACKUP.sh` for the backup, `scripts/UNLOCK.sh` for apply, revert and status. [verified]

The reason is recorded in the script's own header: the backup path took several rounds to get right, and a second copy of it behind a nicer screen would be a second place for it to be quietly wrong. [verified]

## 5. The launcher reset never fails silently

`reset_default_launcher` has two refusals and both say why and return non-zero. A disabled stock launcher cannot be made home, so it names `UNLOCK.sh --revert` as the command that works. A stock launcher that registers no home activity is reported as exactly that. [verified]

It also never guesses the component. The activity carrying the home filter on this firmware is not the one you see, so the handler asks the device and takes the first match for the stock package. [verified]

The failure this prevents is the worst kind for a menu entry: without the check the entry appears to do nothing at all. [verified]

## 6. Progress comes from the artifact, not from parsed output

The percentage, rate and estimate in the backup screen are computed from the image file growing on disk, checked every two seconds against the device size read earlier. [verified]

Only the counters and the visible tail are read from the log, and even there the parsing is defensive: the stall count uses `grep -c` with no fallback, because adding `|| echo 0` appended a second zero to a value that already printed one, and the result broke arithmetic downstream. [verified]

## 7. A failed activity launch is reported as a failure

`run_adb_command` inspects the output as well as the exit status, because `am start` prints an error and still exits 0. [verified]

Without that check the menu reported Done for activities that never opened, which on a device where many vendor components are missing is most entries. [verified]
