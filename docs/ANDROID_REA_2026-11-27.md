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
