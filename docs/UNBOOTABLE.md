# Projector will not boot: first steps

For an NL5H00X that stopped booting after a modification: a flashed `boot.img`,
a Magisk attempt, a disabled component, a bad restore. It gets you a serial
console and a boot log, and tells you what the log means.

It does **not** contain a verified way to write a stock `boot.img` back to a
device whose kernel no longer starts. This repo has not done that on this board yet.
The steps below get you to the point where that becomes a concrete, answerable
question instead of a guess.

---

## Step 0: stop and keep what you have

- **Do not flash anything else.** Each extra write makes the log harder to read
  and can overwrite the thing you need to restore.
- **Find the original `boot.img`.** Magisk patches a copy of the image you gave
  it. That unpatched file is the only stock boot image most people have. Copy it
  somewhere safe now.
- If you ran `./scripts/MAKE_BACKUP.sh` before, keep that
  `projector-backup-*` directory. It holds a full image of the internal storage.

### If you tried Magisk

Magisk cannot work on this device. Both `boot` and `recovery` carry
`ramdisk=0` in their headers. The kernel has no real ramdisk and mounts
`/system` directly from `root=/dev/mmcblk0p20`, so `magiskboot` has nothing to
patch. An image it produced is probably not bootable. Details:
[root/README.md](../root/README.md). For root on this device, use the `sud`
daemon described there instead.

## Step 1: note what the projector does

Write down exactly what you see when you press power. It decides where to look.

| What you see | Likely stage | Where to go |
|---|---|---|
| Vendor logo, then stuck forever. No Wi-Fi, no adb. | Android is running but never finishes booting. | [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) first. Still needs UART unless adb happens to work. |
| Red LED, no logo, nothing on screen. | Earlier: bootloader or kernel. | Steps 2 to 6 below. |
| Anything else | Unknown | Steps 2 to 6 below. |

"Likely" is the honest word. The screen alone cannot tell these apart. The
serial log can.

### Red LED: is the power button broken?

Probably not, though this is reasoning, not something measured on this board.
On HiSilicon TV chips, standby and wake-up (front button, IR remote) are
usually handled by a small separate controller, not by the Android kernel. A
flashed `boot.img` replaces only the kernel. The more likely story: the button
wakes the board, the bootloader tries to start the broken kernel, fails, and
the board falls back to standby or hangs. The LED stays red because nothing gets
far enough to change it.

The screen cannot tell "button ignored" from "button works, kernel fails". The
serial log in step 6 can.

Cheap things to try first, none verified on this model:

- The power button on the IR remote. Same wake path, so it will likely act the
  same, but it costs nothing.
- Unplug the power for a minute and plug it back in. Some boards start fully
  on power-up instead of going to standby.

Do not short `KEY0-IN1` or `KEY0-IN2` to ground to fake a button press. They
may be analog inputs reading a resistor ladder, and they only duplicate the
real button anyway.

## Step 2: what you need

- A USB to UART adapter with **3.3 V** logic (CP2102, CH340, FT232 or similar).
  A 5 V adapter can damage the SoC.
- A soldering iron and three thin wires, or pin headers.
- A terminal program: `picocom` or `screen` on Linux and macOS, PuTTY on Windows.

Opening the case is not documented here yet.

## Step 3: find the pads

Board `NL-5H000-MAIN-V1`, SoC Hi3751v352F, Android 9.

![NL-5H000-MAIN-V1 mainboard](../assets/hardware/board-overview.jpg)

`TX` and `RX` are two plated through-holes at the top right, immediately to the
right of the 4-pin speaker connector (`VOR+ VOR- VOL- VOL+`).

![UART TX/RX pads close-up](../assets/hardware/uart-pads-txrx-closeup.jpg)

There is **no ground pad** next to them. Take `GND` from the keypad connector:
`LED-G  LED-R  KEY0-IN2  KEY0-IN1  GND`.

## Step 4: wire it

| Adapter | Board |
|---|---|
| `GND` | `GND` on the keypad connector |
| `RX` | `TX` |
| `TX` | `RX` |
| `VCC` / `3V3` / `5V` | **not connected** |

TX goes to RX: what one side sends, the other receives. If you later see
nothing at all, swapping the two data wires is safe and is the first thing to
try.

Leave the projector unplugged while soldering.

## Step 5: prove the adapter works before you trust it

A silent terminal can mean a dead board or a broken measurement. Rule out the
second one first.

1. Disconnect the adapter from the board.
2. Join the adapter's own `TX` and `RX` with a wire.
3. Open the port (below) and type. Every key must appear on screen.
4. If it does not, the problem is the adapter, driver or port settings, not the
   projector.

