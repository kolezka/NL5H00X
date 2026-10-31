# ESP32-C6 SuperMini projector UART bridge

This firmware turns the NL5H00X projector's 3.3 V UART into a password-gated TCP
console on the local network. The ESP32-C6 powers up with the projector, joins
Wi-Fi, and then forwards bytes both ways between TCP port 2323 and the UART.

This is the Android serial console (`console:/ $`), not ADB. adbd does not speak
over UART. To get ADB, use the console to start adbd on TCP and connect to the
projector's own Wi-Fi address:

```sh
su 0 setprop service.adb.tcp.port 5555
su 0 stop adbd
su 0 start adbd
```

```sh
adb connect <projector-ip>:5555
```

## Behaviour

- Joins the Wi-Fi network from `secrets.h` (30 s timeout).
- If that fails, starts the fallback AP. After 5 minutes on the AP with no
  client, it restarts and tries the station network again, so a router that
  boots slower than the projector does not leave the bridge stuck on the AP.
- Advertises `projector-uart.local` over mDNS. One client at a time.
- Keeps the last 16 KiB of projector output while nobody is connected and
  replays it after login.
- Client input reaches the projector only after the console password. After
  that the bridge is fully bidirectional.
- A stalled client is dropped instead of blocking UART capture. A silent Wi-Fi
  loss is detected by TCP keepalive in about 30 s.
- Prints its IP address on the USB serial port at boot (`pio device monitor`).

## Wiring

UART1 uses GPIO20 (RX) and GPIO19 (TX). GPIO16 is the C6 ROM log pin. Do not use
it for the projector, because the ROM writes boot text there before this firmware
runs. Also avoid GPIO8 (RGB LED), GPIO9 (BOOT) and GPIO15 (LED, strapping pin).

