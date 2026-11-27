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

The framework reports security patch level `2019-11-05` (`ro.build.version.security_patch`). This is the build's declared Android patch level, not its build date or a verification of individual backports. A separate query for `ro.vendor.build.security_patch` returned an empty value, so that property does not establish the vendor patch level. Likewise `ro.vndk.version=28` identifies a native interface version, not proof of Treble support: this build explicitly sets `ro.treble.enabled=false`.

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

## Android USB roles

PackageManager advertises `android.hardware.usb.host`, and the kernel root hub product strings identify EHCI and OHCI host controllers. The composite radio above is an observed USB host device. Separately, both Android gadget properties `sys.usb.config` and `sys.usb.state` read `adb`. This snapshot was obtained over TCP ADB, not a USB cable: the properties do not verify that any external connector can expose USB ADB. Controller count is not connector count. No peripheral was plugged in, detached or reconfigured.

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

In a passive post-boot snapshot, Android's DeviceIdleController reported both light and deep Doze disabled, with both state machines `ACTIVE`. PowerManager reported `Awake`, `mIsPowered=true` and `mStayOn=true`. Doze concerns framework idle restrictions on apps; it is not the same as switching off the projector or suspending the board. No standby or wake transition was tested, so these readings do not establish behavior after the remote power button is pressed.

