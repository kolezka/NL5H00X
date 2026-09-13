---
block: app-install
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Contracts

No automated test covers any contract on this page, because no suite exercises `scripts/INSTALL_APP.sh` at this pin. [verified] Every `enforcement:` below is therefore either a guard the script runs against itself at run time or an honest `convention`, and each run time guard protects one execution, not a future edit. [inferred] See `GAPS.md`.

## Command line surface

The script accepts exactly two forms, an APK path with optional `--name`, `--allow-home`, `--reboot` and `--no-reboot`, or `--remove` with a package name, as printed by `scripts/INSTALL_APP.sh::usage()`. [verified] An unrecognised option starting with a hyphen prints usage and exits 1, while a bare word is taken as the APK path and a second bare word silently replaces the first. [verified] Missing both an APK and a removal target prints usage and exits 1, and a named APK that is not a regular file exits 1 before any device contact. [verified]

Exactly one APK is accepted, so a Play style split bundle cannot be passed to this script and must be merged and re signed before it can be installed at all. [verified]

enforcement: `scripts/INSTALL_APP.sh::main()` (argument loop, run time)

## Host prerequisites are checked before the device is touched

`unzip` and `python3` must be on the host PATH or the script exits 1 with a message naming the missing tool. [verified] That check runs before `require_device`, so a host missing a parser fails without opening an ADB connection. [verified] No check covers the digest tool, which `scripts/INSTALL_APP.sh::local_md5()` resolves as `md5` if present and `md5sum` otherwise. [verified]

enforcement: `scripts/INSTALL_APP.sh::main()` (preflight loop over `unzip` and `python3`)

## Manifest facts are a three line shell safe format

`scripts/INSTALL_APP.sh::apk_facts()` prints `PKG=` and `HOME=yes` or `HOME=no` on success, and on failure prints a single `ERROR=` line and nothing else. [verified] The three defined failure values are `scripts/INSTALL_APP.sh::"ERROR=not-an-android-manifest"`, `scripts/INSTALL_APP.sh::"ERROR=string-pool-unreadable"` and `scripts/INSTALL_APP.sh::"ERROR=manifest-parse-failed"`. [verified] The helper exits 0 in every case, including all three errors, so the caller must inspect the text rather than a status. [verified]

The caller matches that text by substring, `*ERROR=*` first and then `*"HOME=yes"*`, so the format is a real interface between the embedded Python and the shell around it even though both live in one file. [verified]

enforcement: convention (the caller string matches the format; nothing validates the emitted text, see `GAPS.md`)

## An APK claiming the home intent is refused by default

When the pool contains `android.intent.category.HOME` or `android.intent.category.SETUP_WIZARD`, `scripts/INSTALL_APP.sh::install_app()` prints `scripts/INSTALL_APP.sh::"This APK declares CATEGORY_HOME or CATEGORY_SETUP_WIZARD"` and returns 1 unless `--allow-home` was given. [verified] With `--allow-home` it prints a warning and proceeds. [verified] A manifest that could not be decoded is refused the same way, with `scripts/INSTALL_APP.sh::"Refusing to install an APK whose home declaration cannot be checked"`. [verified]

Both refusals happen before the script writes anything to the device, so a rejected APK leaves no state behind. [verified]

enforcement: `scripts/INSTALL_APP.sh::install_app()` (manifest gate, before staging)

## The normal install is attempted first and its success ends the run

`adb install -r` runs before any fallback, and output containing `Success` returns 0 immediately with `scripts/INSTALL_APP.sh::"Installed normally - no $SYSTEM_APP_DIR copy needed"`. [verified] In that case `APP_DIR` stays empty and `scripts/INSTALL_APP.sh::main()` exits 0 without prompting for a reboot and without running `verify_installed()`. [verified] On this hardware that branch is not expected to be reached, since the recorded behaviour is that every install path fails with the same install location error. [historical: 2026-07-30, docs/INSTALL_LOCKED.md]

enforcement: `scripts/INSTALL_APP.sh::install_app()` (substring test on the install output)

## Install layout under /system/app

A fallback install produces `/system/app/<name>/<name>.apk` with mode 644 inside a directory with mode 755, owned recursively by `root:root`, where `<name>` is `--name` or the leading alphanumeric run of the APK filename from `scripts/INSTALL_APP.sh::default_name_from_apk()`. [verified] When the APK carries native code, the matching ABI is unpacked flat into `/system/app/<name>/lib/<isa>/` with mode 644 under directories at 755, using the mapping in `scripts/INSTALL_APP.sh::abi_to_isa()`. [verified] `scripts/INSTALL_APP.sh::SYSTEM_APP_DIR` and `scripts/INSTALL_APP.sh::STAGING` are fixed constants and cannot be overridden from the environment or the command line. [verified]

Only the file contents are verified afterwards. The `chmod` and `chown` calls are best effort and their results are never checked. [verified]

enforcement: convention (content is verified by digest, modes and ownership are not, see `GAPS.md`)

