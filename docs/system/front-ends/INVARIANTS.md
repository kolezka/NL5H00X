---
block: front-ends
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Invariants

Properties a rewrite of either front end has to keep. Most are paid for by a defect recorded in a source comment; those carry a history tag, because reading the comment proves the rationale was written down, not that the event can be re-measured from this repository. [verified]

## 1. A state changing entry is routed, never fired like the rest

`scripts/TOOLS.sh::main_menu()` inspects the command half of the selected entry and calls `scripts/TOOLS.sh::reset_default_launcher()` when it equals the sentinel, falling through to `scripts/TOOLS.sh::run_adb_command()` for everything else. [verified] The comment above `MENU_LAUNCHER` records the split that justifies it: the other entries only open screens, this one changes which launcher the device boots into, so it is routed rather than fired blindly. [verified] Collapsing the sentinel back into an ordinary command string would remove the handler and with it the only check that exists on that write. [inferred]

## 2. `am start` exit status is not trusted

`scripts/TOOLS.sh::run_adb_command()` captures combined output, then treats the action as failed when the status is non-zero **or** the output matches an error shaped pattern. [verified] The comment records why the second half is there: `scripts/TOOLS.sh::"Error: Activity not started"` is printed while the command still exits 0, so the exit code alone reported success for activities that never opened. [historical: undated, comment in scripts/TOOLS.sh] A rewrite that checks only the status reintroduces a menu that says Done for every entry, including entries for packages absent from the device. [inferred]

## 3. The array indirection must work on bash 3.2

`scripts/TOOLS.sh::section_items()` expands an array named by a variable through `eval` rather than a nameref. [verified] The comment records the defect: `scripts/TOOLS.sh::"namerefs need bash 4.3"` while macOS ships 3.2, so the script died on the first menu draw for every Mac user. [historical: undated, comment in scripts/TOOLS.sh] The suite guards this with a parse check under the system interpreter, not the one on `PATH`, asserting `tests/ui-tests.sh::"parses under /bin/bash"` for each entry script. [verified]

## 4. The stock launcher's home component is asked for, never hardcoded

`scripts/TOOLS.sh::reset_default_launcher()` queries the device for activities matching MAIN and `CATEGORY_HOME` and extracts the component belonging to `scripts/TOOLS.sh::STOCK_LAUNCHER_PKG`. [verified] The comment records the trap: the activity a user sees is `.MainActivity`, but the one carrying the HOME filter is `scripts/TOOLS.sh::"WizardAciticity"`, their spelling, so setting home against `.MainActivity` is rejected. [historical: undated, comment in scripts/TOOLS.sh] When the query returns nothing the handler stops with a warning instead of sending a command built from a guess. [verified]

## 5. Device output is narrowed to a safe shape before it re-enters a command

The component is extracted with `grep -oE` against a pattern that permits only the known package name, a slash, and letters, digits, underscores and dots, then the first match alone is used. [verified] That value is interpolated into the string handed to `adb shell`, so the character class is what keeps arbitrary device output from becoming shell input. [inferred] This is the only place in either front end where text read off the device is placed into a command; `scripts/PROJECTOR.sh::detect_state()` puts device output into printf arguments and tests the size against `^[0-9]+$` before assigning it. [verified]

## 6. Progress is measured from the artifact, not from the log

`scripts/PROJECTOR.sh::run_backup()` computes the percentage from the growing image file's size against the device size, and the comment states the reason: the file is the thing being produced, so its size cannot disagree with reality the way a log line can. [verified] Log text is used only for the block counter, the stall counter and the completion string, all of which degrade to a less informative screen rather than a wrong bar when the backup block rewords a message. [inferred]

## 7. A counting command that exits non-zero must not get a fallback

The stall counter is written without an `|| echo 0` fallback, and the comment records the defect it caused: `scripts/PROJECTOR.sh::"grep -c already prints 0"` when it finds nothing while still exiting 1, so the fallback appended a second zero and the variable became two lines, which is an arithmetic syntax error downstream. [historical: undated, comment in scripts/PROJECTOR.sh] The guard that remains is a parameter default on an empty value, which is a different condition from a non-zero status. [verified]

## 8. The backup child cannot consume the operator's keystrokes

`scripts/PROJECTOR.sh::run_backup()` starts the backup in the background with stdout and stderr redirected into the log, unlike the three unlock invocations which run in the foreground and share the terminal. [verified] A background command in a non-interactive shell has its stdin attached to `/dev/null` before any explicit redirection, so the child cannot read a line that was meant for the menu. [inferred] Measured on this host with GNU bash 5.3.15 by piping one line into a script that backgrounds a subshell reading stdin and then reads stdin itself: the child read end of input and the parent still received the line. [verified] The matching suite scenario types only `1`, an empty line for the pause, and `q`, which is consistent with the child consuming nothing. [verified]

## 9. Displayed sizes are decimal, matching the manifest

`scripts/PROJECTOR.sh::human()` divides by powers of 1000, not 1024. [verified] The comment records the reason: the device reports its size in decimal bytes and every number in the docs and the manifest is decimal, so a GiB figure here would look like a different device to someone reading both. [historical: undated, comment in scripts/PROJECTOR.sh] A rewrite that switches to GiB makes the header disagree with the backup block's manifest for the same hardware. [inferred]

## 10. A short remaining time is shown in seconds

`scripts/PROJECTOR.sh::run_backup()` switches the estimate to seconds below one minute. [verified] The comment records why: `scripts/PROJECTOR.sh::"Integer minutes read as"` zero minutes left for anything under a minute, which looks like a hang rather than nearly done. [historical: undated, comment in scripts/PROJECTOR.sh]

## 11. A refusal says which way it failed and what to do instead

`scripts/PROJECTOR.sh::run_unlock()` refuses without a verified backup and then states the consequence rather than the rule, ending with `scripts/PROJECTOR.sh::"the unlock disables your only working home screen"`. [verified] `scripts/TOOLS.sh::reset_default_launcher()` does the same for its own refusal, naming the disabled state and pointing at `scripts/TOOLS.sh::"UNLOCK.sh --revert"` as the command that works. [verified] Both are asserted on by text, including `tests/ui-tests.sh::"points at the command that actually works"`, so a reword that drops the remedy fails the suite. [verified]

The refusal text in `scripts/PROJECTOR.sh::run_unlock()` describes a behaviour the unlock block no longer has. The suite records that the unlock reaches its goal with a preference alone and asserts `tests/ui-tests.sh::"the unlock left the stock launcher enabled"`. [verified] The invariant that survives is the shape, a refusal that names a consequence; the specific consequence named is stale and is listed in [Gaps](GAPS.md). [inferred]

## 12. A guard for an older toolkit's damage stays after the cause is fixed

The disabled launcher check in `scripts/TOOLS.sh::reset_default_launcher()` covers a state the current unlock never creates. [verified] The suite comment records the decision to keep it: devices disabled by older versions of this toolkit are out there, and the scenario now sets that state directly rather than producing it with an unlock. [verified] The companion scenario asserts the guard does not misfire, checking for `tests/ui-tests.sh::"no bogus 'disabled' excuse"` on a device the current unlock has touched. [verified]
