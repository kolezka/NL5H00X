# Vendor system apps, read-only audit (2026-10-26)

Scope: the 22 packages from Newlink, Zhiying and HiSilicon in `/system/app` and
`/system/priv-app`. Method: every APK pulled (sha256 equal on device and host for
all 22), manifests read with `aapt2 dump xmltree`, runtime state from `ps` and
`dumpsys activity services`, string scan of `classes.dex` for cross-references.
Twelve APKs carry their code only in the vdex, so the string scan covers 10 of
22 and the dependency column is a lower bound for the rest. Nothing was changed.

Why it matters: 20 of 22 run as `android.uid.system`. Disabling the wrong one
is how the device stopped booting once (see [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md)).

## Verdicts

| Package | What it is | Running | Notable permissions | Verdict |
|---|---|---|---|---|
| `com.newlink.wtprovision` | Home dispatcher, persistent, declares SETUP_WIZARD | yes | INSTALL_PACKAGES, RECOVERY, SET_PREFERRED_APPLICATIONS, WRITE_SECURE_SETTINGS | **do not touch**, boot depends on it |
| `com.newlink.hisilauncher` | Stock launcher (RGTPLauncher), persistent | yes | FORCE_STOP_PACKAGES, location | **do not touch**, it is the fallback home |
| `com.zhiying.powerservice` | Power key and standby handling | no (boot receiver) | SYSTEM_ALERT_WINDOW | **do not touch**, power path |
| `com.hisilicon.tv.service` | HiSilicon TV platform service, persistent | yes | none notable | **do not touch**, platform |
| `com.hisilicon.rmservice` | Resource manager, persistent | yes | FORCE_STOP_PACKAGES | **do not touch**, platform |
| `com.hisilicon.tvinput.external` | HDMI, VGA, CVBS, YPbPr input services | yes | WRITE_SECURE_SETTINGS | **keep**, every external input goes through it |
| `com.hisilicon.android.inputmethod.remote` | Remote-control IME, persistent | yes | none | **keep**, text entry from the remote |
| `com.zhiying.settings` | Vendor settings UI (ZYSetting), 31 activities | no | RECOVERY, SHUTDOWN, WRITE_SECURE_SETTINGS, MASTER_CLEAR intent | **keep**, calls into wtprovision and hisetting |
| `com.newlink.hisetting` | Projection, zoom, Bluetooth helper (ZYCustomer) | no | INSTALL_PACKAGES, WRITE_SECURE_SETTINGS, location | **keep, review**, see below |
| `com.hisilicon.tvsetting` | HiSilicon settings, boot receiver | no | MASTER_CLEAR, RECOVERY, SHUTDOWN, INJECT_EVENTS | **keep, review**, receivers gated by a signature permission |
| `com.newlink.service` | Vendor telemetry and factory service | yes (BootService) | MASTER_CLEAR, RECOVERY, SHUTDOWN, WRITE_SECURE_SETTINGS, location | **keep, review**, see [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) |
| `com.zhiying.sourceui` | Source picker UI | no | RECOVERY | keep |
| `com.newlink.nlsource` | Source player stub | no | none | keep, referenced by the launcher and sourceui |
| `com.hisilicon.tvui` | TV UI, 13 exported activities | no | INTERACT_ACROSS_USERS | keep, referenced by launcher and sourceui |
| `com.newlink.cast` | Screen cast (HBCastNew) | no | INTERNET, SYSTEM_ALERT_WINDOW | optional, nothing depends on it |
| `com.hisilicon.miracast` | Miracast sink | no | none | optional, launcher references it |
| `com.newlink.filemanager` | File manager | no | PACKAGE_USAGE_STATS | optional, launcher and sourceui reference it |
| `com.hisilicon.android.videoplayer` | Video player, priv-app | no | INTERNET | optional |
| `com.hisilicon.android.music` | Music player | no | none | optional |
| `com.hisilicon.higallery` | Gallery | no | INTERNET | optional |
| `com.newlink.isuperred.ijkplayer` | IJK video player | no | INTERNET | optional |
| `com.hisilicon.tv.menu` | Factory menu | no | none | optional, factory only |

"Optional" means no other vendor package depends on it and it is not running.
It does not mean disabling it is tested. Any disable is a device change: one
package at a time, `pm disable-user`, reboot, confirm boot and HOME, with
`pm enable` as the revert.

## Findings worth a decision

**`com.newlink.hisetting` holds INSTALL_PACKAGES and references a package that
does not exist.** Its code names `com.newlink.install.InstallActivity`; `pm path
com.newlink.install` returns nothing. Two exported services (`MyService` on
action `android.hisi.zoom`, `ProjectionService` on `android.service.projection`)
have no permission attribute. They run as uid system. What they do when started
by an untrusted app is not decoded here; the APK has a classes.dex, so it can be.

**`com.newlink.service`** (NewLinkService) is the one already analysed. This
audit adds: the USB path is `UsbReceiver` (exported, MEDIA_MOUNTED) handing off
to `UsbIntentService` (not exported), which looks for files named
`ZMEnvFile.txt`, `activate_nowindow.txt`, `autotestmotor.txt`,
`autotestvideo.txt`, `screenReplace.txt` and a `zhiying_custom_update.json` on
the mounted volume, and its update URL is `http://www.newlinksz.com/product/update`
over plain HTTP. `BootService` and `ClearNotificationReceiver` are exported
without a permission. A USB stick is an input channel into a uid-system process.

