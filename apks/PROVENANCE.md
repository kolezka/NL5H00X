Where the APKs in this directory came from, and what was checked before they
were trusted enough to install as a system launcher.

Last updated: 2026-07-29

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