Projector line: 3.3 V, 115200 8N1, no flow control. The pads are `TX RX` right of
the speaker connector. GND comes from the keypad connector, see
[`docs/BOOT_DEADLOCK.md`](../docs/BOOT_DEADLOCK.md#serial-console-reference).

```text
Projector TX  ----------------> ESP32-C6 GPIO20 (UART1 RX)
Projector RX  <---------------- ESP32-C6 GPIO19 (UART1 TX)
IR VCC (3.3 V) ---------------- ESP32-C6 3V3
IR GND ------------------------ ESP32-C6 GND
```

Direct wires work: both sides use 3.3 V logic and share one supply. 1 kOhm in
series with each signal adds margin if you have resistors, but is not required.

The bridge stays powered while the projector sleeps, so an idle-high GPIO19 would
feed the unpowered SoC through its RX pin. The firmware prevents that. When the
projector's TX line stays low for 500 ms, it releases the UART and leaves GPIO19
as a high-impedance input. When the line goes high again, it reattaches. A
pull-down on GPIO20 makes an unpowered projector read as low instead of
floating.

If the projector ever stops at a bootloader prompt instead of booting, add
10 kOhm from GPIO19 to the ESP32 `3V3`: it holds the line idle while the ESP32
resets.

### Power

The chassis USB ports are out of reach, so the ESP32 takes its supply from the
VCC pin of the IR receiver connector (`GND IR VCC`, bottom centre of the board),
which carries 3.3 V. VCC goes to the SuperMini `3V3` pin, bypassing its regulator,
and the IR connector's GND to any SuperMini `GND` pin. That GND wire is also the
UART ground reference. Do not use the `5V` pin: 3.3 V there leaves about 3.0 V
after the regulator, and the ESP32 resets under Wi-Fi load.

The IR rail is also what the remote uses to wake the projector, and IR receivers
are often fed through a small filter resistor. To keep the ESP32 from pulling it
down:

- If you have one, put a 470 to 1000 µF electrolytic capacitor (6.3 V or more)
  across `3V3` and `GND` at the ESP32. Without it, watch for brownouts.
- The firmware caps Wi-Fi transmit power at 11 dBm to cut current peaks.
- The console banner shows uptime and the last reset reason. `BROWNOUT`, or an
  uptime that keeps resetting, means the supply is too weak.
- After the install, check that the remote still wakes the projector.

The IR rail probably stays live in standby, so the bridge keeps running while
the projector sleeps. Never connect USB-C while IR VCC is wired to `3V3`: the
board regulator and the projector rail would drive the same net. After the first
flash, update over Wi-Fi (see below). For a USB flash later, disconnect the `3V3`
wire first; GND, TX and RX can stay. Unplugging the projector from mains is not
enough, because USB power would then back-feed the projector's standby rail.

## Configuration

```sh
cd firmware
cp include/secrets.example.h include/secrets.h
```

Fill in the Wi-Fi SSID and password, a fallback AP password, a console
password and an OTA password. `secrets.h` is ignored by Git. The build refuses
empty or placeholder values, SSIDs longer than 32 characters, Wi-Fi passwords
outside 8 to 63 characters, and console or OTA passwords outside 12 to 64
characters.

## Build and flash

The project uses the pioarduino platform because the stock `espressif32`
platform has no Arduino core for the C6. `platformio.ini` overrides the board
profile's 8 MB flash to the 4 MB of the ESP32-C6FH4.

```sh
cd firmware
pio run
pio run --target upload        # the board shows up as /dev/cu.usbmodem*
pio device monitor             # shows the Wi-Fi IP after reset
```

Without a global PlatformIO install, prefix each command with
`uvx --from platformio`. If upload cannot reach the bootloader, hold BOOT, tap
RESET, then start the upload.

### Over Wi-Fi (OTA)

USB is needed only for the first flash. After that, the bridge accepts new
firmware on port 3232, protected by `OTA_PASSWORD`:

```sh
cd firmware
PROJECTOR_OTA_PASSWORD='same value as OTA_PASSWORD' pio run -e ota -t upload
```

Or from the browser: open `http://projector-uart.local/`, pick
`.pio/build/esp32-c6-supermini/firmware.bin` under **Firmware update**, enter the
OTA password and upload. The password travels as HTTP basic auth, readable on the
local network like the console password.

The upload drops the console client and pauses UART capture until the ESP32
restarts, about 20 s. If new firmware cannot join Wi-Fi, OTA is gone too: then
disconnect the `3V3` wire and flash over USB.

## Connect

```sh
nc projector-uart.local 2323
```

On the fallback AP, join it and use `nc 192.168.4.1 2323`. Enter the console
password, then press Enter once to get a prompt. Exit `nc` with `Ctrl-C`.

A status page runs at `http://projector-uart.local/`. It shows whether the
projector UART is sending data, byte counters, the console client, Wi-Fi signal,
uptime and the last reset reason, and refreshes every 2 s. It needs no password
and never shows UART content, so the console log stays behind the console
password. Raw values are at `/status.json`.

The password and all console traffic travel as plain TCP. Keep port 2323 on the
local network: no port forwarding, no tunnels, no public Wi-Fi.

## Safe first test

1. Solder only projector TX and GND. Leave GPIO19 unconnected.
2. Power the ESP32 from the Mac over USB. Connect with `nc` and log in.
3. Power the projector on. Success means readable boot text or
   `console:/ $`. An open socket or a byte count is not success. Garbled text
   means a wrong baud rate or a bad ground. A flood of `0x00` means RX is
   shorted to ground.
4. Only then solder GPIO19 to projector RX. Unplug USB, then wire IR VCC to
   `3V3`.
5. Restart the projector and confirm it still boots to the launcher. This proves
   the TX line does not interrupt the boot.
6. Connect, press Enter, and confirm the console answers.

## Portable tests

Host tests cover history replay, overflow eviction, chunked replay, network queue
wraparound and overflow, and password acceptance and rejection:

```sh
sh firmware/test/portable/run.sh
```
