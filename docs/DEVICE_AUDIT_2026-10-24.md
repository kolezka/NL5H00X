# Device audit: root, boot and modification options

Last updated: 2026-10-24.

This report records observations from one owner's NL5H00X_TP. It does not describe
an untouched factory image: the unit already contains third-party apps, multiple
root clients and an init-started root daemon. Other units may differ.

**Result:** root commands work over ADB and over the Android UART console. Root
access does not establish a working bootloader rescue channel or make arbitrary
system changes safe. No boot, recovery, environment or calibration partition was
written during the audit.

## Evidence levels and scope

- **Verified live:** decoded device output, including command completion and
  exit status where relevant.
- **Historical:** earlier repository analysis, not repeated in this session.
- **Inferred:** an explanation consistent with the observations, not isolated by
  a controlled experiment.
- **Unverified:** a capability or procedure not exercised.

The work began with read-only inspection. With the owner's later approval, a
stalled diagnostic process was terminated and Projectivy was force-stopped for
a root-daemon test. Projectivy was then started again; `dumpsys activity` showed
its HOME activity resumed. The owner separately unplugged and reconnected the
hardware. No kernel, framework, app APK or root binary was changed.

## Device inventory

The following were verified live on 2026-10-24.

| Item | Observation |
|---|---|
| Product | `NL5H00X_TP`, manufacturer `Hisilicon` |
| Board / platform | `bigfish`; CPU hardware string `hi3751` |
| CPU | Four CPUs, implementer `0x41`, part `0xd03` (Cortex-A53) |
| Running kernel | `4.9.127_s5`, `armv7l` |
| Android | 9, API 28, `userdebug`, `dev-keys` |
| Build | `NL5H00X_TP-userdebug 9 PPR1.180610.011 eng.hudson.20220706.192233 dev-keys` |
| Security patch property | `2019-11-05` |
| App ABI list | `armeabi-v7a,armeabi` |
| RAM exposed to Linux | `MemTotal: 1005264 kB`, about 982 MiB |
| Swap | `319088 kB`; zram listed in the device configuration |
| eMMC user area | 14,942,208 sectors of 512 bytes = 7,650,410,496 bytes |
| SELinux | `Permissive` |
| Debug settings | `ro.debuggable=1`, `ro.secure=1` |
| Treble | `ro.treble.enabled=false`, `ro.vndk.lite=true` |
| Root filesystem | `ro.build.system_root_image=true`; `/dev/root` at `/`, ext4, read-only |
| Vendor filesystem | ext4, read-only |
| Encryption property | `ro.crypto.state=unsupported` |
| Current HOME resolution | `com.spocky.projengmenu/.ui.home.MainActivity` |

The kernel and userspace are 32-bit. That is not proof of an ARMv7-only CPU and
is not permission to flash an arm64 system. Display, power and calibration still
depend on the vendor stack.

At the sampled time, `/` had 251,864 KiB free and `/data` had 3,365,208 KiB free.
These are point-in-time readings, not capacity guarantees for a later install.

## Root paths

### ADB

The session verified this sequence against the explicitly selected projector:

```sh
adb -s <projector-ip>:5555 shell id
adb -s <projector-ip>:5555 root
adb -s <projector-ip>:5555 shell id
```

The first identity was `uid=2000(shell)`; after restarting `adbd` as root it was
`uid=0(root)` in `u:r:su:s0`. After the owner's power cycle, ADB again started as
shell. `adb root` is not a persistent change to the UART console service.

### UART

After authenticating to the ESP bridge, the Android prompt was `console:/ $`.
These two commands produced different results:

```sh
su 0 id                         # setgid failed, exit 1
/system/xbin/su_hybrid 0 id       # uid=0(root), exit 0
```

The second command was rechecked after the owner reconnected the hardware. Use
it only if this installed client exists and the identity check succeeds. Its
successful output alone does not distinguish its setuid and daemon paths.

