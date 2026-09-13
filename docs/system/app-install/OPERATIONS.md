---
block: app-install
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Operations

## Start and stop

Two entry forms exist, `bash scripts/INSTALL_APP.sh <file.apk>` with optional `--name`, `--allow-home`, `--reboot` or `--no-reboot`, and `bash scripts/INSTALL_APP.sh --remove <package.name>` with the same reboot flags. [verified] `-h` or `--help` prints usage and exits 0. [verified]

There is no daemon and no resumable state. A run either completes, or exits non zero at the step that failed. [verified] Root is required for both forms: `scripts/INSTALL_APP.sh::main()` calls `require_device true`, which exits the process when root cannot be established rather than returning to the caller. [verified] How root is established and which `su` form is used belongs to [`device-access`](../device-access/README.md).

Both prompts read `/dev/tty`, so the script cannot be driven unattended past a conflicting install or a removal confirmation. [verified] `--reboot` and `--no-reboot` remove the only other prompt. [verified]

Stopping the script partway is not clean. The install and removal paths both hold `/system` mounted read write across several commands with no `trap` to close it, so an interrupt in that window leaves the partition writable. [verified] See `GAPS.md`.

## Observe

All output is human readable text on stdout and stderr from the shared print helpers, with warnings and errors on stderr. [verified] No log file, manifest or run directory is written, so a run leaves no record on the host once the terminal is gone. [verified] Capture the session yourself if the output matters.

The steps that announce themselves are the manifest read, the normal install attempt, the upload, the library upload, the copy into `/system`, the verification and the reboot. [verified] The two checks that actually gate success are quieter: the digest comparisons inside `scripts/INSTALL_APP.sh::install_app()` and the stat after delete in `scripts/INSTALL_APP.sh::remove_app()`. [verified]

After a reboot performed by this script, `scripts/INSTALL_APP.sh::verify_installed()` reports registration and the resolved `primaryCpuAbi`. [verified] Read that ABI line as the real signal on any APK carrying native code: a registered package with a null ABI is an app that will fail when it first loads a library, not a successful install. [inferred]

To inspect the result independently of this script, read `dumpsys package <pkg>` for `codePath` and `primaryCpuAbi`, and list the installed directory under `/system/app`. [verified] The package database is not proof on its own, since it keeps naming an old `codePath` until the next boot. [verified]

## Configuration and paths

`SCRIPT_DIR` resolves from `BASH_SOURCE` and both libraries load from the sibling `lib/` directory, so the script uses the checkout it was started from and has no override for that. [verified]

`scripts/INSTALL_APP.sh::SYSTEM_APP_DIR` and `scripts/INSTALL_APP.sh::STAGING` are fixed constants, not environment reads. [verified] Changing where an app lands means editing the script.

The installed directory name resolves in one step with a fallback: `--name` if given, otherwise `scripts/INSTALL_APP.sh::default_name_from_apk()` takes the leading alphanumeric run of the filename with `.apk` removed, and falls back to the filename stripped of every non alphanumeric character when that run is empty. [verified]

The ISA directory resolves from the intersection of two lists, not from a single value: the ABI directories present in the APK from `scripts/INSTALL_APP.sh::apk_abis()`, and the device list from `ro.product.cpu.abilist`. [verified] The device list is walked in its own order and the first entry the APK also provides wins, then `scripts/INSTALL_APP.sh::abi_to_isa()` maps it to `arm`, `arm64`, `x86` or `x86_64`. [verified] An empty intersection, or a match with no mapping, ends the run. [verified]

`scripts/INSTALL_APP.sh::DO_REBOOT` defaults to `ask` and is set to `yes` or `no` by flag. [verified] `scripts/INSTALL_APP.sh::ALLOW_HOME` defaults to false. [verified] The digest tool resolves as `md5` when present and `md5sum` otherwise. [verified]

## Failure and recovery

A refused APK, a failed upload or a failed digest comparison leaves the device unchanged or leaves only staged files under `/data/local/tmp`, which the error paths remove where they can. [verified] The one thing to check after any failed install is whether `/system` is still mounted read write, because this block never confirms the remount back to read only. [verified]

When `scripts/INSTALL_APP.sh::reboot_and_wait()` reports that the device did not return, the script points at the deadlock document and at `scripts/UNLOCK.sh::"--repair"`. [verified] That flag is the toolkit's recovery path for a projector stuck at the vendor logo, and it belongs to [`unlock`](../unlock/README.md). [verified] Whether it recovers any particular failure caused by this block is not established by anything in this repository, and no test covers it. [verified] Reboot outcomes on this device cannot be read over ADB in any case; a person has to watch the screen. [assumption]

### Removing a system app is irreversible on this device

The removal path is exactly this: refuse if the package is in `scripts/INSTALL_APP.sh::PROTECTED_PKGS`, read `codePath` from `dumpsys package`, refuse if it is not under `/system/app`, require the package name typed at the terminal, remount `/system` read write, `rm -rf` the whole `codePath` directory as root, remount read only, then stat the directory to confirm it is gone. [verified]

Nothing is copied before the delete. [verified] There is no staged copy, no rename, no archive on the device and none on the host. [verified]

Recovery cost, in the order it gets worse:

- If the app was installed by this script and the original APK is still on the host, reinstalling and rebooting is the whole undo. [inferred]
- If the APK is not on the host, it has to be found again, at the version that worked. For an app that came merged from a split bundle, that means repeating the merge and the local re signing by hand. [historical: 2026-08-07, docs/INSTALL_LOCKED.md]
- If the app shipped with the device, there is no APK to go back to. The only route is a partition image from a prior backup run of `scripts/MAKE_BACKUP.sh`, and its generated restore script offers a system partition branch that requires a `system.img` file to be present. [verified] That is a whole partition write, not a file restore, and it reverts every other change made since the image was taken. [inferred] See [`backup`](../backup/README.md) for what a given run actually produces.
- If the deleted package was answering the home intent, the next boot is the test, and the device is a single physical unit with no working recovery partition. [historical: undated, docs/INSTALL_LOCKED.md]

Take and verify a backup before using `--remove`, and treat the typed confirmation as the last reversible moment rather than as a safety mechanism. [inferred] The guards refuse four packages by name and everything outside `/system/app` by location; they do not make a permitted deletion recoverable, and nothing tests them. [verified]
