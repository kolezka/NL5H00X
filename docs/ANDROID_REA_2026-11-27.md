# Android 9 on the NL5H00X: 2026-11-27 observations

Scope: HOME dispatch, boot-related declarations and running processes, Newlink and HiSilicon application manifests, build and partition layout on one modified NL5H00X_TP. This is not a boot trace, raw flash dump or review of every executable. REA inspected shipped artifacts offline. ADB supplied the artifacts, package resolver results and post-boot snapshot; no activity was started and no reboot was performed.

## Two HOME decisions

1. **System to dispatcher (REA manifest + ADB resolver).** `com.newlink.wtprovision/.MainActivity` declares `MAIN` with `HOME`, `SETUP_WIZARD`, `MONKEY` and `DEFAULT` in one filter (priority 29). All categories in the incoming intent must match. `MAIN + HOME` returned WTProvision, RGTPLauncher, Nova, Projectivy and FallbackHome. Adding `SETUP_WIZARD` left only WTProvision; priority did not distinguish competing matches in that query.
2. **Dispatcher to launcher (REA method bodies).** On the normal HOME path `MainActivity.doSelectSourceId(-1)` calls `startActivity` with an explicit `ComponentName(home_pkg, home_activity)`. If the pair is missing, `getLauncherHomeActivity()` queries `MAIN + HOME` without `SETUP_WIZARD`, skips package names containing `wtprovision` or `com.android.tv.settings`, and takes the first remaining result. The stock launcher is a possible target, not a hard-coded destination. Factory video and source 10010 have separate branches; neither proves a HOME launch.
3. **Inside the stock launcher (REA method body).** If the pair names `com.newlink.hisilauncher/.WizardAciticity` (spelling in the APK), its `onCreate` reads `zysys.rgtp.launcher`. Values 1, 2 and 3 select `MainActivityNew`, `MainActivitySecond` and `MainActivityThird`; the default selects `MainActivity`. It starts the selected activity and finishes itself.

WTProvision and hisilauncher processes were present after boot. The sampled 4000 log entries did not identify a HOME handoff. Neither process presence nor resolver order establishes the pair used at the last boot.

## Artifact provenance

The shipped WTProvision APK (SHA-256 `0260af1f4824d4e1744d99c1e951543ab73a6afd72087a5ea6facd4512b0a430`) supplied the manifest, not the activity bodies. Its companion ARM VDEX 019 (`8ef44fe7f339c381bb029dfda307f9a065be8a4b7d64ae3f8b09757601c8e336`) supplied CompactDex. `vdexExtractor` and `compact-to-dex` produced standard DEX 039 with 6308 class definitions. REA inspected the derived APK (`8c2c5f0d3631b5d225c268b1d8111e6156756d342477753bd802cf0e72b50a4f`); it was not installed. RGTPLauncher was inspected directly (`83396f9340839143c89a662e0cebd9558b5a585e26a7b6f5dc7f4096547d3a4b`).

| REA observation | Evidence ID |
|---|---|
| WTProvision manifest filter | `[redacted]` |
| `getLauncherHomeActivity` | `[redacted]` |
| `doSelectSourceId` | `[redacted]` |
| `WizardAciticity.onCreate` | `[redacted]` |

## Vendor packages and boot

The [component inventory](vendor-manifests-2026-11-27.csv) contains 152 REA declaration rows for the 19 installed packages in the `com.newlink.*` and `com.hisilicon.*` namespaces. Eighteen manifests had complete declaration coverage; HiTvService returned four declarations with partial coverage. An empty `exported` field means no explicit value was recorded, not `false`. Declarations are not delivery records.

NewLinkService and HiTvSetting declare `BOOT_COMPLETED` receivers. The latter declares `com.hisilicon.permission.COMMON_PERMISSION`. The HDMI, YPbPr, CVBS and VGA TV input services declare `BIND_TV_INPUT`. ADB showed zygote, system_server, surfaceflinger, both HOME packages, com.newlink.service, com.hisilicon.tv.service and com.hisilicon.rmservice running; bootanim was stopped. This snapshot does not order their startup.

## Build and storage (ADB)

Android 9 (API 28), `PPR1.180610.011`, incremental `eng.hudson.20220706.192233`, `userdebug/dev-keys`. The root and vendor filesystems were mounted read-only as ext4. By-name links mapped recovery to p5, logo to p8, boot to p9, misc to p15, system to p20, vendor to p21, cache to p24 and userdata to p25. Reported filesystem capacities and use: `/` 1.7 G (88%), `/vendor` 291 M (16%), `/data` 4.4 G (38%), `/cache` 93 M (1%). These are filesystem measurements, not raw partition sizes.

## Board identity and Android startup configuration