`/init.rc` starts the console as `user shell`, `group shell log readproc`, with
`seclabel u:r:shell:s0`. UART is a transport, not an automatic privilege grant.

| Installed path | Mode | Observation |
|---|---|---|
| `/system/xbin/su` | `0755`, root-owned | Fails from the UART shell; succeeds for the allowed app-UID probe through the existing root infrastructure |
| `/system/xbin/su_orig` | `0755`, root-owned | Preserved alternate client |
| `/system/xbin/su_hybrid` | `4755`, root-owned | Returns root from UART and ADB shell |
| `/system/xbin/sud` | `0755`, root-owned | Selected by the current init service |
| `/system/bin/sud` | `0755`, root-owned | A different binary also exists; not the path selected by that service |

Do not assume the current installed client names and modes match every historical
README example or every future installation of `scripts/ROOT.sh`.

### App-root policy and the queue problem

Verified live: `init.svc.sud=running`, a root-owned `sud` process with parent init,
and the abstract socket `@projector_su`. The current service starts
`/system/xbin/sud` in `u:r:su:s0`.

A diagnostic process was switched to an application UID, then the existing
`privtest` set `NO_NEW_PRIVS` before executing the command:

| Caller / command | Result | Exit |
|---|---|---|
| Projectivy UID, `id` control | Original application UID | 0 |
| Same UID, `su 0 id` | `uid=0(root)` | 0 |
| F-Droid UID, `id` control | Original application UID | 0 |
| Same UID, `su 0 id` | Explicit `org.fdroid.fdroid not allowed` | 1 |

These probes use a shell SELinux context. They verify the UID/NO_NEW_PRIVS path,
not every behavior of the real app. The existing allow-list contains
`org.fdroid.froid`, which differs from the installed `org.fdroid.fdroid`.
No allow-list entry was changed.

Before the successful probes, Projectivy held a root shell open. `sud` waited in
`do_wait`; its child shell waited in `pipe_wait`; a second root request timed out.
The Projectivy client and root shell shared the same pipe descriptors. This
matches `root/sud.c`'s synchronous accept/handle loop and child `waitpid`.

After the approved cleanup and Projectivy stop, both Projectivy and `sud` had new
PIDs and the probes succeeded. The old daemon's exit cause was not captured.
Do not claim that the same daemon resumed, or that SIGPIPE was proven. A permanent
concurrency fix is a separate task; it was not part of this audit.

## Partition and boot evidence

The complete by-name listing and the CRC-checked environment agree on these
names. Sizes below use the boot environment's binary MiB units.

| Partition | Name | Size |
|---|---|---|
| p1 | fastboot (bootloader) | 8 MiB |
| p2 / p3 | bootargs / bootargsbak | 1 MiB each |
| p4 | slaveboot | 2 MiB |
| p5 | recovery | 40 MiB |
| p6 / p7 | panelparam / deviceinfo | 8 / 2 MiB |
| p8 | logo | 40 MiB |
| p9 | boot (Android image) | 40 MiB |
| p10 / p11 | dtbo / atf | 1 / 2 MiB |
| p12 / p13 | trustedcore / securestore | 8 / 10 MiB |
| p14 / p15 | versioninfo / misc | 1 MiB each |
| p16 / p17 | bootmusic / bootmusicsec | 10 MiB each |
| p18 / p19 | tconparam / demura | 80 / 4 MiB |
| p20 / p21 | system / vendor | 1843 / 300 MiB |
| p22 / p23 / p24 | atv / log / cache | 50 / 60 / 100 MiB |
| p25 | userdata | Remaining user area |

**p1 is not the Android kernel image.** A partition named `fastboot` does not
establish a fastboot protocol endpoint. Calibration partitions are not spare
storage for experiments.

Bounded 4096-byte header reads, with exact-length checks, showed:

| Header field | boot | recovery |
|---|---|---|
| Android header version | 0 | 0 |
| Page size | 2048 | 2048 |
| Kernel payload bytes | 9,346,760 | 18,538,072 |
| External ramdisk bytes | 0 | 0 |
| Kernel wrapper magic | `0x27051956` (uImage) | `0x27051956` (uImage) |

Header `ramdisk=0` does not exclude an archive embedded inside the kernel.
The later offline check below decompressed both kernels from the owner's backup;
it did not boot recovery or establish identity with every current live partition.

The 65,536-byte environment passed CRC32 validation and contained:

```text
bootdelay=0
stdin=serial
stdout=serial
stderr=serial
root=/dev/mmcblk0p20
skip_initramfs
androidboot.selinux=permissive
console=ttyAMA0,115200
```

This does not prove that autoboot can be interrupted at delay zero or that a
modified environment has a safe fallback. Do not change it merely because its
CRC format is known.

Selected verified-boot/slot properties were empty; package features nevertheless
declared `android.software.verified_boot`. No `vbmeta` name appeared in the
captured by-name inventory. These observations do not establish bootloader unlock
or absence of SoC secure boot.

`/sys/fs/pstore` existed and was mounted, but its directory was empty.
`/proc/config.gz` was missing. The running system did not expose the inspected
`/sys/class/udc`, `/sys/class/android_usb` or `/config/usb_gadget` paths. This is
software-interface evidence, not a complete physical controller inventory.

### Offline recovery image check

A follow-up independently read bounded boot/recovery regions from the owner's
2026-09-13 full user-area image. It verified the Android image ID, uImage header
CRC and payload CRC, decompressed each kernel, then parsed CPIO headers and the
archive trailer rather than trusting a byte count or string search.

| Backup region | SHA-256 | Embedded archive |
|---|---|---|
| boot / p9 | `2d69bd1eeabaed74b7433b36a0420ea789b8692f4ed11f6bdb2e3df80f444989` | 3,153,408 bytes, 57 entries, including `init` and `init.rc` |
| recovery / p5 | `88bf2536d6607a3575adce31711b41bb8aad97374eeab856a7f1ac2100e9fba4` | 20,690,944 bytes, 245 entries, including `init`, `sbin/recovery` and `vendor/bin/busybox` |

Recovery's extracted `init.rc` includes:

```text
service console /vendor/bin/busybox sh
    console
    user root
    group log
    seclabel u:r:recovery:s0
```

This is verified configuration in the backup, not an observed recovery shell.
The older description of boot's initramfs as only a 462-byte empty archive is
incorrect for this image. Live `skip_initramfs` explains why the presence of an
embedded archive is distinct from normal Android's root filesystem selection.

The backup image checks do not prove current full-partition identity, verified
boot signatures, a functioning recovery entry path, or restoration from a failed
state. No BCB write, reset, autoboot interruption or recovery launch was performed
for this follow-up. Detailed U-Boot control-flow conclusions from the delegated
analysis remain outside this independently verified subset.

## Framework and signing evidence

