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

In the live user 0 snapshot, PackageManager listed 78 distinct packages. Its system filter returned 76 and its non-system filter returned two; the sets were disjoint and their union matched the unfiltered list. Exactly 19 of the 78 names had the Newlink or HiSilicon prefixes used for the REA inventory below. Package counts include framework and service packages, not just launchable apps. The non-system package names were not published. The namespace filter describes audit coverage, not authorship of every package in the image.

Grouping the active APK paths of those 76 system packages gave 42 in `/system/app`, 27 in `/system/priv-app`, one in `/system/framework`, four in `/vendor/overlay`, one in `/vendor/app` and one in `/data/app`. The last package's record carried both `SYSTEM` and `UPDATED_SYSTEM_APP`: Android still classifies it as system software while using its updated copy from writable storage. For firmware comparisons, distinguish the APK currently in use from the copy shipped in the read-only image. Directory counts alone do not establish effective permission grants or which overlays are active.

For user 0, OverlayManager matched all four vendor overlay APK paths. The three display-cutout emulation overlays (corner, double and tall) target `android` and each had `STATE_DISABLED`. The dark theme overlay targets `com.android.systemui` and had `STATE_MISSING_TARGET`. All four had `mIsEnabled: false`. None of these four overlays was applying resources in that snapshot. The dark theme state describes target resolution by OverlayManager, not how the launcher draws its own theme.

The [component inventory](vendor-manifests-2026-11-27.csv) contains 152 REA declaration rows for the 19 installed packages in the `com.newlink.*` and `com.hisilicon.*` namespaces. Eighteen manifests had complete declaration coverage; HiTvService returned four declarations with partial coverage. An empty `exported` field means no explicit value was recorded, not `false`. Declarations are not delivery records.

NewLinkService and HiTvSetting declare `BOOT_COMPLETED` receivers. The latter declares `com.hisilicon.permission.COMMON_PERMISSION`. The HDMI, YPbPr, CVBS and VGA TV input services declare `BIND_TV_INPUT`. ADB showed zygote, system_server, surfaceflinger, both HOME packages, com.newlink.service, com.hisilicon.tv.service and com.hisilicon.rmservice running; bootanim was stopped. This snapshot does not order their startup.

## Build and storage (ADB)

Android 9 (API 28), `PPR1.180610.011`, incremental `eng.hudson.20220706.192233`, `userdebug/dev-keys`. The root and vendor filesystems were mounted read-only as ext4. By-name links mapped recovery to p5, logo to p8, boot to p9, misc to p15, system to p20, vendor to p21, cache to p24 and userdata to p25. Reported filesystem capacities and use: `/` 1.7 G (88%), `/vendor` 291 M (16%), `/data` 4.4 G (38%), `/cache` 93 M (1%). These are filesystem measurements, not raw partition sizes.

Android's volume daemon (`vold`) was running, and StorageManager reported both `private` and `emulated` volumes mounted. In the ADB shell mount namespace the userdata block device backs ext4 at `/data`; `sdcardfs` exposes `/data/media` at `/storage/emulated`. The `/sdcard` alias points to `/storage/self/primary`, which in turn points to `/mnt/user/0/primary`. The emulated shared-storage view therefore consumes space on userdata, not a second disk: do not add its reported capacity to `/data`. This describes the active internal storage arrangement, not support for removable media. No user files were enumerated.

The board init file invokes `mount_all /vendor/etc/fstab.${ro.hardware}`. In the resolved `fstab.bigfish`, the `/data` entry requests `wait,check,quota,reservedsize=104857600` (100 MiB reserved); `/cache` requests `wait`. The live mount table confirms both are writable ext4 using `data=ordered`. The 100 MiB figure is a configuration request, not a measurement of current free space. Mount flags alone do not establish that a filesystem check ran at the last boot or that a quota was enforced for a particular app.

## Board identity and Android startup configuration

The running device tree reports model `Hi3751` and compatible `hisilicon,hi3751`; `/proc/cpuinfo` reports hardware `hi3751`. Android uses the board name `bigfish` for `ro.board.platform`, `ro.hardware` and `ro.boot.hardware`. These are complementary identifiers, not different devices. The kernel showed CPUs `0-3` online, each reporting implementer `0x41` and part `0xd03` (Arm Cortex-A53). That core identity does not imply a 64-bit Android build: the running kernel reports `armv7l` and Android selects `zygote32`. These software observations do not identify a finer chip stepping or package marking.

The main MMC user block device reports type `MMC`, product name `UEM`, and 14,942,208 Linux 512-byte sectors: 7,650,410,496 bytes (7.125 GiB). This is the capacity exposed by `mmcblk0`, not free space, the size of userdata, or a physical NAND inventory.

On-device init configuration connects these identifiers to startup. `/init.rc` imports `/init.${ro.hardware}.rc`, `/vendor/etc/init/hw/init.${ro.hardware}.rc` and `/init.${ro.zygote}.rc`. Both resolved `bigfish` files exist. The resolved `/init.zygote32.rc` declares `zygote` as `/system/bin/app_process -Xzygote /system/bin --zygote --start-system-server`. In the post-boot snapshot init reported zygote running and Android reported `sys.boot_completed=1`. This identifies the configured path into the Android framework, not a replay of every init action or proof that every service was ready.

