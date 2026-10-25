#!/bin/bash
# Boot the projector into stock recovery by writing a menu-only BCB to misc.
#
#   bash tools/recovery/enter-recovery.sh             # full run, asks before the write
#   bash tools/recovery/enter-recovery.sh --dry-run   # every check up to the write, no write
#   bash tools/recovery/enter-recovery.sh --yes       # full run, no question
#
# Needs: the projector on adb with root (`su 0`, override with ROOT_CMD), the ESP32
# bridge on projector-uart.local:2323, the bridge secrets.h readable, python3.
#
# Why a BCB: `adb reboot recovery` does not write one on this build, so U-Boot
# boots Android. With `boot-recovery` in misc, U-Boot boots recovery (verified on
# one unit, 2026-10-25). Recovery clears the BCB itself when it starts.
#
# What it does NOT do: wipe, sideload, or write anything from recovery. It
# refuses to write unless misc is all zero first, so the only "backup" is zeros.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC=/dev/block/platform/soc/f9830000.emmc/by-name/misc
MISC_DEV=/dev/block/mmcblk0p15
MISC_SECTORS=2048          # 1 MiB, from blkdevparts 1M(misc)
MISC_BYTES=1048576
STAGE=/data/local/tmp
ROOT="${ROOT_CMD:-su 0}"
MARK_UBOOT='boot to recovery, set fan to full speed'
MARK_INIT='First stage mount skipped (recovery mode)'

DRY=0; YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --yes) YES=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}/nl5h00x-recovery-$(date +%Y%m%d-%H%M%S)}"
LOGDIR="${LOGDIR%/}"

PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()   { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "=== $1 ==="; }
prereq() { echo "missing prerequisite: $1" >&2; exit 2; }

revert_text() {
    cat <<EOF

Revert (only needed if misc still holds the BCB, for example Android came up):
  from Android:   adb shell "$ROOT sh -c 'dd if=/dev/zero of=$MISC bs=2048 count=1; sync'"
  from recovery:  /vendor/bin/busybox dd if=/dev/zero of=$MISC bs=2048 count=1; /vendor/bin/busybox sync
Then read misc back and confirm it is zero before the next reboot.
In the normal case nothing is needed: recovery clears the BCB when it starts.
EOF
}

# Stop here, before the reboot. Once the BCB is written, say how to undo it.
stop() {
    bad "$1"
    echo
    echo "STOPPED: not rebooting. $PASS passed, $FAIL failed. Logs: $LOGDIR"
    [[ "${WRITTEN:-0}" == 1 ]] && revert_text
    exit 1
}

CAP_PID=
cleanup() { [[ -n "$CAP_PID" ]] && kill "$CAP_PID" 2>/dev/null; }
trap cleanup EXIT

as_root() { adb shell "$ROOT sh -c '$1'" | tr -d '\r'; }
host_sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
dev_sha()  { as_root "sha256sum $1" | cut -d' ' -f1; }

# Pull a root-written file and prove the copy matches the device.
pull_verified() {  # pull_verified DEVICE_PATH HOST_PATH
    as_root "chmod 644 $1" >/dev/null || return 1
    adb pull "$1" "$2" >/dev/null 2>&1 || return 1
    [[ "$(host_sha "$2")" == "$(dev_sha "$1")" ]]
}

head_ "prerequisites"
for tool in adb python3 shasum cmp; do
    command -v "$tool" >/dev/null 2>&1 || prereq "$tool not in PATH"
done
mkdir -p "$LOGDIR" || prereq "cannot create $LOGDIR"
python3 "$HERE/bcb.py" selftest >"$LOGDIR/bcb-selftest.txt" 2>&1 \
    || { cat "$LOGDIR/bcb-selftest.txt"; prereq "bcb.py selftest failed"; }
ok "bcb.py parser controls (SAFE accepted, wipe refused)"
python3 "$HERE/uart.py" check || prereq "UART bridge not usable"
ok "bridge shows its password prompt"
[[ "$(adb get-state 2>/dev/null)" == "device" ]] || prereq "no device on adb"
ok "adb device present"
[[ "$(as_root 'id -u')" == "0" ]] || prereq "no root over adb ($ROOT sh -c 'id -u' is not 0)"
ok "root via $ROOT"

head_ "misc partition"
as_root "rm -f $STAGE/bcb.img $STAGE/misc.before $STAGE/misc.after" >/dev/null
resolved=$(as_root "readlink -f $MISC")
[[ "$resolved" == "$MISC_DEV" ]] || stop "misc resolves to '$resolved', expected $MISC_DEV"
ok "misc is $MISC_DEV"
sectors=$(as_root "cat /sys/class/block/${MISC_DEV##*/}/size")
[[ "$sectors" == "$MISC_SECTORS" ]] || stop "misc is '$sectors' sectors, expected $MISC_SECTORS"
ok "misc is $MISC_BYTES bytes"
as_root "dd if=$MISC of=$STAGE/misc.before bs=4096 count=256" >/dev/null 2>&1 \
    || stop "could not read misc"
