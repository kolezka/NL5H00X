#!/usr/bin/env python3
"""Drive the stock recovery root console over the ESP32 UART bridge.

Recovery's serial console is `/vendor/bin/busybox sh` as root, with no applets
in PATH. Every tool is called as `/vendor/bin/busybox <applet>`.

  recovery-console.py            read-only probes: identity, recovery.log, misc, mounts
  recovery-console.py --reboot   probes, then `busybox reboot -f` and wait for the reset

Nothing here writes to the device. `--reboot` is refused unless the probes show
uid 0 and a /tmp/recovery.log, so it cannot reboot a running Android by mistake.
Plain `reboot` does nothing in this recovery; `reboot -f` was verified to work.

The bridge takes one client. Stop any capture before running this.
Exit codes: 0 ok, 1 not in recovery or reboot not seen, 2 bridge or secret problem.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uart import BB, Bridge, BridgeError  # noqa: E402

MISC = "/dev/block/platform/soc/f9830000.emmc/by-name/misc"
RESET_MARKERS = [b"Restarting system", b"reboot:", b"System startup", b"U-Boot"]


def probe(b: Bridge) -> bool:
    """Run read-only probes. Returns True when this is the recovery root console."""
    def show(cmd, timeout=20):
        rc, body = b.run(cmd, timeout)
        print(f"$ {cmd}\n{body}\n[rc={rc}]\n")
        return rc, body

    rc_id, out_id = show(f"{BB} id")
    rc_log, _ = show(f"{BB} grep -E 'Command:|no_command' /tmp/recovery.log")
    # od here has no -A flag; default octal offsets are fine for a visual check.
    show(f"{BB} dd if={MISC} bs=2048 count=1 2>/dev/null | {BB} od -c | {BB} head -6")
    show(f"{BB} mount | {BB} grep -E ' /(cache|system|data|vendor) '")

    is_root = rc_id == 0 and "uid=0" in out_id
    in_recovery = rc_log == 0
    print(f"root console: {'yes' if is_root else 'NO'}")
    print(f"recovery log present: {'yes' if in_recovery else 'NO'}")
    return is_root and in_recovery


def reboot(b: Bridge) -> bool:
    """Send `busybox reboot -f` and wait for the link to drop or the reset to print."""
    b.send(f"{BB} reboot -f")
    out = b.recv_until(RESET_MARKERS, 25)
    seen = [m.decode() for m in RESET_MARKERS if m in out]
    if b.closed:
        print("reboot: bridge link dropped")
        return True
    if seen:
        print(f"reboot: reset seen on UART ({', '.join(seen)})")
        return True
    print("reboot: no link drop and no reset text within 25 s")
    return False


def main(argv: list) -> int:
    args = argv[1:]
    if args not in ([], ["--reboot"]):
        print(__doc__, file=sys.stderr)
        return 2
    b = Bridge()
    try:
        b.login()
        print(f"[console: {b.prompt()}]\n")
        ok = probe(b)
        if not args:
            return 0 if ok else 1
        if not ok:
            print("refusing --reboot: this does not look like the recovery root console")
            return 1
        if not reboot(b):
            return 1
        print("Next: `adb wait-for-device` then `adb shell getprop sys.boot_completed`.")
        print("This script saw the reset only. Android being up is a separate check.")
        return 0
    except BridgeError as e:
        print(f"bridge: {e}", file=sys.stderr)
        return 2
    finally:
        b.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