`TvSettings.apk` was pulled and its SHA-256 matched the source. `apksigner verify
--print-certs` succeeded; the certificate matched the AOSP test-platform
fingerprint recorded in [DEV_OPTIONS_CRASH.md](DEV_OPTIONS_CRASH.md#the-platform-key).
Signing compatibility does not establish runtime compatibility of a patch.

The installation-code investigation needs compiled artifacts, not just the JAR:

| Artifact | Bytes | SHA-256 |
|---|---|---|
| `services.jar` | 183 | `1c16f5976318fadcf7add92c518a93896f99e2a78f742b7347d8539103264882` |
| `services.vdex` | 8,665,104 | `eb4425ceb3272861c7b9f66ee7915d6a906f3b4e80dfe5afbe4bbbae5b6d7f28` |
| `services.odex` | 20,888,656 | `37cb9af67e5bb4a7c1ad2ca371839f5de67ab3693bef1cc246c10b9eddb03d24` |

The JAR contains only `META-INF/MANIFEST.MF`; VDEX has version 019 and ODEX is
ELF32. All three local hashes matched the device. Follow-up decoding identified
a vendor whitelist gate in `InstallParams.handleStartCopy()`. With the live
`zyzys.install.whitelist` property empty and the readable
`/system/etc/WhiteListPermissionFilter.cfg` file zero bytes, that gate returns
`-19` and skips copying. The property-reading path was controlled against SDK
value `28`. See [INSTALL_LOCKED.md](INSTALL_LOCKED.md#verified-vendor-whitelist-branch)
for methods, offsets and the distinction from the later location checks.

No property was changed and no install attempted. The code and current inputs
explain this denial branch, not successful installation after bypassing it or
the inputs present during every historical failure.

## What this enables, and what it does not

- **Verified:** root diagnostics over ADB and Android UART, plus the controlled
  allowed/refused app-UID tests above.
- **Candidate changes:** targeted system apps, settings and root services after
  scoped review and verified backups. The prior system-app installation route
  is documented in [INSTALL_LOCKED.md](INSTALL_LOCKED.md).
- **Not a routine upgrade:** Magisk needs analysis of the unusual boot/recovery
  layout; KernelSU requires a compatible vendor-kernel integration. A generic
  Android image is not a drop-in replacement for this non-Treble vendor stack.
  No current root-framework compatibility survey was performed.
- **Not verified:** recovery boot, pre-kernel UART rescue, USB-device ADB,
  bootloader unlock, safe raw restore or replacement firmware.

The restore safety HOLD in
[recovery-hazards.md](../tests/contracts/observations/recovery-hazards.md) remains
relevant. A checksum-verified image is necessary evidence, not a tested rescue
procedure. There must also be an accessible restore channel in the failed state.

### Recovery characterization, not a hardware restore

At documentation-worktree baseline `ad79826`, an independent run of
`/bin/bash tests/contracts/characterize-recovery.sh` returned exit 1: 256 checks
passed and one failed. The failure is wording drift in the saved hazard
observation: the generated text names the source plus both mapped target hashes,
where the fixture names only the fake block hash. This is not a green suite or
a repaired restore implementation.

The contained run re-observed false success after a failed partition write,
reboot after a successful push without a restore write, and raw whole-device
fallback after failed push. All block writes were intercepted by the fake; no
physical device was used for these checks.

The current generator also calls `backup_partition` on `mmcblk0p1` and names the
file `boot.img`. On this device map, that means **U-Boot, not Android boot p9**.
Do not flash an old `boot.img` to p9 based on its filename. Inspect its format and
source mapping first. Documentation corrections do not repair this generator.

## Electrical and bridge limits

The owner reported 3.3 V at IR VCC and later reported operation after moving to
the ESP board's 5V pin. This session did not independently measure either loaded
supply voltage, available current, regulator behavior or the final wiring.
Neither USB firmware tests nor a working Wi-Fi connection validate that supply.

The ESP firmware's GPIO-level heuristic is **not electrical isolation** and does
not replace series resistors or guarantee protection against back-feeding. Do
not use an idle UART level as proof of projector power state. Direct wiring and
simultaneous power sources require a verified circuit, not a software promise.

The working Android UART session also does not prove that the bridge captures
U-Boot from power-on. Validate early capture and the rescue channel separately
before considering any boot-critical write.

## Follow-up work

1. Fix and regression-test `sud` concurrent-client handling and disconnect paths.
2. Reconcile installed root clients, their modes and package allow-list entries.
3. Use the identified whitelist branch to design a scoped installation test;
   later install/location stages remain unverified and no bypass was applied.
4. Verify recovery tooling against isolated fakes, then establish a real rescue
   plan without making the only projector the destructive test fixture.

This report is the dated baseline for those tasks, not a claim they are complete.
