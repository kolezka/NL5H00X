# Why this device cannot install apps, and what to do about it

Last updated: 2026-10-24.

**Summary:** the install attempts recorded on 2026-07-30 failed with
`INSTALL_FAILED_INVALID_INSTALL_LOCATION`, including root and multiple transfer
methods. Offline analysis on 2026-10-24 identified an additional vendor whitelist
gate that returns this error under the currently read configuration: the control
property is empty and the whitelist file has zero bytes. This is a code-and-input
finding, not a new install trial or proof that bypassing the gate is sufficient.
The historical workaround is placing a compatible APK under `/system/app`, with
its native libraries when required. See the
[October device audit](DEVICE_AUDIT_2026-10-24.md).

`scripts/INSTALL_APP.sh` implements that workaround and rejects HOME or
SETUP_WIZARD declarations by default. That guard reduces a known boot risk;
it is not proof that every other APK is safe.

---

## The symptom

```
$ adb install SmartTube_stable_31.94_armeabi-v7a.apk
Performing Streamed Install
adb: failed to install ...: Failure [INSTALL_FAILED_INVALID_INSTALL_LOCATION]
```

The July inspection found `/data/app` empty and no third-party entries from
`pm list packages -3`. APKPure, Magisk, Nova and Projectivy were under
`/system/app`. This records that snapshot, not every installation in the device's
history. The October package listing still placed these named apps in `/system`.

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

## What the historical log establishes

The recorded log places the failure after the vendor's `handleStartCopy` message:

```text
D/PackageManager( 1865): handleStartCopy: org.smarttube.stable
I/ActivityManager( 1865): START ... com.android.packageinstaller/.InstallFailed
D/InstallFailed(16053): Installation status code: 1
```

That does not identify the exact failing branch. The earlier claim that this
error necessarily means a volume-resolution exception was an unverified inference
from AOSP, not proof about this vendor build. It is withdrawn.

### Current investigation inputs

