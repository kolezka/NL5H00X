---
block: app-install
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Gaps

## Nothing tests this script at all

No suite exercises `scripts/INSTALL_APP.sh` at this pin: the only entry scripts the tests launch are `MAKE_BACKUP.sh`, `UNLOCK.sh`, `TOOLS.sh` and `PROJECTOR.sh`. [verified] Reproduce with `git grep -n -i INSTALL_APP f04ee86 -- tests/`, which returns nothing. [verified]

This block therefore has no enforcement beyond its own run time checks, and a run time check protects the run it is part of, not the next edit. [inferred] The parts that would be cheapest to cover are also the ones where a regression is silent: `scripts/INSTALL_APP.sh::apk_facts()` can be driven by a fixture APK with no device involved, and `scripts/INSTALL_APP.sh::abi_to_isa()` and `scripts/INSTALL_APP.sh::default_name_from_apk()` are pure functions. [inferred] The fake ADB already models `pm`, `dumpsys` and `adb install` refusal for other blocks, so the device facing paths are reachable too. [verified]

## The launcher the toolkit installs is not protected from removal

`scripts/INSTALL_APP.sh::PROTECTED_PKGS` names the stock launcher and the home dispatcher but not `scripts/lib/unlock.sh::LAUNCHER_PKG`, the replacement launcher the unlock path installs and makes the home activity. [verified] That block's fallback install target is `scripts/lib/unlock.sh::LAUNCHER_SYSTEM_DIR`, which defaults to a directory under `/system/app`. [verified] The `codePath` guard therefore passes and the name guard does not apply, leaving `--remove` willing to delete the package that is currently answering the home intent. [inferred] Details of how that launcher is chosen and registered belong to [`unlock`](../unlock/README.md).

The two lists are also independent copies of the same package names, so a rename on either side leaves one of them guarding nothing. [verified]

## /system can be left writable

`install_app()` and `remove_app()` both open the write window with `system_rw` and close it with `system_ro`, and neither installs a `trap`. [verified] An interrupt, a host crash or a disconnected cable between those two points leaves `/system` mounted read write with no message. [inferred]

The close is also unverified. `scripts/lib/unlock.sh::system_ro()` discards the remount status, and this block never re-reads the mount state afterwards, so a failed remount to read only is indistinguishable from a successful one from inside this script. [verified] The mechanism is owned by [`unlock`](../unlock/README.md); the consequence here is that a successful looking install can end with the partition still writable.

## Modes and ownership are never checked

The `chmod` and `chown` calls on the installed directory, the APK and the library directory all discard their status, and verification covers file contents only. [verified] An install where `chown -R root:root` failed passes every check this script makes and can still fail to load at run time on the device. [inferred] Nothing reads back a mode, an owner or a SELinux context. [verified]

## A path containing a single quote fails late and leaves debris

`scripts/lib/common.sh::adb_root_exec()` refuses any command containing a single quote and returns without contacting the device. [verified] On the install path those calls are written with a trailing `|| true`, so the refusal is swallowed and the run continues to the digest check, which then fails on a file that was never created. [inferred] The reported error names a digest mismatch rather than the rejected command. [inferred]

## The directory name from --name is not validated

`--name` is used unquoted inside the remote command string, so a value containing whitespace or a shell metacharacter is expanded by the device shell rather than treated as one directory name. [verified] `scripts/INSTALL_APP.sh::default_name_from_apk()` only produces alphanumeric names, so this is reachable only through the flag. [verified] The digest check fails afterwards, but the partial directories created under `/system/app` are not cleaned up. [inferred]

## Nothing verifies the result when the reboot is skipped

`scripts/INSTALL_APP.sh::verify_installed()` runs only after a reboot this script performed. [verified] With `--no-reboot`, or with a declined prompt, the script exits 0 having verified the bytes on disk and nothing about registration or the resolved ABI. [verified] The next boot is when the outcome becomes visible, and by then the operator has no output from this run to compare against. [inferred]

## The removal path takes no backup

`remove_app()` deletes the directory with `rm -rf` and keeps no copy, on or off the device. [verified] The only guards are the name list, the `codePath` prefix and the typed confirmation, all of which run before the delete and none of which make it reversible. [verified] Recovery cost is set out in `OPERATIONS.md`.

## MD5 is a corruption check, not an integrity check

Both digest comparisons use MD5. [verified] That is adequate for detecting a truncated or garbled transfer, which is what the comparison is for, and it is not evidence that the APK is the one its publisher signed. [inferred] For a merged split bundle the signature is in any case locally generated rather than the developer's. [historical: 2026-08-07, docs/INSTALL_LOCKED.md]

## The digest tool is missing from the preflight check

`scripts/INSTALL_APP.sh::main()` verifies `unzip` and `python3` but not `md5` or `md5sum`. [verified] A host with neither reaches the first digest call partway through an install, after the APK has already been staged on the device. [inferred]

## An option given as the final argument aborts without a message

`--name` and `--remove` both consume a value with `shift 2`. [verified] Supplied as the last word on the command line there is no second argument to shift, and under `set -euo pipefail` the failing `shift` ends the script rather than reaching the usage text. [inferred]

## A temporary directory leaks on one failure path

The local unpack directory is removed on unpack failure, on library upload failure and at the end of verification. [verified] The branch that fails on an APK digest mismatch returns before reaching that cleanup, leaving the extracted libraries in a `mktemp` directory on the host. [verified]

## The refusal message can be empty

When the normal install fails, the reason is extracted by matching `Failure [...]` in the output. [verified] Any failure whose text does not match that shape, including a transport error, prints an empty reason and the script proceeds to the fallback regardless. [inferred]
