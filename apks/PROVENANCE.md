Where the APKs in this directory came from, and what was checked before they
were trusted enough to install as a system launcher.

Last updated: 2026-09-20

## projectivy-launcher-4.71.apk

The launcher the unlock installs by default.

| | |
|---|---|
| Source | `https://github.com/spocky/miproja1/releases/download/4.71/ProjectivyLauncher-4.71-c95-xda-release.apk` |
| Retrieved | 2026-07-29 |
| SHA-256 (file) | `6818fc2db44411a605ca4d7067fb9d7227aaef2414cff42de58fe13e9321b47a` |
| Package | `com.spocky.projengmenu` |
| versionCode / name | `95` / `4.71` |
| minSdk / targetSdk | `23` / `37` |
| ABIs | `arm64-v8a`, `armeabi-v7a`, `x86` |
| Home activity | `com.spocky.projengmenu.ui.home.MainActivity` |
| Signers | 1 |
| Signer DN | `CN=Despesse Mickael, O=Unknown, L=Villeurbanne, C=FR` |
| Signer SHA-256 | `f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd` |
| Signature schemes | v1 JAR: yes, v2: yes, v3: no |

Checked with `apkanalyzer` and `apksigner` from Android build-tools 36.1.0.

Why this build and not the newest on APKMirror: the 4.71 packages there are
Android App Bundles, which `adb install` cannot take (they need
`install-multiple`), and the only armeabi-v7a bundle variant is marked Android
12L+. `miproja1` is the developer's own repository -- its README describes it
as the update channel for installs that did not come from Google Play -- and it
publishes a plain universal APK. That is both a better supply chain and the
only form this toolkit can install in one step.

Relevant to this device: the projector is `armeabi-v7a` on API 28, so minSdk 23
and the presence of an `armeabi-v7a` slice are the two things that had to hold.

**What this verification does and does not prove.** The APK is internally
consistent and signed by a single certificate, and it came over HTTPS from the
developer's own GitHub releases. There is no independent reference copy of
Spocky's Play Store signing key to compare against, so this does not *prove*
the key is the same one Google Play ships. If you already have Projectivy
installed from Play, keep it -- the unlock treats an existing install as done
and will not replace it. A signing-key mismatch would in any case make an
in-place upgrade fail loudly rather than silently.

## nova-launcher-7.0.57.apk

Kept, not used by default. Nova was the original target before the switch to
Projectivy, and it is still installed in `/system/app` on the reference device
from an attempt made in July 2025.

It remains here as a fallback, reachable without editing any code:

```bash
LAUNCHER_PKG=com.teslacoilsw.launcher \
LAUNCHER_NAME=Nova \
LAUNCHER_APK_GLOB='nova-launcher*.apk' \
  ./scripts/UNLOCK.sh --apply-all
```

Nova is a phone launcher and expects touch; on a projector driven by a remote
it is usable but awkward, which is why it is no longer the default.

## Bundled apps (added 2026-09-14)

Seven apps the owner asked for, staged into `/system/app` on the reference
device with `scripts/INSTALL_APP.sh` the same day. All are open source, all
carry an `armeabi-v7a` slice or no native code, all have minSdk 24 or lower
(the device is API 28), and each verified with `apksigner` as a single-signer
APK. Sizes stay under GitHub's 100 MB file limit, which is why TV Bro is the
build without the bundled Gecko engine and Termux is the per-ABI build rather
than the universal one.

Button Mapper was requested too and is not here: it is closed source and Play
Store only, so it cannot be redistributed. Install it through Aurora Store.