Then reconnect it to the board.

Port settings: **115200 baud, 8N1, no flow control.**

```bash
# Linux
picocom -b 115200 --logfile boot.log /dev/ttyUSB0

# macOS
screen -L /dev/cu.usbserial-XXXX 115200   # log goes to ./screenlog.0
```

On macOS, read the pitfalls in
[BOOT_DEADLOCK.md](BOOT_DEADLOCK.md#macos-serial-pitfalls) before concluding
anything. Two of them look exactly like dead hardware: `stty -f` resetting the
baud to 9600, and a shell alias turning `cat` into something that buffers.

What an idle line looks like:

- **Silence** is normal while the board is off or idle.
- **A flood of `0x00` bytes** means `RX` is shorted to ground. Fix the wiring.
- **A single `0xFF` or `0xFE`** when you open the port or type is noise. It
  proves nothing either way.

## Step 6: capture a boot log

**The console does not need the power button.** It is the SoC's own serial
port and works whenever the board has power. A red LED already means the board
has power. On HiSilicon boards the bootloader usually prints its first messages
the moment power is applied, before it decides to go to standby. So even if
the button does nothing at all, plugging in the power with UART connected
should still produce a log. That is typical for these chips, not yet confirmed
on this board.

Order matters here, so that the first messages are not missed.

1. Unplug the projector's power.
2. Connect the proven adapter to the board and start the terminal with logging.
3. Plug the power back in. Watch for output **before** pressing anything.
4. Wait 30 seconds, then press the power button.
5. Wait two minutes. Keep the whole log file.

Note in the issue whether output appeared at step 3, at step 4, or not at all.
Output at either step means the board is alive and the button question from
step 1 is answered.

### Optional: watch the current with a bench supply

The projector's own power supply is fine for everything above. A bench supply
does not power the board "harder". What it adds is a current reading, which
tells you whether the board reacts to the button even when the screen and the
log show nothing.

Before connecting it:

- **Read the voltage from the label on the original supply.** This repo does not
  document the board's power input. Do not assume 12 V.
- **Measure the original supply's plug** with a multimeter: voltage and which
  contact is positive. Wrong polarity or wrong voltage can destroy the board.
- **Set a current limit.** Start low, around 1 A, and raise it only if the
  supply hits the limit while the board is still starting.

Then:

1. Connect UART and start logging, as above.
2. Power the board from the bench supply at the original voltage. Note the
   current in standby.
3. Press the power button. Watch the current for 30 seconds.

How to read it (reasoning, not measured on this board):

| Current after pressing power | Likely meaning |
|---|---|
| Jumps up, then falls back to the standby value | The button works. The board starts and fails, probably at the kernel. |
| Jumps up and stays up | The board is running. Check the log; the screen may just stay dark. |
| Does not change | The board is not waking up. The button or the wake-up path is the problem. |
| Hits the current limit | Stop. Something draws far more than it should. |

Write the standby current and the peak current in the issue.

### Reading the log

Compare what you captured with this table.

| Log shows | What it means | Next |
|---|---|---|
| Nothing at all, adapter proven in step 5, wires swapped once, both at power-on and after the button | The board is not talking on these pads, or it dies before the first message. | Try the current check above to see if the board reacts at all. Then open an issue with photos of your wiring and the current readings. |
| Bootloader output that stops or loops, with no Linux kernel messages after it | The bootloader cannot start the kernel. A bad `boot` partition fits this. | Open an issue with the log. Restoring `boot` from here is not documented yet. |
| Linux kernel messages ending in a `Kernel panic` | The kernel starts but cannot continue. A patched or mismatched `boot.img` fits this. | Open an issue with the log. |
| A `console:/ $` prompt | Android is up. You have a shell and root with `su 0`. | Go to [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md#diagnosing-it) and follow the diagnosis. Do not write anything yet. |

The middle rows describe where boot stops, not a confirmed cause. This repo has
no log yet of a boot that fails before Android, so there are no known strings to
match against. Yours would be the first.

## Step 7: ask for help

Open an issue on this repository with:

- what you flashed or changed, and with which tool
- the full log from step 6 (`boot.log` or `screenlog.0`)
- whether you still have the original `boot.img`, and its size and SHA-256
  (`sha256sum boot.img` or `shasum -a 256 boot.img`)
- whether you have a `projector-backup-*` directory

Remove anything personal from the log before posting. It may contain your Wi-Fi
network name or the device serial number.

## See also

- [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md): the one brick with a verified fix, and
  the full serial console reference
- [root/README.md](../root/README.md): why Magisk cannot work here, and the root
  method that does
- [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md): partition layout
