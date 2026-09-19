---
block: app-install
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## Command line

One positional APK path installs, `--remove PKG` removes, and the two are
mutually exclusive because the remove branch is taken first and the APK argument
is then ignored [verified]. `--name NAME` picks the directory under
`/system/app`, `--allow-home` lifts the home refusal, and `--reboot` or
`--no-reboot` decides the reboot without asking [verified]. With neither an APK
nor `--remove`, the script prints usage and exits 1 [verified].

enforcement: `scripts/INSTALL_APP.sh::main()` (argument parse, runtime)

## Preconditions

`unzip` and `python3` must be on the host, and a device with working root must
answer, or the script exits 1 [verified]. The host tool check runs first, then
root is established, and both happen before the install or remove branch is chosen
[verified].

enforcement: `scripts/INSTALL_APP.sh::main()` (runtime, via `scripts/lib/common.sh::require_device()`)

## Normal install is tried first

The `/system/app` write is a fallback, not the primary path [verified]. The order
inside the install flow is manifest gate, package name, duplicate-copy check, ABI
gate, then `adb install -r` [verified]. When that install prints `Success` the
script reports it, writes nothing to `/system`, leaves the pending-install state
empty and exits without offering a reboot [verified].

enforcement: `scripts/INSTALL_APP.sh::install_app()` (runtime)

## Home intent refusal

An APK whose manifest string pool contains `android.intent.category.HOME` or
`android.intent.category.SETUP_WIZARD` is refused unless `--allow-home` is passed
[verified]. A manifest that cannot be parsed is also a refusal, not a pass
[verified]. This gate runs before anything touches the device [verified].

enforcement: `scripts/INSTALL_APP.sh::apk_facts()` (parse) and `scripts/INSTALL_APP.sh::install_app()` (gate)

## ABI gate

When the APK ships `lib/<abi>/*.so` entries, the install proceeds only if one of
those ABIs appears in the device's `ro.product.cpu.abilist` [verified]. The first
device ABI that matches wins, so the device's own preference order decides
[verified]. A matching ABI with no known ISA directory name is also refused
[verified]. An APK with no native libraries skips this gate entirely [verified].

enforcement: `scripts/INSTALL_APP.sh::apk_abis()` and `scripts/INSTALL_APP.sh::abi_to_isa()` (runtime)

## On-device layout

The install produces `/system/app/<Name>/<Name>.apk` at mode 644 inside a
directory at mode 755, owned by root [verified]. When the APK has native code for
a supported ABI, the `.so` files are flattened out of `lib/<abi>/` and written to
`/system/app/<Name>/lib/<isa>/` at mode 644 [verified]. Nothing else is written
into the app directory [verified].

enforcement: `scripts/INSTALL_APP.sh::install_app()` (runtime)

## Everything written is checksum verified

The staged upload is compared against the local file before the copy, and the APK
and every unpacked library are compared again after the copy into `/system`
[verified]. A mismatch fails the install [verified]. The comparison is MD5 on both
ends [verified].

enforcement: `scripts/INSTALL_APP.sh::local_md5()` against on-device `md5sum` (runtime)

## /system is left read-only

Every path that remounts `/system` writable remounts it read-only again before the
function returns, on both the install and remove flows [verified]. Verification
runs after the read-only remount, so a checksum failure does not leave the
partition writable [verified].

enforcement: `scripts/lib/unlock.sh::system_ro()` called from `scripts/INSTALL_APP.sh::install_app()` and `scripts/INSTALL_APP.sh::remove_app()` (runtime)

## Registration happens on the next boot

A staged app does not exist for the package manager until `/system/app` is
rescanned at boot [verified]. With `--no-reboot`, or when the reboot prompt is
declined, the script says so and exits 0 with the app staged but unregistered
[verified].

enforcement: `scripts/INSTALL_APP.sh::main()` (runtime) and the post-boot check in `scripts/INSTALL_APP.sh::verify_installed()`

## Post-boot verification

After a reboot the script requires that the package registered, and, when the APK
had native code, that the package manager resolved a non-null `primaryCpuAbi`
[verified]. Either failure exits 1 [verified]. This check runs only when the
script performed the reboot itself [verified].

enforcement: `scripts/INSTALL_APP.sh::verify_installed()` (runtime)

## Removal

`--remove` is the only supported removal path, because an app installed this way
is a system app and cannot be uninstalled from the UI [verified]. It refuses any
package in the protected list, refuses a package whose recorded `codePath` is not
under `/system/app`, requires the operator to retype the package name, and fails
if the directory still exists afterwards [verified]. The protected list is the
home dispatcher `com.newlink.wtprovision`, the stock launcher
`com.newlink.hisilauncher`, `com.android.tv.settings` and `com.android.settings`
[verified].

enforcement: `scripts/INSTALL_APP.sh::PROTECTED_PKGS` and `scripts/INSTALL_APP.sh::remove_app()` (runtime)

## Ordering against the launcher default

The project README states that installing any app which declares a `LAUNCHER`
category makes Android clear the recorded home preference, so HOME shows the
chooser again afterwards; that is read from `README.md::"recorded home preference"`
at the pin and was not re-measured on the device here [assumption]. Given that,
and given that the home preference is written by
`scripts/lib/unlock.sh::launcher_default_apply()` in
[unlock](../unlock/README.md), an install run after that step undoes it, so the
launcher default must be set last [inferred]. Nothing in this block checks or
restores the preference [verified].

enforcement: convention
