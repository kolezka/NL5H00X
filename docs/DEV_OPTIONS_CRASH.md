# Why Developer options crash, and the platform key that lets you fix them

**Summary:** selecting *Ustawienia urządzenia → Opcje programistyczne* kills
`com.android.tv.settings` instantly and silently — the panel vanishes and focus
falls back to whatever was underneath. The cause is not configuration: the OEM's
settings screen calls a USB device-mode API on hardware that has no USB device
controller, and the framework throws. No navigation path avoids it. The screen
can only be fixed by changing code — which turns out to be practical, because
**this device is signed with the public AOSP test platform key.**

## The symptom

Nothing appears. There is no error dialog, so it reads as an unresponsive menu
item rather than a crash. The menu entry itself is present and reachable; the
developer mode is already unlocked (`development_settings_enabled=1`,
`adb_enabled=1`). Only the screen is unreachable.

## Root cause

```
DevelopmentFragment.onCreateView:580
  -> DevelopmentFragment.updateUsbConfigurationValues:1274
    -> UsbManager.getCurrentFunctions:718
      -> IUsbManager$Stub$Proxy.getCurrentFunctions:866
        -> UsbService.getCurrentFunctions:418   (Preconditions.checkState)
```

`UsbService` creates its `mDeviceManager` only when `/sys/class/android_usb`
exists. On this device it does not, and neither does `/sys/class/udc`. The field
stays null, the precondition fails, and the fragment dies in `onCreateView` —
before it draws anything.

The hardware story is consistent: `pm list features` reports only
`android.hardware.usb.host`, and `dumpsys usb` returns a populated host manager
while the gadget side throws. The projector can be a USB *host*; it cannot be a
USB *device*.

## What was ruled out

| Hypothesis | Why not |
|-----------|---------|
| Developer mode not unlocked | `development_settings_enabled=1`; the menu entry is present |
| Wrong entry point | `cmd package query-activities` for `APPLICATION_DEVELOPMENT_SETTINGS` returns exactly one activity — the one that crashes |
| A different launcher would work | Reproduced from `tv.nativesettings.launcher`, from the remote, and from `am start` — same stack every time |
| Create the missing sysfs path | sysfs is kernel-backed; you cannot `mkdir` in it. Faking it would move the crash into `system_server`, whose death restarts Android — that is worse, not better |
| Stale state, fixable by reboot | Reproduced after a clean reboot |

This is a bug in the vendor's build: `DevelopmentFragment` calls the USB
device-mode API unconditionally, on a device that cannot support it.

## The platform key

`/system/priv-app/TvSettings/TvSettings.apk` declares
`sharedUserId="android.uid.system"`, so any replacement must carry the same
signature or the package stops being registered — which would cost you the entire
Settings app.

The signing certificate's DN is `android@android.com`, which *suggests* AOSP test
keys but does not prove them: a vendor can generate its own key and keep the
default subject. The decisive check is the digest.

| | SHA-256 of certificate |
|---|---|
| `TvSettings.apk` on the device | `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8` |
| AOSP `build/target/product/security/platform.x509.pem` | `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8` |

They match, and the public `platform.pk8` modulus matches that certificate. **The
private key for this device's platform signature is published in AOSP.**

That is the enabling fact for far more than this one screen: any system component
here can be modified and re-signed so that the shared system UID still matches.
It is also, bluntly, the device's security posture — see
[SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md).

Original APK signs with v1 + v2 + v3 (no v3.1, no v4); reproduce those schemes.

## The patch

Two edits in
`smali/com/android/tv/settings/system/development/DevelopmentFragment.smali`:

| | Method | Change |
|---|--------|--------|
| A | `updateUsbConfigurationValues` | `if-eqz v0, :cond_2` → `goto :cond_2` |
| B | `writeUsbConfigurationOption` | insert `return-void` at entry |

Patch A invents no control flow. The method already opens with "if there is no
USB preference, do nothing", and that branch leads straight to `return-void`;
forcing the jump just always takes the escape the code already has.

Patch B covers `setCurrentFunctions`, a *second* USB call that never appeared in
any crash log — because you cannot reach it until the screen renders. It would
have crashed the moment anyone selected the USB configuration item.

### Rebuilding without breaking resources

Decompile with `apktool d -r`. Without `-r`, apktool re-encodes `resources.arsc`,
and this is a system APK built against the vendor's `framework-res` — the rebuild
can shift resource IDs.

Verify the rebuild touched only code before signing anything:

| Entry | CRC before → after |
|-------|-------------------|
| `resources.arsc` | `568a3f58` → `568a3f58` |
| `AndroidManifest.xml` | `22360890` → `22360890` |
| `classes.dex` | `5b087a56` → `f2fb4350` |

638 entries in, 635 out; the three that vanish are `META-INF/CERT.RSA`,
`CERT.SF` and `MANIFEST.MF`, regenerated when signing.

```sh
apktool d -r -f -o tvs TvSettings.apk
# ... patch smali ...
apktool b -o patched-raw.apk tvs
zipalign -f -p 4 patched-raw.apk patched-aligned.apk
apksigner sign --key platform.pk8 --cert platform.x509.pem \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out patched.apk patched-aligned.apk
```

Confirm the signed result reports the same `c8a2e9bc…` digest before going near
`/system`, and keep a byte-verified copy of the original APK first.

**Status: built and verified up to signing; not yet deployed or confirmed on the
device.** Deployment additionally needs `/system` remounted read-write and a
reboot so PackageManager rescans. The USB configuration item stays visible but
inert — removing it from the list means touching resources, which this approach
deliberately avoids.

## If you only need the settings, not the screen

Every value behind that screen is reachable without it:

```sh
adb shell settings put global window_animation_scale 0.5
```

`WRITE_SECURE_SETTINGS` has protection level `signature|privileged|development`,
and the `development` flag means an ordinary app can be granted it from the
shell (`pm grant`) — so a replacement UI is possible without the platform key at
all. Note that installing that app still lands in `/system/app`, because normal
installs fail on this device; see [INSTALL_LOCKED.md](INSTALL_LOCKED.md).