pull_verified "$STAGE/misc.before" "$LOGDIR/misc.before" || stop "misc dump did not pull intact"
ok "misc dump pulled, hash matches device"
python3 "$HERE/bcb.py" check-zero "$LOGDIR/misc.before" \
    || stop "misc is not all zero; something else wrote it, find out what before going on"
ok "misc is all zero before the write"

head_ "build and stage the BCB"
python3 "$HERE/bcb.py" build >"$LOGDIR/bcb.img" || stop "bcb.py build failed"
python3 "$HERE/bcb.py" parse <"$LOGDIR/bcb.img" || stop "built BCB is not SAFE"
ok "built BCB parses SAFE"
adb push "$LOGDIR/bcb.img" "$STAGE/bcb.img" >/dev/null 2>&1 || stop "push failed"
[[ "$(host_sha "$LOGDIR/bcb.img")" == "$(dev_sha "$STAGE/bcb.img")" ]] \
    || stop "staged BCB hash does not match the host copy"
ok "staged copy hash matches"

if [[ "$DRY" == 1 ]]; then
    echo
    echo "DRY RUN: stopping before the write. $PASS passed, $FAIL failed. Logs: $LOGDIR"
    exit 0
fi

head_ "UART capture"
# One client at a time on the bridge, so log in now and hold it through the reboot.
rm -f "$LOGDIR/capture.ready"
python3 "$HERE/uart.py" capture "$LOGDIR/uart-boot.log" --seconds 600 \
    --until "$MARK_INIT" --after 20 --ready-file "$LOGDIR/capture.ready" \
    >"$LOGDIR/capture.out" 2>&1 &
CAP_PID=$!
for _ in $(seq 1 30); do
    [[ -f "$LOGDIR/capture.ready" ]] && break
    kill -0 "$CAP_PID" 2>/dev/null || break
    sleep 1
done
[[ -f "$LOGDIR/capture.ready" ]] || { cat "$LOGDIR/capture.out"; stop "UART capture did not reach the live console"; }
ok "capturing to $LOGDIR/uart-boot.log"

if [[ "$YES" != 1 ]]; then
    echo
    read -r -p "Write the BCB to $MISC_DEV (misc) now? Type 'write' to go on: " answer
    [[ "$answer" == "write" ]] || stop "not confirmed"
fi

head_ "write"
# Toybox dd refuses conv=fsync and writes nothing, so plain dd, then sync.
WRITTEN=1
out=$(as_root "dd if=$STAGE/bcb.img of=$MISC bs=2048 count=1; echo dd_rc=\$?; sync" 2>&1)
echo "$out" | grep -q '^dd_rc=0$' || stop "dd did not report success: $out"
ok "dd bs=2048 count=1 exited 0, sync done"

head_ "readback"
as_root "dd if=$MISC of=$STAGE/misc.after bs=4096 count=256" >/dev/null 2>&1 \
    || stop "could not read misc back"
pull_verified "$STAGE/misc.after" "$LOGDIR/misc.after" || stop "readback did not pull intact"
ok "readback pulled, hash matches device"
head -c 2048 "$LOGDIR/misc.after" | cmp -s - "$LOGDIR/bcb.img" \
    || stop "first 2048 bytes of misc differ from the staged image"
ok "first 2048 bytes equal the staged image"
python3 "$HERE/bcb.py" check-misc "$LOGDIR/misc.after" \
    || stop "misc readback is not a SAFE BCB followed by zeros"
ok "readback parses SAFE and the rest of misc is zero"

head_ "reboot"
# Plain reboot from a shell, the path verified on 2026-10-25. Not `adb reboot recovery`.
adb shell reboot >/dev/null 2>&1
echo "  reboot sent; waiting for the capture (up to 10 minutes)"
wait "$CAP_PID"; cap_rc=$?
CAP_PID=
cat "$LOGDIR/capture.out"
if [[ "$cap_rc" == 0 ]]; then ok "capture saw the recovery marker"; else bad "capture exited $cap_rc"; fi
if grep -qF "$MARK_UBOOT" "$LOGDIR/uart-boot.log"; then ok "U-Boot: $MARK_UBOOT"; else bad "U-Boot recovery line not in the log"; fi
if grep -qF "$MARK_INIT" "$LOGDIR/uart-boot.log"; then ok "init: $MARK_INIT"; else bad "init recovery line not in the log"; fi

echo
echo "$PASS passed, $FAIL failed. UART log: $LOGDIR/uart-boot.log"
if [[ "$FAIL" == 0 ]]; then
    echo "Recovery booted per UART. The screen shows its menu; a human confirms that."
    echo "Next: python3 $HERE/recovery-console.py         (read-only probes)"
    echo "      python3 $HERE/recovery-console.py --reboot (busybox reboot -f, back to Android)"
fi
revert_text
[[ "$FAIL" == 0 ]]
