# Booting stock recovery

Verified on 2026-10-25, on one unit (the owner's modified NL5H00X_TP), one
recovery boot. The tools are in [tools/recovery](../tools/recovery/README.md).

## Short version

Write an Android bootloader message (BCB) with `command=boot-recovery` to the
`misc` partition and reboot. U-Boot then boots the recovery image. Recovery
opens its menu, clears the BCB, and gives a root shell on the serial console.

`adb reboot recovery` does not do this on this build. It writes no BCB (`misc`
stayed all zero), so U-Boot boots Android. That explains the earlier failed
attempt recorded in [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md#why-every-channel-dies-at-once).

## The BCB

`misc` is `/dev/block/platform/soc/f9830000.emmc/by-name/misc`, which is
`mmcblk0p15`, 1 MiB. The BCB is its first 2048 bytes, in the AOSP
`bootloader_message` layout:

| Field | Bytes | Value written |
| --- | --- | --- |
| `command` | 0 to 31 | `boot-recovery`, then zeros |
| `status` | 32 to 63 | zero |
| `recovery` | 64 to 831 | zero (no arguments) |
| `stage` | 832 to 863 | zero |
| `reserved` | 864 to 2047 | zero |

An empty `recovery` field means recovery starts with no arguments and shows its
menu. An argument such as `--wipe_data` would make it act on its own.
`tools/recovery/bcb.py` builds only the empty form by default and calls
anything else UNSAFE.

## What the verified run showed

`misc` was all zero before the write. The image was staged in
`/data/local/tmp`, its hash checked, then written as root with plain
`dd bs=2048 count=1` and `sync`. Toybox `dd` refuses `conv=fsync`
(`conv option disabled`, exit 1, nothing written), so that flag is not used.
The readback matched the staged image and parsed as SAFE.

The reboot came from the Android shell:

```
console:/ $ [ 5704.367980] reboot: Restarting system with command 'shell'
```

U-Boot read the BCB and chose recovery:

```
CUSTOM func[custom_pull_gpio_demo] line[322] :INFO: boot to recovery, set fan to full speed
```

The kernel booted with the recovery command line (`recoverybootargs`), and
init ran in recovery mode:

```
[    2.745867] init: First stage mount skipped (recovery mode)
```

Processes then ran in the `u:r:recovery:s0` SELinux domain, and a `busybox`
process opened `/dev/console`. Recovery reached its menu: `/tmp/recovery.log`
showed `Command: "/sbin/recovery"` with no arguments and `no_command_text`.

## The recovery console

Reached through the same ESP32 UART bridge and password gate as the Android
console. The prompt is `# `.

- It is `/vendor/bin/busybox sh` as root: `busybox id` gave `uid=0 gid=1007`.
- No applets are linked into `PATH` and toybox is absent. Call every tool as
  `/vendor/bin/busybox <applet>`.
- `busybox od` has no `-A` flag.
- Plain `reboot` does nothing. `/vendor/bin/busybox reboot -f` rebooted cleanly
  back to Android.

## The BCB clears itself

Recovery clears the BCB when it starts, so the reboot after recovery goes to
Android with no host action. If recovery never runs after the write, the BCB
stays and every reboot tries recovery until it is zeroed. The revert commands
are in [tools/recovery/README.md](../tools/recovery/README.md#revert).

## Earlier recovery runs on this unit

`/cache/recovery/last_log*` shows recovery ran three times before, each with
`--wipe_data` from a BCB. Those were factory resets. They show the recovery
image works on this unit; they are not something to repeat.

## Limits

- One unit, one recovery boot. Other firmware builds may behave differently.
- Nothing was written from recovery: no wipe, no sideload, no restore.
- adb inside recovery was not tested.
- This does not change the restore safety HOLD. The generated restore scripts
  fail loudly since 2026-10-26 (see
  [recovery-hazards.md](../tests/contracts/observations/recovery-hazards.md)),
  but no restore has been exercised on the unit.
- Writing `misc` needs Android root. A unit that cannot boot Android cannot use
  this path unless something else writes the BCB.
