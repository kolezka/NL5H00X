# Why this device cannot install apps, and what to do about it

**Summary:** every normal install on the NL5H00X fails with
`INSTALL_FAILED_INVALID_INSTALL_LOCATION`, regardless of transfer method, flags
or uid. The failure is inside the vendor's patched `PackageManagerService`. It
is not fixable from userspace, and the supported route is copying the app into
`/system/app` — which requires unpacking the APK's native libraries by hand.

Use `scripts/INSTALL_APP.sh`, which does all of this and refuses the one class of
APK that can brick the device.

---

## The symptom

```
$ adb install SmartTube_stable_31.94_armeabi-v7a.apk
Performing Streamed Install
adb: failed to install ...: Failure [INSTALL_FAILED_INVALID_INSTALL_LOCATION]
```

`/data/app` is empty and `pm list packages -3` returns nothing. **Nothing has ever
been installed normally on this device.** Everything present — APKPure, Magisk,
Nova, Projectivy — sits in `/system/app`.

## What was ruled out

Each of these was checked on hardware, 2026-07-30, and is clean:

| Hypothesis | Evidence against |
|---|---|
| Sideloading disabled | `install_non_market_apps` = 1 in both `global` and `secure` |
| Package verifier blocking | `package_verifier_enable` = 0, `verifier_verify_adb_installs` = 0 |
| Out of space | 3.8 GB free on `/data`; a 25 MB APK fails, and so does a 1 KB session |
| User restriction / device policy | No restrictions on user 0; no device owner. Only `guest` has `no_install_unknown_sources` |
| `installd` dead | `init.svc.installd` = running |
| Wrong ABI | Fails identically for the correct `armeabi-v7a` build, and for arch-independent APKs |
| Missing package installer | `com.android.packageinstaller` present and reached — it is what shows the failure dialog |
| Needs root | `su 0 pm install` fails with the *same* error |
| Transfer method | adb streamed, `pm install` from a local file, and `-f` (`INSTALL_INTERNAL`) all fail identically |
| Install location preference | `pm get-install-location` = 0 (auto); sessions create fine at 1 KB, 25 MB and 3 GB |

## Where it actually fails

The vendor added a log line AOSP does not have, and it is the last thing printed
before the failure:

```
D/PackageManager( 1865): handleStartCopy: org.smarttube.stable
I/ActivityManager( 1865): START ... com.android.packageinstaller/.InstallFailed
D/InstallFailed(16053): Installation status code: 1
```

So the install dies inside `handleStartCopy()`, at install-location resolution,
before a single byte is copied.

One inference is solid. In `PackageHelper.resolveInstallLocation`, running out of
room returns `RECOMMEND_FAILED_INSUFFICIENT_STORAGE`, which surfaces as
`INSTALL_FAILED_INSUFFICIENT_STORAGE`. The only path to
`RECOMMEND_FAILED_INVALID_LOCATION` — and therefore to the error this device
actually returns — is an exception thrown while resolving the volume. **This is a
thrown exception, not a capacity decision.** The two branches are mutually
exclusive, which is why "free up space" advice does nothing here.

**Which call throws is not established.** Determining it means decompiling the
vendor's `/system/framework/services.jar`, since the relevant code is modified
from AOSP. That is a read-only investigation and safe to do; it just has not been
done.

## Why it is not worth fixing at the source

Any real fix lives in `services.jar`, which is loaded by `system_server` at boot.
Replacing it on a device with **no working recovery partition** — U-Boot logs
`starting system with command 'recovery'` and then boots normal Android anyway —
risks a device that cannot boot and cannot be rescued except over UART. Weighed
against a workaround that already works, patching the framework is the wrong
trade. See [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) for what a non-booting NL5H00X
costs to recover.

## The workaround, and its one sharp edge

Copy the APK into `/system/app/<Name>/<Name>.apk` and reboot. The package
manager scans `/system/app` at boot and registers it.

**Native libraries may not come along for the ride** — and whether they do
depends on a manifest flag that is easy to miss.

An APK either wants its libraries extracted or loads them straight out of itself:

| `android:extractNativeLibs` | `.so` stored as | Needs `lib/<isa>/`? |
|---|---|---|
| `false` | `Stored` (uncompressed, aligned) | No — loaded from inside the APK |
| `true`, or absent (the default for `targetSdk` >= 23) | `Deflated` | **Yes** |

This is why the toolkit's launcher path got away with copying only the APK for so
long: Projectivy sets `extractNativeLibs="false"` and ships its three `.so` files
uncompressed, so it works without a `lib/` directory. SmartTube does not set the
flag at all and ships deflated libraries, so it does not.

A normal install extracts `lib/<abi>/*.so` into the app's native library
directory. Copying the APK does not, and an app in the second row of that table
then dies at the first `System.loadLibrary`:

```
loadFormatInfo error: IllegalStateException: J2V8 native library not loaded
(j2v8-android-arm_32): dalvik.system.PathClassLoader[DexPathList[[zip file
"/system/app/SmartTube/SmartTube.apk"],nativeLibraryDirectories=[...]]]
```

Measured on hardware 2026-07-30: SmartTube installed, launched and browsed
correctly, and failed only on playback — the kind of partial success that reads
as "the app is broken" rather than "the install was incomplete".

`INSTALL_APP.sh` unpacks them unconditionally rather than reading the flag: for
an `extractNativeLibs="false"` app the extra copy is redundant but inert, and
getting the flag wrong in the other direction produces an app that installs,
launches, and fails later on some feature nobody thought to test.

The fix is to unpack them into the ISA directory the platform expects:

```
/system/app/SmartTube/
├── SmartTube.apk
└── lib/
    └── arm/            # armeabi-v7a -> arm, arm64-v8a -> arm64
        ├── libj2v8.so
        └── ...
```

Confirm it took by checking that the package manager resolved an ABI — a null
`primaryCpuAbi` means the libraries will not load:

```
$ adb shell dumpsys package org.smarttube.stable | grep -E "primaryCpuAbi|NativeLibrary"
    legacyNativeLibraryDir=/system/app/SmartTube/lib
    primaryCpuAbi=armeabi-v7a
```

## Consequences of installing this way

- The app is a **system app**. It cannot be uninstalled through the UI; removing
  it means deleting the directory from `/system` and rebooting
  (`scripts/INSTALL_APP.sh --remove <package>`).
- It **only registers on the next boot**, never immediately.
- It consumes space on the 1.7 GB system partition, not on `/data`.
- An APK declaring `CATEGORY_HOME` becomes a launcher candidate the moment it
  registers. On this firmware that is exactly how the device stops booting —
  `INSTALL_APP.sh` refuses such APKs unless `--allow-home` is given. See
  [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md).

## Related

- Part of: [README](../README.md)
- See also: [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) — what happens when the home
  intent is got wrong, and how to recover
- Implemented by: `scripts/INSTALL_APP.sh`
- Same fallback, launcher-specific: `launcher_present_apply()` in
  `scripts/lib/unlock.sh`

_Last updated: 2026-07-30_