## Application compatibility and vendor Java APIs

The stock app ABI list is `armeabi-v7a,armeabi`, the 64-bit list is empty, and `/system/bin/app_process` resolves to `app_process32`. An app that requires an `arm64-v8a`-only native library has no matching stock app ABI. This restriction concerns native code, not ordinary DEX bytecode; an ABI match alone does not guarantee installability or correct behavior.

PackageManager lists three HiSilicon Java libraries. The stock XML under `/system/etc/permissions` maps `com.hisilicon.android` to `HitvManager.jar`, `com.hisilicon.android.tvapi` to `HitvShare.jar`, and `com.hisilicon.dtv` to `HiDtvShare.jar`, all under `/system/framework`. These library names are framework dependencies that vendor apps can request, not Android application package names. Registration alone does not prove which app uses a given API.

For a concrete consumer, the live package record for `com.newlink.wtprovision` lists `com.hisilicon.android.tvapi` under `usesOptionalLibraries` and `/system/framework/HitvShare.jar` under `usesLibraryFiles`. Stock Android thus resolves the optional library for the provisioning app. This does not prove that any one of its methods called the API during boot or that all features work without it.

REA's complete decoded manifest for the stock external TV input APK shows a different contract: minimum and target API 28, Leanback and Live TV required, touchscreen optional. Its HDMI, YPbPr, CVBS and VGA services advertise the Android `TvInputService` action. The requirements describe the software environment expected by this APK, not a physical inventory of inputs.

## Embedded web content

PackageManager advertises `android.software.webview`. Android's WebView Update Service identified `com.android.webview` version `66.0.3359.158` as both current and preferred, installed and enabled for all users in the snapshot. It reported multiprocess mode disabled. For an app embedding a standard Android WebView, this provider version is a more precise compatibility baseline than Android API 28 alone. It does not identify a standalone browser, an app's bundled engine or the most recent available update. No page was loaded and no rendering or update test was performed.

## Board services and radio drivers

The root `bigfish` init configuration requests `bootvideo` at `init`. At `post-fs` it requests `hwsysmanager-1-0`, `vendor.hiavplayer`, `hwandroidmediahal-2-0`, `hwtvmw-1-0` and `hidl_memory`. All five reported `running` after boot. `bootvideo` reported `stopped`; that state does not show whether a boot video played. The vendor configuration mounts the board fstab at `fs` and requests `vendor.ir_user` and `vendor.virtualkeypad` at `boot`. Both reported `running`. This ties two input services to board startup, not a particular remote button to either service.

The vendor boot action lists several alternative Bluetooth modules; the file alone does not identify the fitted radio. In the running kernel, `wlan0` and `p2p0` both point to the same USB parent, with vendor/product ID `a69c:8801`. Two interfaces on that device bind to `aic_btusb` and the third binds to `aic8800_fdrv`. This identifies the stock composite radio's driver pair without scanning or pairing. It does not identify the exact silicon revision or verify radio performance. `eth0`, by contrast, points to the `hieth` platform driver.

Above the kernel driver, PackageManager advertises Bluetooth and Bluetooth LE. The Android Bluetooth manager reported the adapter enabled and `ON` in this snapshot. The vendor A2DP audio policy declares output routes for Bluetooth headphones and speakers, plus an input route. These are logical Android audio paths, not evidence of a connected accessory, an active stream, or a working end-to-end receiver mode. No discovery or pairing was requested.

## Display mode, UI density and framebuffer

Android's DisplayManager reported the built-in display ON, with one advertised mode: 1920 by 1080 at approximately 60 Hz. WindowManager independently reported a base size of 1920 by 1080 and a density override of 320 dpi over a base of 240 dpi. The override changes the scale used for Android layouts, not the pixel dimensions of the display mode. Neither density value measures the projected image on a wall.

Kernel sysfs identified `fb0` as `hifb`, with a virtual size of 1920 by 3240 at 32 bits per pixel. The virtual height is three 1080-line spans; that is framebuffer geometry, not a 3240-line display or proof of how many buffers the compositor actually presents. These readings establish what stock Android and the framebuffer driver expose. They do not independently measure panel-native resolution, optical output or physical refresh timing.

## Wireless display application

Stock Android exposes Miracast as a HiSilicon system app. REA decoded its original manifest: `WelcomeActivity` declares `MAIN` with both `LAUNCHER` and `LEANBACK_LAUNCHER`, and the same package declares `WfdService`. On the projector, a package-scoped Leanback intent query resolved to `com.hisilicon.miracast/.activity.WelcomeActivity`; it did not launch it. PackageManager also advertises Wi-Fi Direct. These observations confirm the installed TV launcher entry and declared service, not a running wireless display session, protocol interoperability or stream quality. No peer discovery or pairing was performed.

## Android media decoding

