# Vendor telemetry, OTA and the update question

**Summary:** the projector reports to the manufacturer on every boot and every
network change. `com.newlink.service` posts the WiFi MAC, a city derived from a
geo-IP lookup, customer and batch identifiers and a usage counter to
`www.newlinksz.com`, all over plain HTTP. There is no silent OTA path: the only
firmware installer is a user-driven screen in the vendor settings app, and the
vendor's update package returns 404 anyway. Android itself cannot be updated on
this hardware. The safe way to stop the reporting is a DNS or firewall block on
the router, not `pm disable`.

Measured 2026-09-14 on the reference unit (build `eng.hudson.20220706`,
Android 9, security patch 2019-11-05) by reading the live device over adb and
decompiling the vendor APKs on the host. Nothing on the device was changed.

---

## 1. What phones home

### `com.newlink.service`

Privileged system app (`/system/priv-app/NewLinkService`, shared uid
`android.uid.system`), holding `INSTALL_PACKAGES`, `RECOVERY`, `REBOOT`,
`WRITE_SECURE_SETTINGS`, `ACCESS_FINE_LOCATION` and `READ_PHONE_STATE`.

Trigger chain:

1. `BootCompleteReceiver` starts `BootService`.
2. `BootService` waits 60 s, then starts `MyServices`.
3. `NetWorkChangeReceiver` starts `MyServices` again on every connectivity
   change.

`MyServices` builds one JSON object (class `com.newlink.service.Entity`) and
sends it to three endpoints with OkHttp:

| Endpoint | Purpose |
|----------|---------|
| `http://www.newlinksz.com/product/update` | Device activation. The response sets `persist.sys.authenticate=1` and `persist.sys.date`. Despite the name, this is not a firmware update. |
| `http://www.newlinksz.com/product/verification` | Sent when activated. |
| `http://www.newlinksz.com/product/usetime` | Sent when activated. |

Fields in the JSON: `macaddr`, `city`, `project_id`, `cusname`, `batch`,
`systemVersion`, `usetime`, `authenticate`. `city` comes from a separate GET to
`http://whois.pconline.com.cn/ip.jsp`, a Chinese geo-IP service on China
Telecom's network. `https://www.baidu.com` is used only as a connectivity probe.

Confirmed live, not only in code: at audit time `netstat` on the device showed
the `com.newlink.service` process with a connection to `171.105.61.4:80`, one of
the A records of `whois.pconline.com.cn`.

The activation flag can only be set, never cleared: the sole writer in the code
is `Util.setAuthenticate()`, which hardcodes `"1"`. The reference unit was
activated on 2023-09-20 according to `persist.sys.date`.

### Other vendor endpoints

Every vendor APK was checked, including the HiSilicon ones that ship without
`classes.dex` (their code lives in `oat/arm/*.vdex`, which a dex-only scan
misses).

| Package | Endpoint | When it fires |
|---------|----------|---------------|
| `com.zhiying.settings` | `ro.zhiying.server` + `ro.zhiying.update_url`, fallback `http://121.40.159.114` (Alibaba Cloud) | Only when the user opens the system update screen |
| `com.newlink.hisetting` | `http://www.newlinksz.com/app/OurAppUpdateANDIMG` | Only when the user opens the vendor app-store screen |
| `com.newlink.wtprovision` | `http://101.35.187.203/app/OurAppUpdateANDIMG`, `http://cdn.newlink-sz.com/qiniu/appstore/4/ZYLive.apk` | First-run wizard. Already completed (`zysys.wizard.first=false`); no ZYLive package is installed |
| `com.newlink.cast`, `com.newlink.isuperred.ijkplayer` | Apple HLS sample streams | Never; library test constants |
| All HiSilicon apps, `com.zhiying.powerservice`, `com.zhiying.sourceui`, `com.newlink.filemanager`, `com.newlink.nlsource`, `com.newlink.hisilauncher`, `com.example.bluetoothsetting` | none | n/a |

`system_server` connections to Google addresses are the stock connectivity
check and NTP.

## 2. What `com.newlink.service` is for

It is the factory tool that stayed on the shipped device. Besides the reporting
above it contains:

- **Activation gate.** If `persist.sys.authenticate` is not `1` and the network
  is up, `BootService` shows an overlay window and starts `ActivationActivity`,
  which sends the user to WiFi settings. Idle on an activated unit.
- **USB provisioning.** `UsbReceiver` on `MEDIA_MOUNTED` runs
  `UsbIntentService`, which looks for `macReplace.txt`, `nl_sn.txt`,
  `EthHWaddr.txt`, `panel_index.txt`, `screenReplace.txt`,
  `wifiConfiguration.txt`, `ZMEnvFile.txt`, `new_logo.jpg`, `bootvideo.mp4`,
  `bootanimation.zip`, `activate.txt` and `activate_nowindow.txt` in the root
  of the stick and applies them (MAC, serial, panel index, boot branding, WiFi).