## An ABI mismatch is refused, not worked around

When the APK contains any `lib/<abi>/*.so`, the device list from `ro.product.cpu.abilist` is walked in device order and the first ABI the APK also provides wins. [verified] If none match, the script prints both lists and returns 1 rather than installing an app that cannot load its libraries. [verified] A matched ABI with no entry in `abi_to_isa()` is also a refusal. [verified]

This check runs before the normal install attempt, so an APK built for the wrong architecture is refused even on the path where the platform installer would have handled it. [verified]

enforcement: `scripts/INSTALL_APP.sh::install_app()` (ABI intersection, before install)

## Every byte that crosses to the device is digest checked

The staged upload is compared against the local file and a mismatch deletes the staged copy and returns 1 with `scripts/INSTALL_APP.sh::"Upload corrupted"`. [verified] After the copy into `/system` the installed APK is compared again, and each unpacked `.so` is compared individually, with any mismatch failing the run. [verified] Both comparisons use MD5, computed locally by `scripts/INSTALL_APP.sh::local_md5()` and on the device by `md5sum`. [verified]

These digests are the only real check on the copy step, because the `mkdir`, `cp`, `chmod` and `chown` calls all discard their status. [verified] A digest proves the bytes arrived intact; it is not a check that the APK is the one the publisher signed. [inferred]

enforcement: `scripts/INSTALL_APP.sh::install_app()` (digest comparison after upload and after copy)

## Removal refuses by package name and by location

`scripts/INSTALL_APP.sh::remove_app()` compares the requested package against `scripts/INSTALL_APP.sh::PROTECTED_PKGS`, which holds `com.newlink.wtprovision`, `com.newlink.hisilauncher`, `com.android.tv.settings` and `com.android.settings`, and refuses with `scripts/INSTALL_APP.sh::"Refusing to remove"` before making any device call. [verified] A package whose `codePath` does not start with `/system/app/` is refused with `scripts/INSTALL_APP.sh::"not ours to delete"`, and a package with no resolvable `codePath` is reported as not installed. [verified]

The name list is the only guard that can stop the removal of a package that genuinely does live under `/system/app`, since the location guard passes for everything there. [inferred]

enforcement: `scripts/INSTALL_APP.sh::PROTECTED_PKGS` and the `codePath` prefix test in `scripts/INSTALL_APP.sh::remove_app()` (run time, before the delete)

## Removal requires the package name typed on the terminal

The operator must type the exact package name at `scripts/INSTALL_APP.sh::"Type the package name to confirm:"`, read from `/dev/tty` rather than stdin. [verified] Any other answer cancels and returns 1, and a failed read sets the answer to the empty string, which also cancels. [verified] A piped or redirected answer therefore cannot approve a deletion, which is deliberate: `adb shell` consumes this script's stdin, as the comment on the equivalent prompt in `install_app()` records. [verified]

enforcement: `scripts/INSTALL_APP.sh::remove_app()` (tty read, compared for equality with the package name)

## The delete is confirmed against the device, not against the command

`rm -rf` discards its status and the directory is then stat'ed; if it still exists the script reports `scripts/INSTALL_APP.sh::"$dir is still there"` and returns 1. [verified] Success is only claimed after that check. [verified]

enforcement: `scripts/INSTALL_APP.sh::remove_app()` (stat after delete)

## Nothing takes effect until the next boot

A fallback install and a removal both end with the change on disk and the package manager unaware of it, stated to the operator as `scripts/INSTALL_APP.sh::"Staged. The package registers on the next boot, not before."` [verified] `--no-reboot` exits 0 with a warning, `--reboot` reboots without asking, and the default asks on `/dev/tty`. [verified]

enforcement: `scripts/INSTALL_APP.sh::main()` (reboot branch on `DO_REBOOT`)

## A reboot counts only when uptime regresses

`scripts/INSTALL_APP.sh::reboot_and_wait()` records `/proc/uptime` before rebooting and polls for `sys.boot_completed` for up to 200 seconds. [verified] Reconnecting is not accepted as proof: the new uptime must be lower than the old one, otherwise the script warns and returns 1. [verified] A device that never reports boot completion within the window returns 1 with `scripts/INSTALL_APP.sh::"Device did not come back within 200s"` and a pointer to the deadlock document and the repair flag. [verified]

enforcement: `scripts/INSTALL_APP.sh::reboot_and_wait()` (uptime comparison, post reboot)

## Post reboot verification covers registration and native ABI

`scripts/INSTALL_APP.sh::verify_installed()` fails when the package is not registered, and when the APK carried native code it also fails on an empty or `null` `primaryCpuAbi` with `scripts/INSTALL_APP.sh::"No primaryCpuAbi resolved - native libraries will not load"`. [verified] It runs only on the install path and only after a reboot this script performed. [verified]

enforcement: `scripts/INSTALL_APP.sh::verify_installed()` (post reboot, install path only)