| File | Package | Version (code) | minSdk / target | Source | SHA-256 (file) | Signer DN | Signer SHA-256 |
|---|---|---|---|---|---|---|---|
| `aurora-store-4.8.4.apk` | `com.aurora.store` | 4.8.4 (76) | 23 / 37 | `https://f-droid.org/repo/com.aurora.store_76.apk` | `fd9c75d90d0f4a7c132b9b4a5a2cf1992a45e03b8d8ff988b7dcfbc0db2c4d11` | `CN=FDroid, OU=FDroid, O=fdroid.org` | `5c83c7672b929955dc0a1db89a5e6ae4389e2eae7ec939956041694e5815f532` |
| `fdroid-1.23.2.apk` | `org.fdroid.fdroid` | 1.23.2 (1023052) | 23 / 30 | `https://f-droid.org/F-Droid.apk` | `985f5181d48bb6bafd54083a048b391271e0ab28385881cc41294fb01a222762` | `CN=Ciaran Gultnieks, L=Wetherby, C=UK` | `43238d512c1e5eb2d6569f4a3afbf5523418b82e0a3ed1552770abb9a9c9ccab` |
| `kodi-21.3-omega-armeabi-v7a.apk` | `org.xbmc.kodi` | 21.3 (2103000) | 21 / 34 | `https://mirrors.kodi.tv/releases/android/arm/kodi-21.3-Omega-armeabi-v7a.apk` | `12d75e895649f68f217e42c2d881a94fd3177d7b9a7937825852aed545520cc8` | `CN=XBMC Foundation, OU=Android platform` | `f517b44b5db5e62a6c1ec55ba47526db7de0d61f6ba26a7987520e293499b8d5` |
| `jellyfin-androidtv-0.19.10.apk` | `org.jellyfin.androidtv` | 0.19.10 (191099) | 21 / 36 | `https://github.com/jellyfin/jellyfin-androidtv/releases/download/v0.19.10/jellyfin-androidtv-v0.19.10-release.apk` | `8510a517c99927076082917f41bf306dd7a2546c59d492dd11bde18d6e2e4628` | `CN=Joshua Boniface, OU=Jellyfin Team, O=Jellyfin` | `d881796ed2a67ff6ef9f676828723c6b1fa18e09388962cba4abc4a594a69131` |
| `tvbro-2.1.6-geckoexcluded.apk` | `com.phlox.tvwebbrowser` | 2.1.6 (69) | 24 / 36 | `https://github.com/truefedex/tv-bro/releases/download/v2.1.6/tvbro-2.1.6-generic-geckoExcluded.apk` | `d8634edfe8d94b4fb9a52005d68a090a7f1e85b7f39c2cf01a25dc9dd60942b2` | `CN=Pheodor Tsapana, O=PhloX Development Team` | `1e5124be7e7fcb7a6462b47a42a8567863c6fccc6fe7708cd278be4f43047c75` |
| `afwall-4.1.0-free.apk` | `dev.ukanth.ufirewall` | 4.1.0 (20260801) | 23 / 36 | `https://github.com/ukanth/afwall/releases/download/v4.1.0/AFWall_4.1.0_Free.apk` | `920f48c916a7eeddafe64403f03b7cce5c99682c03007cecde9bc7d60ef8d950` | `CN=Umakanthan Chandran` | `715e26c1254e70f44543453af8d6af9c22feee2cf1191de15e6a9f2df7e2a248` |
| `termux-app-0.118.3-armeabi-v7a.apk` | `com.termux` | 0.118.3 (1002) | 24 / 28 | `https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_armeabi-v7a.apk` | `89416397b70f9ff67a0044e8abe6ef82487cd48fcf543e2d23e02688cc541cf0` | `CN=APK Signer, OU=Earth, O=Earth` | `b6da01480eefd5fbf2cd3771b8d1021ec791304bdd6c4bf41d3faabad48ee5e1` |

Checked with `apkanalyzer` and `apksigner` from Android build-tools 36.1.0.

Notes per app:

- **F-Droid** trips the installer's HOME check. The category sits on the
  `StartupReceiver` `BOOT_COMPLETED` intent-filter, not on any activity, so it
  cannot become a home candidate (activity resolution ignores receivers) and the
  brick in `docs/BOOT_DEADLOCK.md` does not apply. Installed with
  `--allow-home` on that basis.
- **Termux** GitHub releases are signed with the project's debug key on purpose
  (the `OU=Earth` certificate). Do not mix with the F-Droid build, which has a
  different signer. The F-Droid build is a 115 MB universal APK, over the
  GitHub limit.
- **AFWall+** needs root. Allow it through the daemon:
  `./scripts/ROOT.sh --allow dev.ukanth.ufirewall`. Same for Termux if root is
  wanted there.
- **TV Bro** uses the system WebView, which on this firmware is the 2022 stock
  build. The Gecko-bundled arm32 APK is 150 MB and would give a current engine
  at the cost of a file too big for the repo.
- **Kodi** is the only single-ABI file here; it is the arm32 build the Kodi
  mirror publishes, 46 native libraries.

Signer certificates were compared against nothing external. What is proven is
that each file came over HTTPS from the project's own release channel and is
internally consistent under one certificate. Record the signer hashes above so a
later "update" that arrives under a different key is noticed.

## netflix-androidtv-11.0.1-armeabi-v7a.apk and netflix-androidtv-8.3.11-armeabi-v7a.apk (added 2026-09-20)

Netflix for Android TV (`com.netflix.ninja`), the leanback build. Two plain,
Netflix-signed APKs, nothing merged or re-signed. The device is an Android TV
build (`ro.build.characteristics=tv`, `android.software.leanback_only`), so
the phone/tablet app (`com.netflix.mediaclient`) is the wrong package here: a
merged 9.59.0 copy was staged on 2026-09-20, ran on the projector, and killed
itself right after the logo with a Bugsnag startup record `SPY-36283: Error CT`
and device type `android-tv`. It was removed the same day.