- **Factory test screens.** `MacActivity`, `SNActivity`, `FactoryActivity`,
  `MotorRotation`, `VideoActivity` (exported, intent
  `android.newlink.factory_video`), `ToastActivity`, `ZMEnvFileActivity`.
- **Factory-reset hook.** `ClearNotificationReceiver` on
  `MASTER_CLEAR_NOTIFICATION`, gated on `vendor.zy.power.fc.enable`.

Nothing else depends on it. Across all 21 vendor vdex files and the decompiled
APKs the only outside reference is `com.newlink.wtprovision`, and only to
`VideoActivity`. The "hardware interface" label this package used to carry in
`TECHNICAL_NOTES.md` was a guess and is wrong.

Do not disable it anyway. It is a uid-system app on the boot path, which is the
class of change that produced the brick in [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md).
Block the hosts instead (section 5).

## 3. OTA: how it works and why it does not

The manifest URL is built from two build properties:

```
ro.zhiying.server=http://www.newlinksz.com/zyftp/ZYUpdate/default_5hxx/
ro.zhiying.update_url=netupdate/cq_5h000_t011_updateVer.xml
```

On 2026-09-14 that URL still answered. It offers `V1.0.1.4` (the device runs
`V1.0.0.8`), an MD5 and a package URL on `cdn.newlink-sz.com`. Plain HTTP, no
signature beyond the MD5. The package URL itself returns **404**, so the channel
is dead.

The only installer is `com.zhiying.settings`: `SystemUpdateActivity` shows a
dialog, `UpdateService` downloads to `data/cache/update.zip`, checks the MD5 and
calls `RecoverySystem.installPackage`. That app has no boot receiver, no alarm
and no scheduled job. `com.newlink.service` contains no firmware install code.
No `update.zip` or recovery command file exists on the device.

Even a live package would probably not apply here: `RecoverySystem` writes a
command to `misc` and reboots into recovery, and on this unit U-Boot boots the
normal image regardless (see [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md)). Untested,
and it must stay untested: it is a one-shot experiment on the only unit.

## 4. Can Android be updated

No.

| Route | Why not |
|-------|---------|
| Vendor OTA | Package returns 404. Was an Android 9 build anyway. |
| GSI / Treble | `ro.treble.enabled=false`, `ro.vndk.lite=true`, 32-bit ARM. No maintained arm32 GSI exists past Android 10. |
| A/B or `update_engine` | Not present. |
| Recovery flash | Recovery image is real, U-Boot does not boot it. |
| U-Boot USB upgrade | The bootloader has `loader_upgrade` and "USB mandatory upgrade" strings, so a HiSilicon field-flash path exists in principle. There is no firmware to feed it and no console to watch it. |
| Custom ROM | Kernel `4.9.127_s5` has no located GPL source; the display path needs vendor HALs plus per-unit panel calibration partitions. |

Security patch level stays at 2019-11-05. What can be kept current is user
space: the launcher, media apps and whatever else goes into `/system/app`.

## 5. Stopping the reporting

Block these names on the router, or in a DNS resolver the projector uses:

```
www.newlinksz.com
whois.pconline.com.cn
cdn.newlink-sz.com
```

Optional, only if the app-store screens are never wanted: `101.35.187.203` and
`121.40.159.114` (raw IPs in `wtprovision` and `zhiying.settings`).

A blocked lookup makes `MyServices` log an OkHttp failure and give up until the
next trigger. The activation flag is already persisted, so nothing user-visible
changes.

Editing `/system/etc/hosts` works too, but it is a root write to `/system`, so
stage it in `/data/local/tmp`, write with `su 0 sh -c "cat staged > target"` and
confirm with `sha256sum` (the `adb push` trap in [BOOT_BRANDING.md](BOOT_BRANDING.md)
applies to `/system` as well). The router is the simpler and reversible choice.

## 6. Reproducing the audit

Read-only. Replace the address with the projector's.

```sh
D="192.168.50.229:5555"
adb -s $D shell getprop | grep -e zhiying -e persist.sys.authenticate -e persist.sys.date
adb -s $D shell "su 0 sh -c 'netstat -tunpW'"
adb -s $D shell dumpsys package com.newlink.service | grep -e INSTALL_PACKAGES -e RECOVERY -e REBOOT
adb -s $D pull /system/priv-app/NewLinkService/NewLinkService.apk .
apktool d NewLinkService.apk
rg -n 'http://' NewLinkService/smali --glob '*.smali'
curl -sI "http://cdn.newlink-sz.com/qiniu/ZYUpdate/5HXXX/5H000/CQ_5H000_T011/update.zip"
```

Traps met on the way, so nobody repeats them:

- HiSilicon APKs have no `classes.dex`; scan `oat/arm/*.vdex` with `strings`.
- The device logcat buffer covers only a few minutes, so "nothing in the log"
  is not evidence about a boot-time service.
- `dumpsys netstats` reports no per-uid rows on this build.
