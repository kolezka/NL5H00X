# Recovery tools

Boot the projector into its stock recovery and use recovery's root serial
console. The mechanism and the evidence are in
[docs/RECOVERY.md](../../docs/RECOVERY.md). The sequence was verified on one
unit on 2026-10-25.

| Tool | Runs on | Purpose |
| --- | --- | --- |
| `bcb.py` | host | Build, parse and check the 2048-byte bootloader message (BCB) for `misc` |
| `uart.py` | host | Shared client for the ESP32 UART bridge: handshake, sentinel command runner, capture |
| `enter-recovery.sh` | host + device | Check everything, write the BCB to `misc`, read it back, then reboot into recovery |
| `recovery-console.py` | host | Read-only probes on the recovery console, and `--reboot` to leave it |

## The verified sequence

```sh
bash tools/recovery/enter-recovery.sh --dry-run   # every check, no write
bash tools/recovery/enter-recovery.sh             # asks, writes, reboots
python3 tools/recovery/recovery-console.py        # probes in recovery
python3 tools/recovery/recovery-console.py --reboot
```

`enter-recovery.sh` stops before the reboot if any step fails:

1. Prerequisites: `bcb.py selftest` (the parser accepts the safe image and
   refuses a wipe image), the bridge shows its password prompt, a device on adb,
   and `su 0 sh -c 'id -u'` prints `0`. A missing prerequisite exits 2.
2. `misc` resolves to `/dev/block/mmcblk0p15` and is 1 MiB. A full dump is
   pulled, its hash matches the device, and it is **all zero**. Anything else
   stops the run: something else wrote `misc`, and that needs a look first.
3. Build the BCB, parse it as SAFE, push it to `/data/local/tmp`, and compare
   the staged copy's sha256 with the host copy.
4. Log in to the bridge and start a UART capture. The bridge takes one client,
   so the capture holds it from here through the reboot.
5. Ask for the word `write` (skip with `--yes`). Write with plain
   `dd bs=2048 count=1`, then `sync`. Toybox `dd` refuses `conv=fsync` and
   writes nothing, so it is not used.
6. Read all of `misc` back, check the hash of the pulled copy, `cmp` the first
   2048 bytes against the staged image, parse them as SAFE, and confirm the
   rest is zero.
7. Only then `adb shell reboot`. The capture waits for
   `init: First stage mount skipped (recovery mode)` and the script checks the
   log for the U-Boot line `boot to recovery, set fan to full speed`.

Logs and the `misc` dumps go to `$TMPDIR/nl5h00x-recovery-<timestamp>`, or to
`LOGDIR` if set. The before-dump is all zero by construction, so it is only a
record, not a backup anyone needs to keep.

## Revert

Normally nothing. Recovery clears the BCB when it starts, so the next reboot
goes to Android.

If the BCB was written but recovery never ran (for example Android came up),
zero it by hand and read it back:

```sh
adb shell "su 0 sh -c 'dd if=/dev/zero of=/dev/block/platform/soc/f9830000.emmc/by-name/misc bs=2048 count=1; sync'"
```

From the recovery console the same write is
`/vendor/bin/busybox dd if=/dev/zero of=<misc> bs=2048 count=1; /vendor/bin/busybox sync`.
The script prints both whenever it stops after the write.

## The recovery console

Recovery's serial console is `/vendor/bin/busybox sh` running as root
(`busybox id` gave `uid=0 gid=1007`). There are no applets in `PATH` and no
toybox, so every tool is `/vendor/bin/busybox <applet>`. Its `od` has no `-A`.

Plain `reboot` does nothing there. `/vendor/bin/busybox reboot -f` reboots back
to Android. `recovery-console.py --reboot` refuses unless the probes show uid 0
and a `/tmp/recovery.log`, so it cannot reboot a running Android by mistake. It
reports the reset it saw on UART; Android being up is a separate check.

## bcb.py

```sh
python3 tools/recovery/bcb.py build > bcb.img      # menu-only image
python3 tools/recovery/bcb.py parse < bcb.img      # SAFE (0) or UNSAFE (1)
python3 tools/recovery/bcb.py check-misc misc.img  # 1 MiB dump: SAFE BCB, rest zero
python3 tools/recovery/bcb.py check-zero misc.img  # 1 MiB dump: all zero
python3 tools/recovery/bcb.py selftest             # parser controls
```

`build --wipe-data` is refused. `build --wipe-data --allow-wipe` is the only way
to produce a wipe image, and it exists as a negative control: `parse` and
`check-misc` always call it UNSAFE, so `enter-recovery.sh` will not write it.

## Password handling

The bridge password is `UART_CONSOLE_PASSWORD` in the ESP32 firmware's
gitignored `secrets.h`. `uart.py` reads it from that file each run (override the
path with `UART_SECRETS`). It is never printed, logged or passed on a command
line, and any copy of it in bytes received from the bridge is replaced with
`<REDACTED>` before they reach the screen or a log. Do not put it in a script,
an environment variable in a committed file, or a commit.

`UART_HOST` and `UART_PORT` override `projector-uart.local:2323`.

## Not covered

- No writes from recovery: no wipe, no sideload, no `--update_package`, no
  partition restore. The recovery menu was reached and left, nothing more.
- No factory reset. `/cache/recovery/last_log*` shows recovery ran three times
  with `--wipe_data` before; that is history, not something to repeat.
- No `adb` in recovery was tested. The UART console is the only channel used.
- The restore scripts' false successes in
  [recovery-hazards.md](../../tests/contracts/observations/recovery-hazards.md)
  are unchanged. Reaching recovery does not make those scripts safe.

## How these were checked off the device

The scripts were run against a fake bridge and a fake `adb` that maps device
paths to a temporary directory. That covered the handshake, the sentinel
runner on both consoles, password redaction, the `--reboot` refusal on Android,
and the stop paths in `enter-recovery.sh` (non-zero `misc`, failed `dd`, short
readback, no confirmation, no device, bridge down). The cleaned-up scripts
themselves have not yet been run against the projector. The verified run used
the earlier one-off scripts with the same protocol.