**`com.hisilicon.tvsetting`** declares MASTER_CLEAR, RECOVERY and SHUTDOWN, but
its exported receivers require `com.hisilicon.permission.COMMON_PERMISSION`,
which is declared `signature` (protectionLevel 0x3) by HiSilicon packages. Only
platform-signed apps can send to them. On this device that is every app signed
with the published AOSP key, which is the posture described in
[DEV_OPTIONS_CRASH.md](DEV_OPTIONS_CRASH.md#the-platform-key).

**No vendor package is disabled today**, and no vendor component is disabled in
`package-restrictions`. Only `com.hisilicon.android.videoplayer` has a privapp
permission allow-list entry; the rest get their privileged permissions through
`sharedUserId=android.uid.system`, which bypasses the allow-list.

## Dependencies found by string scan (10 of 22 scanned)

| From | Mentions |
|---|---|
| `hisilauncher` | miracast, tvui, cast, filemanager, nlsource |
| `zhiying.sourceui` | tvui, filemanager, nlsource, zhiying.settings |
| `zhiying.settings` | hisetting, wtprovision, `com.zhiying.autofocus`, `com.zhiying.self.reboot` |
| `newlink.service` | hisetting |
| `newlink.cast` | `com.zhiying.launcher` (not installed) |
| `hisetting` | `com.newlink.install` (not installed) |
| `videoplayer` | tvsetting, tvui, explorer (not installed) |
| `nlsource` | tvinput.external |

## Decoded 2026-10-26: hisetting and newlink.service

Both APKs decompiled with `apktool d -r` and the smali read. Read-only.

**`com.newlink.hisetting`.** The two exported services are harmless.
`MyService` (action `android.hisi.zoom`) toggles the 4:3 / 16:9 aspect through
HiSilicon's `AdvancedPictureSetting`, mirrors the state into the property
`zyzys.newlink.fourThree`, and shows an overlay for two seconds. `ProjectionService`
(action `android.service.projection`) cycles the panel flip/mirror mode through
`Factory.setPanelFlipMirror` and shows an overlay. Neither reads intent extras,
runs a shell, writes files or touches packages. An untrusted caller can flip the
picture; that is all. `INSTALL_PACKAGES` is declared but never used by the app's
own code: `InstallActivity` fetches a JSON app list from
`http://www.newlinksz.com/app/OurAppUpdateANDIMG` (plain HTTP, fields
`packageName`, `versionCode`, `appDownload`, `IMG`), downloads the APK to
external storage with no checksum, and hands it to the system installer with an
`ACTION_VIEW` intent. That path is the vendor's app store; it is subject to the
install gate like any other install and does not run today unless the user
opens the activity. The missing `com.newlink.install` package is launched by
explicit component from `MainActivity` and simply fails to resolve.

**`com.newlink.service`.** `UsbReceiver` (exported, `MEDIA_MOUNTED`) starts the
non-exported `UsbIntentService`, which scans the mounted volume's root for fixed
file names. What each does:

| File on the USB stick | Effect | Gate |
|---|---|---|
| `activate.txt`, `activate_nowindow.txt` | sets `persist.sys.authenticate` and clears `persist.sys.date` | none |
| `autokeystone.txt` | starts `com.zhiying.AUTO_FOCUS_CORRECTION` | `ro.product.manufacturer` must be `MediaTek` (this unit: Hisilicon), so dead |
| `autotestmotor.txt`, `autotestvideo.txt` | starts a factory test activity | `ro.zhiying.model` must be `3S` (this unit: `CQ_5H000_T011`), so dead |
| `new_bootanimation.zip`, `new_bootvideo.mp4` | copied to `/atv/bootvideo/` (or `/data/local/` on MediaTek) | none |
| `EthHWaddr.txt` | reads a MAC into a property | none |
| `screenReplace.txt`, `ZMEnvFile.txt` | reads values into properties (`VIRTUAL_RAM`, `VIRTUAL_ROM`, `reload_vmm`) | model `3S`, dead |
| `zhiying_custom_update.json` | for each item of `type` `file`, copies `<usb>/<vendorRootDir>/<sourcePath>` to `<targetPath>` as uid system | model `3S`, dead on this unit |

The only `Runtime.exec` in the package runs `chmod 666 <path>` on a file it just
copied, and `cat /sys/class/net/*/address`. There is no package install, no
recovery call, no reboot. The JSON copier would be an arbitrary-file-write as
uid system (`targetPath` is not validated), but it is gated on `ro.zhiying.model`
being `3S`, which this unit is not. The live exposure on this hardware is: a
USB stick can replace the boot animation and boot video, and can set
`persist.sys.authenticate`. The update URL `http://www.newlinksz.com/product/update`
lives in `MyServices` alongside `usetime` and `verification` endpoints; the
earlier analysis in [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) covers what is
sent there.

**Decision taken 2026-10-26:** leave both packages enabled. Nothing reachable on
this unit installs, executes or wipes anything. If the boot-animation override
bothers you, the only clean fix is disabling `UsbReceiver` with
`pm disable-user` on that one component, which has no other consumer.

## Not done

Decoding the vdex-only packages (needs `oatdump` on the device, as was done for
wtprovision). Any disable test. Artifacts: `/tmp/vendor-audit/` on the host
(APKs, manifests, dumpsys output, smali trees for hisetting and newlink.service).
