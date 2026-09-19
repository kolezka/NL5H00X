---
block: app-install
doc: DECISIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Decisions

## Write into /system/app instead of fixing the package manager

Every normal install on this device fails with
`INSTALL_FAILED_INVALID_INSTALL_LOCATION` regardless of transfer method, flags or
uid, and the failure is inside the vendor's patched `PackageManagerService` during
install-location resolution; that conclusion and the hypotheses ruled out to reach
it are in `docs/INSTALL_LOCKED.md::INSTALL_FAILED_INVALID_INSTALL_LOCATION` and
were not re-measured here [assumption]. The script
therefore does not try to make a normal install work; it tries one, then copies
the app into `/system/app` [verified].

### Rejected alternative: patch services.jar

A real fix lives in the framework jar loaded by the system server at boot, on a
device whose recovery partition does not work, so a bad replacement leaves a unit
that cannot boot and cannot be rescued except over serial, per
`docs/INSTALL_LOCKED.md::"no working recovery partition"` [assumption]. Weighed against a
workaround that already works, that trade lost [verified]. Boot recovery belongs
to [unlock](../unlock/README.md).

## Parse the binary manifest in the script

`scripts/INSTALL_APP.sh::apk_facts()` unzips `AndroidManifest.xml` and decodes the
resource string pool and chunk tree in embedded Python [verified].

### Rejected alternative: call aapt

`aapt` ships with the Android SDK build-tools, which someone fixing a projector
over adb has no reason to have installed [verified]. The script depends only on
`unzip` and `python3`, both checked before it starts [verified].

### Rejected alternative: scan the APK as text

The string pool is UTF-16 unless a flag says otherwise, and `strings` on macOS
cannot read UTF-16, so grepping an APK for the home category reports a clean
result for every APK ever made, per the header comment above
`scripts/INSTALL_APP.sh::apk_facts()` [assumption]. A false clearance on the one check that
prevents bricking the device is worse than no check, because it looks like a check
[inferred]. The decoded pool is additionally sanity-checked against
`android.intent.action.MAIN` so that a failed decode reports itself [verified].

## Read the package name from the element tree

The chunk walk finds the `manifest` START_TAG and reads its `package` attribute
[verified].

### Rejected alternative: pick it out of the string pool

The pool holds every string in the file with no structure attached, so choosing
which one is the package name is guesswork [verified]. The home check can work off
the flat pool because it only asks whether a known string is present; the package
name cannot, because it asks which string plays a particular role [inferred].

## Unpack native libraries unconditionally

`scripts/INSTALL_APP.sh::install_app()` extracts and copies `.so` files whenever
the APK has a matching ABI, without consulting the manifest flag that says whether
the platform needs them extracted [verified].

### Rejected alternative: read extractNativeLibs and unpack only when needed

For an app that sets the flag false the extra copy is redundant but inert, while
getting the flag wrong in the other direction produces an app that installs,
launches and then fails later on some feature nobody thought to test, per
`docs/INSTALL_LOCKED.md::"redundant but inert"` [assumption]. The asymmetry
is the whole argument: one branch wastes a few megabytes of a partition, the other
ships a broken app that looks fine [inferred].
