# Technical notes: NL5H00X

Last updated: 2026-10-24.

This page summarizes the inspected owner's unit, not every factory NL5H00X.
See the [dated device audit](DEVICE_AUDIT_2026-10-24.md) for commands, evidence
levels, artifact hashes and unresolved questions.

## Device overview

| Property | Verified observation |
|---|---|
| Product / platform | `NL5H00X_TP`, Hisilicon `bigfish`, hardware `hi3751` |
| Android | 9, API 28, `userdebug`, `dev-keys` |
| Security patch property | `2019-11-05` |
| CPU | Four CPUs, Cortex-A53 identifier |
| Running kernel / ABI | `4.9.127_s5`, `armv7l`; `armeabi-v7a,armeabi` |
| Linux-visible RAM | 1,005,264 KiB |
| eMMC user area | 7,650,410,496 bytes (7.65 GB) |
| SELinux | Permissive |
| Treble | Disabled |
| Root layout | System-as-root, ext4 mounted at `/` |

The running OS is 32-bit. CPU instruction-set support alone does not make a
64-bit ROM compatible with the vendor's drivers and projector services.

## Root access

Always check the actual identity; a serial prompt or successful TCP connection
is not a root check.

```sh
adb -s <projector-ip>:5555 shell id
adb -s <projector-ip>:5555 root
adb -s <projector-ip>:5555 shell id
```

The audit observed shell before `adb root`, then `uid=0(root)`. After the owner's
power cycle, ADB started as shell again. `adb root` restarts `adbd`, not the UART
console service.

On the inspected unit, both ADB shell and UART can use the already-installed
client without restarting `adbd`:

```sh
/system/xbin/su_hybrid 0 id
```

It returned `uid=0(root)`, exit 0. Plain `su 0 id` from UART returned
`setgid failed`, exit 1. Do not assume `su_hybrid` exists on a factory unit, and
do not treat one client's accepted syntax as the contract of every `su` version.
See [the root inventory](DEVICE_AUDIT_2026-10-24.md#root-paths).

## Storage architecture

| Partition | Name | Size | Purpose |
|---|---|---|---|
| mmcblk0p1 | fastboot | 8 MiB | Bootloader, not the Android boot image |
| mmcblk0p2 / p3 | bootargs / bootargsbak | 1 MiB each | Boot environment storage; names do not prove automatic fallback |
| mmcblk0p5 | recovery | 40 MiB | Recovery booted once through a `boot-recovery` BCB in `misc`; see [RECOVERY.md](RECOVERY.md) |
| mmcblk0p8 | logo | 40 MiB | Boot branding |
| mmcblk0p9 | boot | 40 MiB | Android kernel image |
| mmcblk0p20 | system | 1843 MiB | Mounted at `/`; `/system` is a directory on it |
| mmcblk0p21 | vendor | 300 MiB | Mounted at `/vendor` |
| mmcblk0p25 | userdata | Remaining user area | Mounted at `/data` |

There are 25 named partitions in the observed inventory. The
[complete map](DEVICE_AUDIT_2026-10-24.md#partition-and-boot-evidence) includes
panel calibration and secure-world partitions that must not be treated as spare
space. A partition named `fastboot` does not prove fastboot protocol support.

At the audit snapshot, the root filesystem had 251,864 KiB free; `/data` had
3,365,208 KiB free. Recheck before planning an installation or dump.

### Reading block devices

Use numeric block sizes. Earlier device tests rejected `bs=1M`; the audit used
`bs=4096` for bounded header reads. Verify both command output and exact byte
length. `adb exec-out` can return a diagnostic body without a useful failure
status; never interpret diagnostic text as a partition image.

The backup workflow streams to the host. Its generated restore tool still needs
the separate safety review described below; a completed download is not enough.

## Installation and system changes

Historical install attempts failed with `INSTALL_FAILED_INVALID_INSTALL_LOCATION`
even as root. The vendor whitelist gate caused that error on this unit. A
fail-succeed-fail hardware test on 2026-10-25 confirmed normal installs work
when `zyzys.install.whitelist=0`. The owner then saved that setting to
`/system/build.prop`, checked it after one reboot, and used a normal install to
update SmartTube. See [INSTALL_LOCKED.md](INSTALL_LOCKED.md#hardware-test-2026-10-25).

The `/system/app` route, including native libraries when required, remains a
fallback if normal installs are gated. The toolkit tries a normal install first.
Remounts and writes have since been used on this unit for the gate setting and
the [Developer options patch](DEV_OPTIONS_CRASH.md#the-patch); the October 24
audit itself made no install or remount change.

The remount target on this system-as-root layout is `/`, not `/system`. Any write
requires a scoped change, a verified original copy, a restore plan, and on-device
read-back. See the [security and recovery limits](SECURITY_ANALYSIS.md).

### Services and home screen

Preserve projector power, display and boot-critical components. In particular:

| Package | Role / constraint |
|---|---|
| `com.zhiying.powerservice` | Power management |
| `com.hisilicon.tv.service` | Display/projector control |
| `com.newlink.service` | Factory provisioning, activation and telemetry; see [VENDOR_TELEMETRY.md](VENDOR_TELEMETRY.md) |
| `com.newlink.wtprovision` | Vendor setup/home dispatch; disabling its main component caused a documented boot deadlock |

The October 24 audit reported Projectivy as the HOME activity, but that alone
did not show which component owned the vendor HOME intent. `wtprovision` owns
that intent and starts the component in its launcher cache; the current unlock
updates that cache. See [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md#the-vendor-home-dispatch).

## Emergency recovery

For a running Android system stuck in the documented setup-wizard deadlock,
follow [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md). For a system that does not reach
Android, start with [UNBOOTABLE.md](UNBOOTABLE.md) and capture evidence before
writing anything.

**Do not run a raw whole-device restore from a one-line example.** The
[restore hazards](../tests/contracts/observations/recovery-hazards.md) were
fixed in generated scripts and checked against a fake device by
[tests/restore-tests.sh](../tests/restore-tests.sh). No hardware restore was
tested. The [recovery safety HOLD](SECURITY_ANALYSIS.md#recovery-safety-hold)
remains open.

The existence of a recovery partition, a full image, or a working Android UART
shell is not proof of recovery from a bootloader/kernel failure. Bootloader
access and restore in the failed state remain unverified on this unit.
