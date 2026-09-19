---
block: app-install
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## Permissions and ownership are set but never verified

The `chmod` and `chown` calls that follow the copy run with their failures
suppressed, and nothing reads the resulting mode or owner back [verified]. The
checksum step proves the bytes arrived, not that the app directory is readable by
the package manager [verified]. A silently failed `chmod` therefore surfaces as
"the package did not register after the reboot", one step away from its cause
[inferred].

## Stale libraries in the target ISA directory survive a reinstall

Libraries are copied into `/system/app/<Name>/lib/<isa>/` without clearing it
first, and the post-copy check only walks the files that were just unpacked
[verified]. A `.so` left by an earlier version of the same app stays on the device
and passes verification by never being looked at [inferred].

## A --name collision with an existing app directory is unchecked

The duplicate-copy warning compares the recorded `codePath` of the package being
installed [verified]. Nothing compares the target directory against the
directories of other packages, so `--name` pointing at an occupied
`/system/app` directory writes into it without a warning [verified]. The protected
package list guards removal only, not this [verified].

## The home check is a whole-pool string scan

`scripts/INSTALL_APP.sh::apk_facts()` reports `HOME=yes` when the category string
appears anywhere in the manifest string pool, without checking that it sits in an
intent filter [verified]. That errs toward refusing, which is the right direction
for this device, but it means an APK that merely mentions the string needs
`--allow-home` to install [inferred]. The override is all-or-nothing: there is no
way to say "this string is incidental" without also waiving the real check
[verified].

## Nothing verifies a staged install that the operator did not reboot

`scripts/INSTALL_APP.sh::verify_installed()` runs only on the branch where the
script performed the reboot [verified]. After `--no-reboot`, or a declined prompt,
there is no command in this block that re-checks the staged app later [verified].

## Checksums are MD5, against a project rule that says sha256

Both the upload check and the post-copy check use MD5 [verified], while the
project's own working rule for device writes is `CLAUDE.md::sha256sum` [verified].
MD5 is adequate for detecting a truncated or corrupted transfer and is not
adequate against a deliberately crafted collision [inferred]. The divergence is
undocumented in the script itself [verified].

## One APK only, and current apps are often not shipped as one

The script takes exactly one APK and has no split-bundle path [verified]. Merging
splits into a single APK, re-signing it, and the `requiredSplitTypes` and
alignment traps that come with it are written up in
`docs/INSTALL_LOCKED.md::requiredSplitTypes` but are entirely manual [verified].

## No space check before writing to /system

The app is copied into `/system` without asking how much room is left [verified].
An app installed this way consumes the system partition rather than `/data`, and
that partition is the smaller of the two; the figures are in
`docs/INSTALL_LOCKED.md::"1.7 GB system partition"` and were not re-measured here
[assumption].

## Removal does not clean up the package database

`scripts/INSTALL_APP.sh::remove_app()` deletes the directory and confirms it is
gone [verified]. The package database keeps naming the deleted `codePath` until
the next boot, and the remove branch only reboots when the operator asks for it
[verified].
