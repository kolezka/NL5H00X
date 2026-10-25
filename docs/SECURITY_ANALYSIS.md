# Security and recovery limits

Last updated: 2026-10-24.

This page separates observed access from untested recovery claims. The
[device audit](DEVICE_AUDIT_2026-10-24.md) is the current evidence record for the
owner's modified NL5H00X_TP. Earlier claims of maximum SELinux enforcement,
manufacturer intent and guaranteed recovery were stronger than the evidence.

## Root is available, but it does not bypass every policy

Verified on the inspected unit:

- `adb root` followed by `id` returned UID 0. ADB returned to shell after the
  owner's power cycle.
- The Android UART console runs as shell. The existing
  `/system/xbin/su_hybrid 0 id` returned UID 0; ordinary `su 0 id` failed.
- `sud` runs as root under init. Controlled app-UID probes with `NO_NEW_PRIVS`
  demonstrated both successful root execution and explicit allow-list refusal.
- SELinux is **Permissive**. An `avc: denied` line does not by itself show that
  the kernel blocked the operation; inspect its context and `permissive` field.
- `ro.secure=1` is present. It does not establish the cause of an APK install
  failure, bootloader lock, or a general "maximum security" mode.

Root provides broad access to files and services, including destructive access.
It does not make vendor PackageManager behavior disappear, supply a compatible
new kernel, or establish a working rescue channel.

### Existing root policy needs review

The audit found multiple installed root clients and two different `sud` binaries.
The selected init service uses `/system/xbin/sud`. The version installed during the
audit handled requests serially, so one long-lived shell held every later client,
and it ignored a failed `setuid`, which ran the command as root. Both are fixed in
the daemon merged as PR #15 and covered by `tests/sud-tests.sh`: a failed uid switch
now exits 1, and a caller with a full stderr pipe can no longer hold the session
slots it does not own. A long-lived root command still occupies its own slot while
it runs, which is a documented limit. The live observations and test limits are
recorded in the audit.

The allow-list is a grant of administrative access, not a list of harmless apps.
Review package identities carefully: the inspected list's `org.fdroid.froid`
differs from the installed `org.fdroid.fdroid`, which was explicitly refused.
Do not replace root clients or edit policy as an incidental cleanup.

## Installation restriction: vendor whitelist gate

Earlier device tests recorded `INSTALL_FAILED_INVALID_INSTALL_LOCATION` across
normal install attempts, including root. The dated matrix and system-app
workaround are in [INSTALL_LOCKED.md](INSTALL_LOCKED.md).

Follow-up VDEX/ODEX analysis identified a vendor whitelist gate. The live
`zyzys.install.whitelist` property is empty and its configuration file is zero
bytes, selecting a branch that returns `-19` before copying. See the
[recovered code evidence](INSTALL_LOCKED.md#verified-vendor-whitelist-branch).
No installation or policy change was attempted; bypassing this gate is not yet a
verified complete fix. This branch does not require a SELinux denial or thrown
volume-resolution exception.

## Platform signature and exposed administration

The current Settings APK's verified certificate matches the AOSP test-platform
fingerprint documented in [DEV_OPTIONS_CRASH.md](DEV_OPTIONS_CRASH.md). This can
make a correctly re-signed system APK patch feasible, but signing compatibility
is not runtime compatibility or safety.

Network ADB and the ESP console are administrative interfaces. Keep them on a
trusted, restricted network. The ESP console uses plaintext TCP; browser firmware
upload uses HTTP authentication, not end-to-end encryption. Do not publish
credentials, private app data, raw device dumps or OTA secrets in this public
repository. A root-capable Wi-Fi bridge is not a security boundary for the
projector.

## Backup requirements

A backup must be validated against its actual source and intended restore target.
A byte count or transfer-success message is not validation.

| Target | Observed mapping / size | Why it matters |
|---|---|---|
| Bootloader | `mmcblk0p1`, 8 MiB, named `fastboot` | Not the Android boot image |
| Android boot | `mmcblk0p9`, 40 MiB | Kernel image |
| Recovery | `mmcblk0p5`, 40 MiB | Exists; successful recovery boot not verified |
| System | `mmcblk0p20`, 1843 MiB | ext4 root mounted at `/` |
| Userdata | `mmcblk0p25` | Private data and settings; size from live partition inventory |
| eMMC user area | 7,650,410,496 bytes | Not automatically a copy of separate eMMC boot areas or external device state |

The [complete map](DEVICE_AUDIT_2026-10-24.md#partition-and-boot-evidence) also
identifies environment, secure-world and panel-calibration partitions.

Before any planned write:

- Identify the exact block device by its current map, not an old filename.
- Check exact byte lengths; never accept a percentage-size threshold.
- Compare checksums against the source and parse structures used by the restore.
- Keep another copy on a separate medium or machine. One local file is not the
  only copy you should depend on.
- Establish how to reach the device if the change prevents Android from booting.
- Verify the restore algorithm with isolated fixtures before considering hardware.
- Inspect generated restore scripts rather than trusting their success messages.

The earlier full-device stream used host-side blocks to avoid filling the same
flash being imaged. Historical transfer rates and free-space readings are not
promises for the next backup. Use current measurements and the toolkit's checks.

## Recovery safety HOLD

[Recorded fake-device traces](../tests/contracts/observations/recovery-hazards.md)
show restore hazards, including a partition path accepting a tiny image,
misleading success reporting, and whole-device branches with different behavior
on successful and failed push. These are isolated characterization results, not
a successful hardware restore. The
[design's safety HOLD](superpowers/specs/2026-09-12-system-flow-refactor-design.md#recovery-safety-hold)
requires separate verification before hardware use.

A checksum-verified backup cannot guarantee recovery, zero downtime, or access to
a nonbooting device. A UART Android shell helps with an Android-level boot stall;
it does not establish bootloader access or the ability to restore damaged flash.

No raw restore, recovery boot, environment write or bootloader interruption was
performed in the October audit. In particular, knowing the environment's CRC and
`bootdelay=0` does not make changing it safe.

## Electrical limits of the ESP bridge

The bridge's GPIO-level power heuristic is not isolation and does not guarantee
against back-feeding. It cannot substitute for verifying the actual circuit,
supply capacity, reset behavior and power sequencing. A functioning TCP console
only verifies that the system worked during that observation.

## Recommended change order

1. Preserve working ADB/UART root access and document the actual installed clients.
2. Fix root-daemon behavior with offline regression tests before deployment.
3. Plan a scoped validation of the identified whitelist gate and later install
   stages before proposing a policy or framework change.
4. Review and test recovery tooling; retain the HOLD until the relevant checks pass.
5. Consider a narrowly scoped system change only with a verified original and a
   usable restore channel. Keep projector power, display and provisioning services.

This is a staged investigation plan, not authorization to flash or modify the
only physical unit.