The post-boot HAL inventory lists the default `IOmx` and `IOmxStore` instances of `android.hardware.media.omx@1.0`. The vendor codec XML, parsed as XML to exclude commented examples, declares HiSilicon AVC, HEVC and VP9 decoder components with a maximum size of 1920 by 1088; the MPEG-2, MPEG-4 and VP8 entries specify 1920 by 1080. The limits describe decoder inputs, not display modes. The same file includes separate Google audio and video codec lists, so its direct entries alone are not an inventory of all codecs available to apps. A registered OMX service plus a declared codec does not prove a player selected it or sustained a particular resolution, profile or frame rate. No media was played.

## TV framework personality and input inventory

PackageManager advertises `android.hardware.type.television`, `android.software.leanback`, `android.software.leanback_only` and `android.software.live_tv`. The running UI mode was `0x14`, whose type field is television. Apps therefore see a television-oriented Android configuration; these flags do not establish commercial Android TV certification or a broadcast tuner.

The live TV Input Manager mapped logical inputs to the vendor's CVBS, VGA and HDMI services (one CVBS identifier, one VGA identifier and three HDMI identifiers). Its service-state list also included the YPbPr service. A service entry, a logical input identifier and a physical socket are different things: none proves a connector is fitted or receiving video. No input was selected during this read.

## Android memory policy

The stock build sets `ro.config.low_ram=true`. Its ART properties specify a 5 MiB starting heap, a 128 MiB growth limit and a 256 MiB heap size. These are managed-heap settings, not limits on a process's total resident memory. Init reported the low-memory killer daemon (`lmkd`) running; that alone does not show it killed any process.

The kernel reported 1,005,264 KiB of usable RAM and 319,088 KiB of swap. `/proc/swaps` identified the active backend as `/dev/block/zram0`; sysfs identified LZ4 as the selected compression algorithm. This provides about 312 MiB of logical swap backed by compressed RAM, not additional physical RAM or evidence of paging to flash. No memory pressure was induced.

## CPU frequency policy and power telemetry

On the running stock kernel, `policy0` lists CPUs 0 through 3 as affected by the same frequency policy. Its `hi3751-cpufreq` driver advertises 800,000 and 1,000,000 kHz (800 MHz and 1 GHz), with the `interactive` governor selected. These are available operating points, not a measurement of the instantaneous clock, sustained performance or the silicon's rated maximum.

Android BatteryService reported `present: false` alongside `level: 42` and `voltage: 0`. The level is therefore not evidence of a battery charged to 42 percent. Its temperature field does not identify a SoC or lamp sensor. This read did not establish a physical temperature, power draw or fan speed.

## Sensors exposed to Android apps

The framework `sensorservice` was registered, but its diagnostic dump reported `No Sensors on the device` and `devInitCheck : -19`. PackageManager's feature list also returned no `android.hardware.sensor.*` entry; the same read returned the expected television feature. At the time of the snapshot the standard Android sensor service therefore offered no sensor inventory. This does not establish why initialization returned that status, or rule out sensors wired to a board controller, exposed through a vendor API, or used internally for protection.

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

## Android text input

ADB reported `com.hisilicon.android.inputmethod.remote/.RemoteIME` both as the selected default input method and in the enabled IME list. REA confirmed the matching service in the stock HiPinyinIME manifest: it advertises `android.view.InputMethod` and requires `BIND_INPUT_METHOD`. The APK separately declares `PinyinDecoderService`. This identifies the vendor component Android selects for text fields, not the driver that receives physical remote buttons. No keyboard was opened and no input text was read or entered.

## Android audio policy and input endpoints

The vendor audio policy includes a primary HAL 2.0 module. It declares `Speaker` as the default output and routes `primary output` (48 kHz, stereo, 16-bit PCM) to that sink. The live `media.audio_policy` dump also lists the primary module, `Sink: Speaker` and `AUDIO_DEVICE_OUT_SPEAKER`. This confirms Android's logical route, not the connection from the HAL to ALSA or the amplifier. Both `audio.primary.bigfish.so` and `audio.primary.default.so` are present under `/vendor/lib/hw`; filenames do not identify which one was loaded. No playback or capture test was performed.

The four input event nodes in this snapshot were `Hi keyboard`, `Hi mouse`, `qwerty` and `Hi Keypad`. All resolve under `/sys/devices/virtual/input`, not to a physical receiver bus. Android can map the virtual key devices to layouts, but these sysfs paths alone do not identify the event producer. The vendor init configuration starts `android_ir_user` (not the similarly named `ir_user`) and `virtualkeypad`; both executables appeared in the post-boot process list. Offline REA ELF inspection of device-checksummed copies found that both depend on `libhi_msp.so`, but `android_ir_user` specifically imports `HI_UNF_IR_GetValueWithProtocol`, `HI_UNF_IR_GetSymbol`, and controls for key-up and repeat handling. A separate byte-string inspection found `/dev/vinput` in `android_ir_user` and `/dev/uinput` in `virtualkeypad`. This distinguishes the IR reader candidate from the second input service; the two path literals do not prove that either node was opened, that one service calls the other, or which virtual event node carries a particular button.
