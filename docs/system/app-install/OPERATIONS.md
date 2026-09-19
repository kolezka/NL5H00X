---
block: app-install
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

The script is a one-shot run, not a service [verified]. Two entry shapes exist:
an APK path installs, and `--remove PKG` removes [verified].

```sh
scripts/INSTALL_APP.sh app.apk
scripts/INSTALL_APP.sh app.apk --name MyApp --no-reboot
scripts/INSTALL_APP.sh --remove com.example.app
```

Guards run in this order: argument parse, usage exit when neither an APK nor
`--remove` was given, a missing-file check on the APK path, the presence of
`unzip` and `python3` on the host, then device and root setup [verified].

There is no stop. Once the copy into `/system` has started the only interruptions
are the checksum failures, and an aborted run can leave a partially written app
directory that the next run overwrites [inferred].

Three prompts read from the terminal directly rather than from standard input: the
duplicate-copy confirmation, the removal confirmation and the reboot question
[verified]. That is deliberate, because `adb shell` swallows the script's standard
input and a piped answer is forwarded to the device instead of reaching the read
[verified]. Piping answers into this script does not work; use `--reboot`,
`--no-reboot` or a terminal [inferred].

## Observe

All progress goes to the terminal through the printing helpers from
[device-access](../device-access/README.md), with warnings and errors on standard
error [verified]. There is no log file [verified].

The two facts the script itself reads back from the device are the recorded
`codePath` of a package and its `primaryCpuAbi`, both parsed out of
`dumpsys package` [verified]. Registration is checked through
`scripts/lib/unlock.sh::package_installed()` [verified]. A null `primaryCpuAbi`
after a reboot is the signal that the native libraries will not load, and the
script prints the directory to check [verified].

The reboot itself is observed through `sys.boot_completed` plus a `/proc/uptime`
comparison, polled every 5 seconds for up to 40 attempts [verified].

## Configuration and paths

There are no environment variables and no config file in this block [verified].
Four resolvers decide where things land.

The install root is the constant `scripts/INSTALL_APP.sh::SYSTEM_APP_DIR` and the
host-to-device staging area is the constant `scripts/INSTALL_APP.sh::STAGING`
[verified]. Neither is overridable [verified].

The app directory name comes from `--name` when given, otherwise from
`scripts/INSTALL_APP.sh::default_name_from_apk()`, which takes the leading
alphanumeric run of the APK filename and falls back to the filename with every
non-alphanumeric character stripped [verified]. The APK inside is always named
after the directory [verified].

The library directory is `lib/<isa>/` under the app directory, where the ISA is
`scripts/INSTALL_APP.sh::abi_to_isa()` applied to the first ABI in the device's
`ro.product.cpu.abilist` that the APK also ships [verified]. Device order decides,
not APK order [verified]. Unknown ABI names map to an empty ISA and abort the
install [verified].

The reboot decision defaults to asking, `--reboot` answers yes and `--no-reboot`
answers no, and the last flag on the command line wins because each simply assigns
`scripts/INSTALL_APP.sh::DO_REBOOT` [verified].

## Failure and recovery

Every refusal before the staging step leaves the device untouched, so an APK
rejected for its manifest, its ABI or an unreadable manifest needs no recovery
[verified].

A failed remount aborts the install after cleaning up the staged file [verified].
A checksum mismatch on the staged upload removes the staged file; a checksum
mismatch after the copy into `/system` does not remove the bad app directory, and
that directory has to be cleared by hand or by a re-run [verified].

The known stuck state is a device that does not come back from the reboot. The
script waits 200 seconds, then points at the boot deadlock write-up and
`scripts/UNLOCK.sh --repair` [verified]. Recovery is outside this block and
belongs to [unlock](../unlock/README.md) [verified].

A device that answers again but with uptime intact is reported as a failure, not a
success, and the post-boot verification is skipped in that case [verified].

Removing an app installed this way is `--remove`, never the launcher or the
settings UI, because the app is a system app [verified].