| | `netflix-androidtv-11.0.1-armeabi-v7a.apk` | `netflix-androidtv-8.3.11-armeabi-v7a.apk` |
|---|---|---|
| Package | `com.netflix.ninja` | `com.netflix.ninja` |
| versionCode / name | `19770` / `11.0.1 build 19770` | `12041` / `8.3.11 build 12041` |
| minSdk / targetSdk | `24` / `34` | `22` / `31` |
| ABIs | `armeabi-v7a` (5 native libs, `Stored`, `extractNativeLibs=false`) | `armeabi-v7a` |
| Size | 93,986,904 bytes | 44,746,837 bytes |
| SHA-256 (file) | `0dd3b3766c313ad2917ffe60e982e42e6ac100564b90ee97705c5519d6b49a4e` | `eabca3239407ebbb105d51d377bd76b8748caf632eb105458ef32b194d6e8ca3` |
| Signer DN | `CN=PPD Builder, OU=PPD, O="Netflix, Inc.", L=Los Gatos, ST=California, C=US` | same |
| Signer SHA-256 | `363863596ea99241eb71b1a985553aa604de3ea3c5f0c546742390e682164e6b` | same |
| Signature schemes | v3 (`apksigner verify --min-sdk-version 28` passes) | v1 + v2 |
| Leanback activity | `com.netflix.ninja.MainActivity`, `uses-feature android.software.leanback` | same |

**Source.** APKPure, pulled unattended with `apkeep` 1.0.0 on 2026-09-20:

```bash
apkeep -a com.netflix.ninja@19770 -d apk-pure .
apkeep -a com.netflix.ninja@12041 -d apk-pure .
```

Both verify with `apksigner` under the same Netflix certificate as the
phone app. That fingerprint (`3638...`) was matched against APKMirror's own
listing by fetching its `netflix-9-58-0-release` variant page for the phone app
on 2026-09-20 and finding the hash on it, so the APKPure copies are
cross-checked against an independent mirror. APKMirror's newest leanback
upload at the time was `13.1.2 build 26051` (94.79 MB, armeabi-v7a, Android
7.0+); its download is gated by an in-browser nonce, which is why the
APKPure builds are here instead. If you fetch 13.1.2 in a browser, check the
signer is `3638...` and it can replace 11.0.1.

**Why two files.** 11.0.1 is the newest build APKPure had. 8.3.11 is the
"Android 5.1+" branch Netflix still publishes (APKMirror shows it updated May
2026); it is the branch older set-top boxes run and the one to fall back to if
11.0.1 refuses to start. Try 11.0.1 first.

**The real risk: certification.** The firmware carries no Netflix
provisioning (no `ro.nrdp.*` properties, no Netflix permission XML, no
preinstalled Netflix package). Netflix for Android TV checks the device
against its certified list on the server, so on this projector the app may
install, sign in and then refuse with `-13`, `ui-800-3` or `tvq-pq-103` at
playback. The XDA and GitHub "uncertified device" mods that once worked
around this stopped working in late 2021 and their authors say so. Widevine
is present at L3 only (`libwvdrmengine.so` in `/vendor/lib/mediadrm`,
`liboemcrypto.so` missing, logged as "Falling back to L3"), so at best SD.
Nothing here can be verified without an account and a reboot; it is the
first thing to test after install.

Install like the other bundled apps:

```bash
./scripts/INSTALL_APP.sh apks/netflix-androidtv-11.0.1-armeabi-v7a.apk
```

**Measured 2026-09-20, 11.0.1 on the reference device.** Installed to
`/system/app/netflix`, registered after the reboot, starts, and shows "this
version of the Netflix app is not compatible with your device" instead of the
sign-in screen. Its own log during that launch: `com.netflix.ninja requires
the Google Play Store, but it is missing`, `Failed to get HDCP levels` from
`MediaDrm.getMaxHdcpLevel` (no HDCP path at all), Widevine falling back to
L3, and `GoogleApiManager ... SERVICE_INVALID`. Together with the missing
`ro.nrdp.*` provisioning that is the uncertified-device rejection this
section warned about, and nothing in this repo can change it: the check is
Netflix's, on their side. 8.3.11 was not tried; the same branch on other
uncertified boxes reports the same `-13` screen. The practical way to watch
Netflix on this projector is the Kodi add-on (CastagnaIT's `plugin.video.netflix`,
which uses the device's Widevine L3 and does not need certification) on the
Kodi build already bundled here, or an HDMI stick that is certified.


The stale phone build still sits in `/system/app/netflix` on the reference
device from the 2026-09-20 attempt; remove that directory when installing
the leanback build so two Netflix icons do not confuse things.