The running device tree reports model `Hi3751` and compatible `hisilicon,hi3751`; `/proc/cpuinfo` reports hardware `hi3751`. Android uses the board name `bigfish` for `ro.board.platform`, `ro.hardware` and `ro.boot.hardware`. These are complementary identifiers, not different devices. The kernel showed CPUs `0-3` online, each reporting implementer `0x41` and part `0xd03` (Arm Cortex-A53). That core identity does not imply a 64-bit Android build: the running kernel reports `armv7l` and Android selects `zygote32`. These software observations do not identify a finer chip stepping or package marking.

The main MMC user block device reports type `MMC`, product name `UEM`, and 14,942,208 Linux 512-byte sectors: 7,650,410,496 bytes (7.125 GiB). This is the capacity exposed by `mmcblk0`, not free space, the size of userdata, or a physical NAND inventory.

On-device init configuration connects these identifiers to startup. `/init.rc` imports `/init.${ro.hardware}.rc`, `/vendor/etc/init/hw/init.${ro.hardware}.rc` and `/init.${ro.zygote}.rc`. Both resolved `bigfish` files exist. The resolved `/init.zygote32.rc` declares `zygote` as `/system/bin/app_process -Xzygote /system/bin --zygote --start-system-server`. In the post-boot snapshot init reported zygote running and Android reported `sys.boot_completed=1`. This identifies the configured path into the Android framework, not a replay of every init action or proof that every service was ready.

## Board services and radio drivers

The root `bigfish` init configuration requests `bootvideo` at `init`. At `post-fs` it requests `hwsysmanager-1-0`, `vendor.hiavplayer`, `hwandroidmediahal-2-0`, `hwtvmw-1-0` and `hidl_memory`. All five reported `running` after boot. `bootvideo` reported `stopped`; that state does not show whether a boot video played. The vendor configuration mounts the board fstab at `fs` and requests `vendor.ir_user` and `vendor.virtualkeypad` at `boot`. Both reported `running`. This ties two input services to board startup, not a particular remote button to either service.

The vendor boot action lists several alternative Bluetooth modules; the file alone does not identify the fitted radio. In the running kernel, `wlan0` and `p2p0` both point to the same USB parent, with vendor/product ID `a69c:8801`. Two interfaces on that device bind to `aic_btusb` and the third binds to `aic8800_fdrv`. This identifies the stock composite radio's driver pair without scanning or pairing. It does not identify the exact silicon revision or verify radio performance. `eth0`, by contrast, points to the `hieth` platform driver.

## Device-wide coverage and open questions

| Subsystem | Evidence from this unit | What it does not establish |
|---|---|---|
| Kernel, CPU and memory | ADB: `uname` reported Linux `4.9.127_s5`, `armv7l`; sysfs reported CPUs `0-3` present. `/proc/meminfo` reported `MemTotal: 1005264 kB` (about 982 MiB). | CPUs present are not CPUs online. Kernel-visible memory is not installed DRAM capacity. Driver inventory and board-specific bindings remain to be mapped. |
| Storage and boot | ADB: partition links and mount sizes above; zygote running after boot. REA: HOME selection paths and boot receiver declarations above. | Neither a boot chronology nor a tested recovery route. |
| Panel and graphics | ADB: SurfaceFlinger identified Mali-450 MP; the device manifest declares composer 2.1. See the [display and remote report](AOSP_PORT_2026-11-27.md). | Neither the panel timing path nor output on a replacement OS has been verified. |
| Audio | ADB: `audioserver` running. ALSA lists card 0 `HISI-AIAO` and PCM `00-00` `playback aiao-hifi-0`, with one playback substream. | Does not identify which Android output routes use that PCM, or verify audible sound. |
| Remote | ADB: input manager associated `Hi Keypad` and `Hi keyboard` with stock key layouts. | No physical keypress traced through the driver to an Android action. |
| Network | ADB: sysfs listed `eth0`, `lo`, `p2p0` and `wlan0`; init reported `wificond` running. | Interface names do not show the physical chipset, active carrier or Wi-Fi association. No scan was performed. |
| Vendor services | REA: manifest inventory above; ADB: named post-boot processes. | Does not map every service to its driver or establish which code ran at boot. |

## Android audio policy and input endpoints

The vendor audio policy includes a primary HAL 2.0 module. It declares `Speaker` as the default output and routes `primary output` (48 kHz, stereo, 16-bit PCM) to that sink. The live `media.audio_policy` dump also lists the primary module, `Sink: Speaker` and `AUDIO_DEVICE_OUT_SPEAKER`. This confirms Android's logical route, not the connection from the HAL to ALSA or the amplifier. Both `audio.primary.bigfish.so` and `audio.primary.default.so` are present under `/vendor/lib/hw`; filenames do not identify which one was loaded. No playback or capture test was performed.

The four input event nodes in this snapshot were `Hi keyboard`, `Hi mouse`, `qwerty` and `Hi Keypad`. All resolve under `/sys/devices/virtual/input`, not to a physical receiver bus. Android can map the virtual key devices to layouts, but these sysfs paths alone do not identify the event producer. A useful next static check is how the stock IR service translates a received code into an input event.