The earlier [technical notes](TECHNICAL_NOTES.md#services-and-home-screen) identify `com.zhiying.powerservice` as a power-management package outside the two namespaces in the manifest inventory. PackageManager confirmed version 1.0 installed for user 0 at `/system/app/PowerService/PowerService.apk`. ActivityManager's package-scoped service dump returned `(nothing)` while the same query for the external TV input package returned a live service record. This distinguishes an installed package from a currently tracked Android service; it does not exclude on-demand handling or identify the owner of the physical power button.

REA decoded all three manifest component declarations in the stock power APK (SHA-256 `f72fb519ef29ff04b07796002ae6f9b7a905cbb3d55a91d366ed906ce109ad20`, matched on the device and analysis host). All are activities: `PowerActivity` and `KJMPowerActivity` declare `android.intent.action.MAIN`; `ListenActivity` declares `MAIN`, `android.intent.action.VIEW` and `zhiying.powerservice.close`. Despite the package name, this manifest declares no Android service or broadcast receiver. The custom action names an activity entry point, not a verified shutdown command. Neither its caller nor its effect on projector hardware follows from the manifest.

REA's complete decompilation of `ListenActivity.onCreate(Bundle)` shows no branch on the incoming intent action. It displays `R.layout.dialog_my` and attaches a click listener to `R.id.dialog_bt`. Only in that callback does it call `TvPictureManager.getInstance().execAdvancedPictureSetting(31, 0)` and then `finish()` on the activity. Opening the activity and activating its button are separate events. The code establishes which screen closes, not what the vendor picture command does to the hardware or who sends the `close` intent. Neither event was triggered during the audit.

`PowerActivity` follows a different path. Its `onCreate(Bundle)` displays `R.layout.power` and calls `findView()` and `registerListener()`. The latter attaches a click listener to `mOkButton`. A click starts a worker thread that attempts to send an Android power-key press and release (key code 26) via `Instrumentation`; the callback catches `Exception` without reporting it. This is an outgoing synthetic key event, not evidence that this activity receives the remote's physical power key. Neither event delivery nor the board's response was tested.

`KJMPowerActivity` displays `R.layout.kjm_power` and schedules handler message 0 with a 5,000 ms delay. Its `handleMessage` callback handles that message by calling `finish()` on the activity. `onDestroy()` clears pending messages and callbacks. The timer therefore dismisses the screen; it is not a five-second hardware shutdown request. This static path does not identify which component opens the screen or whether the board enters standby by a separate route.

Android InputReader reported `/vendor/usr/keylayout/Vendor_046d_Product_0002.kl` as a selected layout. It maps Linux key code 116 to Android `POWER` and 172 to `HOME`. In the same read-only session, `dumpsys window policy` reported `SHORT_PRESS_POWER_GO_TO_SLEEP` and `LONG_PRESS_POWER_SHUT_OFF_NO_CONFIRM`; the very-long, double and triple press settings were `NOTHING`. These are the framework's configured actions if a power event reaches that policy. They do not establish that the physical remote emits code 116, that the vendor leaves the event unconsumed, or that Android sleep removes power from the light source. No key was pressed or injected.

The `com.newlink.hotkeys.service` manifest action points to WTProvision's `MyUtilsService`. REA shows that its `onKey(View, int, KeyEvent)` callback handles focus: without a source string, 136/3002 and 137/3003 dispatch focus up and down; in the start-focus mode, right/left (22/21) do so instead. There is no branch for Android `POWER` (26) in this method. An unmatched key can dismiss the motor view and the callback returns true on the fallback path. That matters only if the event reaches this view; it does not identify the global power-key receiver or prove that the remote event is swallowed.

HiTvSetting declares a separate broadcast receiver, `com.hisilicon.tvsetting.main.SettingHotKeyReceiver`, for `com.android.hisilicon.SendHotKey`, with sender permission `com.hisilicon.permission.COMMON_PERMISSION` (REA manifest). A literal search for the full action in UTF-8 and UTF-16LE across the 19 saved vendor APK manifests and their seven root DEX entries matched the HiTvSetting manifest only. This does not identify a sender: the search excludes preoptimized code outside the APKs, native libraries and framework code, and cannot detect a constructed action string. HiTvSetting itself has no root DEX entry. Neither the broadcast payload nor a connection to physical `POWER` has been established.

## Focus motor request versus on-screen feedback

In WTProvision, `MyUtilsService.dispatchFocusUp` checks for key-down and a reported motor position other than 2. It then calls `TvCustomSetting.setMotorForward(1)` for the initial press or passes 2 for a repeat. It ignores the integer return value and calls `onForward()` to animate the view. On release or at position 2 it calls `onBrake()`, whose decoded body cancels the animation and clears the direction flag if set. This method contains no direct motor-stop request. `TvCustomSetting.setMotorForward(int)` is abstract at that declaration. The on-screen animation is therefore not a measurement of lens movement; it shows what the app requested, not what the optics did.

The app chooses its implementation once during `TvCustomSetting` class initialization. It reads `ro.product.manufacturer` (default empty string) and checks whether the string contains the case-sensitive substring `MediaTek`. `newInstance()` constructs `MtkTvCustomSetting` on a match and `HiTvCustomSetting` otherwise. `MyUtilsService.onCreate()` obtains that stored instance. In the HiSilicon branch, `HiTvCustomSetting.setMotorForward(int)` forwards the argument to `AdvancedPictureSetting.setMotorForward(int)`. In the stock HitvShare bytecode that method returns `mCusEx.setAdvancedPictureSetting(66, argument)`. This identifies the software operation for forward focus, not its units, hardware implementation or result. Source: offline REA inspection of WTProvision and HitvShare; the live manufacturer property and motor operation were not tested in this step.

The reverse path uses the same setting ID, not a second one. `dispatchFocusDown` skips the backward request on key release or when the reported position is 0. Otherwise it passes 1 for the initial press or 2 for a repeat. `HiTvCustomSetting` delegates unchanged, and HitvShare negates the argument before calling `setAdvancedPictureSetting(66, -i)`. The position getter delegates to `getAdvancedPictureSetting(66)`. The sign therefore distinguishes the two requested directions on write; on read, WTProvision treats 0 and 2 as directional limits. Nothing in these methods establishes how the position is measured or whether a physical limit switch exists.

## Sensors exposed to Android apps

The framework `sensorservice` was registered, but its diagnostic dump reported `No Sensors on the device` and `devInitCheck : -19`. PackageManager's feature list also returned no `android.hardware.sensor.*` entry; the same read returned the expected television feature. At the time of the snapshot the standard Android sensor service therefore offered no sensor inventory. This does not establish why initialization returned that status, or rule out sensors wired to a board controller, exposed through a vendor API, or used internally for protection.

WTProvision has a separate vendor event path. In the HiSilicon implementation, `setAccelerometerListener` passes `TVMessage.NL_TV_EVT_EX_ACCELEROMETER` to `setSensorsListener`. That helper replaces the listener for the event ID on `HitvManager`, not Android's `SensorManager`. Its adapter forwards four integers unchanged for each accelerometer, gyroscope, orientation-stable or orientation-change callback. REA establishes the subscription code, not that the board produces any of these events. In the stock HitvShare framework, `OnSensorsListener.notifyMessage` rewinds a non-null `Parcel` and routes event ID 655362 to `notifyAccelerometerMessage`. That decoder reads five integers: if the first is 2 it forwards the remaining four to `onAccelerometerTrigger` in order; otherwise it logs an unsupported action and does not call that callback. The decoder establishes the message format, not the meaning of each value. No sample was captured; the units and physical sensor remain unknown.

`TempService.startSensorsListener()` connects these events to autofocus and keystone correction. REA found two direct calls to `setAccelerometerListener` in that method (DEX code-unit offsets 93 and 209). The first registration branch requires `vendor.newlink.camera_exist=1`; the fallback requires `vendor.newlink.3d_auto.camera_exist=1`. Each registers the same listener for accelerometer, gyroscope and orientation events. With `6dsensor`, autofocus enabled and `mStartFocus` set, the accelerometer callback replaces a pending `autoFocusRunnable` with one delayed by 500 ms. With `3dsensor` and 3D autofocus enabled, the orientation-change callback records roll and pitch and schedules `autoKeystone_3d_Runnable` if `mSensorStatus` is zero. These are separate branches: the accelerometer callback does not itself demonstrate an image correction. The property values, callback delivery and optical result were not measured in this trace.

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