The October audit found `/system/framework/services.jar` is only 183 bytes and
contains `META-INF/MANIFEST.MF`, with no DEX. The matching code artifacts are
`/system/framework/oat/arm/services.vdex` (VDEX019) and `services.odex` (ELF32).
They were copied and checked against device SHA-256 hashes; see
[the audit](DEVICE_AUDIT_2026-10-24.md#framework-and-signing-evidence).

### Verified vendor whitelist branch

The recovered `PackageManagerService$InstallParams.handleStartCopy()` reads
`SystemProperties.get("zyzys.install.whitelist")` with one argument. If the value
is not exactly `"0"`, it calls `PackageManagerService.enableInstallApk(packageName)`.
That method reads `/system/etc/WhiteListPermissionFilter.cfg` and returns true
when `packageName.contains(line)` matches a line. A missing, unreadable or
zero-line file returns false. These are substring matches, not exact package
identity checks. A blank line is not equivalent to a zero-byte file.

The relevant flow, simplified from the recovered instructions, is:

```text
getMinimalPackageInfo(...)       # Runs before this gate; may compute location
log("handleStartCopy: " + packageName)
if property != "0" and not enableInstallApk(packageName):
    result = -19
else:
    continue normal location/install checks
if result != success:
    skip copyApk
mRet = result
```

Live reads through the verified root client found the property empty and the
root-owned, readable configuration file exactly zero bytes. A read of the known
SDK property through the same command path returned `28`, validating the empty
property observation. Those inputs select the explicit whitelist denial. A
volume-resolution exception is not needed to explain it.

For the artifact hashes in the audit, method-relative code-unit offsets are:

| Method | Evidence offsets |
|---|---|
| `InstallParams.handleStartCopy()` | `0x45`: initialize `-0x13`; `0xad` to `0xca`: property/whitelist gate; `0x130`: skip later policy on failure; `0x199`: carry result; `0x1a2`: skip copy; `0x340`: store `mRet` |
| `PackageManagerService.enableInstallApk(String)` | `0x5`: configuration path; `0x24`: read lines; `0x59`: substring match; `0x62`: no match returns false |

The code was recovered offline using Android SDK dexlib2/baksmali 3.0.9 with
API 28 decoding. The original JAR has no code; the ODEX reader resolves its
matching VDEX/CompactDex. This finding concerns that exact vendor build.

**Limit:** no property was changed and no installation attempted. Setting the
property to `"0"` would skip this gate according to the code; it is not a verified
installation fix. The subsequent location checks can independently return `-19`.
The historical log alone cannot establish which branch ran in every old attempt.

## Framework modification and recovery limits

Replacing PackageManager code can prevent `system_server` from booting. A recovery
partition exists and its Android header was read, but a usable recovery boot or
restore procedure has not been verified. Android UART access is not proof that a
broken kernel or bootloader can be recovered.

Keep investigation offline first. Do not replace the framework until the exact
branch and a reversible change are understood and the relevant
[recovery safety HOLD](../tests/contracts/observations/recovery-hazards.md) has been
resolved. See [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) for the narrower Android-level
failure that was recovered over UART.

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

## The other sharp edge: apps that only ship as split bundles

`INSTALL_APP.sh` takes exactly one APK, and a lot of current apps are not
distributed as one. A Play-style bundle is a base APK plus config splits — one
per ABI, one per density, one per language — and the `.so` files live in the ABI
split, not in the base.

Checked 2026-08-07 on Prime Video (Android TV), `com.amazon.amazonvideo.livingroom`:
eleven releases sampled across the range 6.24.4 down to 6.17.0 (June 2024) are
**all** bundles — 26 splits each, or 27 for the `allAbis` uploads that carry arm64
as well. Older releases were not checked. There is no standalone APK anywhere in
that range, so "find a plain APK instead" is not a strategy for this app.

The obvious route is a split install, and it fails exactly like everything else:

```
$ adb install-multiple base.apk split_config.armeabi_v7a.apk \
      split_config.xhdpi.apk split_config.en.apk split_config.pl.apk
adb: failed to finalize session
Failure [INSTALL_FAILED_INVALID_INSTALL_LOCATION]
```

Same error, same patched PMS. Splits change nothing — this is not a separate
problem to solve, it is the same one.

So the splits have to become a single APK before `/system/app` can take it.
Merging rewrites the archive, which invalidates the developer's signature, so the
result must be re-signed with a local key. For a package that has never been
installed here that is harmless: nothing on the device holds a prior signature to
match against.

```
$ java -jar APKEditor.jar m -i app.apkm -o merged.apk
$ zipalign -f -p 4 merged.apk aligned.apk
$ apksigner sign --ks local.jks --min-sdk-version 21 --out App.apk aligned.apk
```

**The trap is `requiredSplitTypes`.** The base manifest declares
`requiredSplitTypes="base__abi,base__density"`, and a base APK moved on its own
is a package with no native code and no resources. APKEditor drops the attribute
in its "Sanitizing manifest" pass — verify that it actually did, because nothing
downstream will complain until the app fails to start:

```
$ aapt2 dump xmltree --file AndroidManifest.xml App.apk | grep requiredSplitTypes
                                              # must print nothing
$ aapt2 dump badging App.apk | grep -E "^package|native-code"
package: name='com.amazon.amazonvideo.livingroom' versionCode='606023231' ...
native-code: 'armeabi-v7a'
$ zipalign -c -p -v 4 App.apk | tail -1
Verification successful
```

That last check is not ceremony. The merged app kept `extractNativeLibs="false"`,
which means the platform maps the `.so` files straight out of the archive and
they must stay `Stored` and aligned — a merge that recompresses them produces an
APK that installs and then dies at the first `System.loadLibrary`, which is the
same failure mode as the missing `lib/` directory above, from a different cause.

Measured result, 2026-08-07: 26 MB merged APK, registered after the reboot with
`primaryCpuAbi=armeabi-v7a`, `IgnitionActivity` reached `mResumedActivity`, and
the leanback UI rendered with artwork. Playback was not tested — that needs an
account, and this device's Widevine level is still unestablished.

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
- A merged bundle carries a **locally generated signature**, not the developer's.
  Nothing on this device checked it, but an app that verifies its own signature at
  runtime would, and there is no upgrade path afterwards: every new version means
  downloading the bundle and repeating the merge by hand.

## Related

- Part of: [README](../README.md)
- See also: [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) — what happens when the home
  intent is got wrong, and how to recover
- Implemented by: `scripts/INSTALL_APP.sh`
- Same fallback, launcher-specific: `launcher_present_apply()` in
  `scripts/lib/unlock.sh`

_Historical installation examples date from July and August 2026. Current policy
analysis and evidence limits were updated on 2026-10-24._
