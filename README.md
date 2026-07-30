# Android Projector Toolkit

Tools for bypassing security restrictions on locked Android projectors and installing custom launchers.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Scripts](#scripts)
- [Documentation](#documentation)
- [Tested Devices](#tested-devices)
- [Safety](#safety)
- [If the projector stops booting: the `wtprovision` brick](#if-the-projector-stops-booting-the-wtprovision-brick)
- [Emergency Recovery](#emergency-recovery)
- [Contributing](#contributing)
- [License](#license)

## Overview

Fixes Android projectors that won't let you install apps or change launchers. Creates a complete device backup and safely replaces the locked stock launcher with [Projectivy](https://github.com/spocky/miproja1), or another launcher of your choice.

## Quick Start

```bash
./scripts/PROJECTOR.sh
```

That is the whole thing. It finds the projector, shows what state it is in, and
walks you through backup → verify → unlock, with a progress bar for the 15-minute
backup. Nothing is done without asking.

```
  NL5H00X Projector Toolkit
  -----------------------------------------------------------
  device       NL5H00X_TP   root: yes
  backup       verified  7.65 GB   projector-backup-20260728_054611
  launcher     locked     stock launcher
  -----------------------------------------------------------

  [1] Back up the device again  ~13 min
  [2] Unlock the launcher
  [3] Restore the stock launcher
  [4] Detailed unlock state
  [5] Refresh
  [q] Quit

  > 1
```

The backup runs behind a live view rather than fifteen minutes of nothing:

```
  Backing up  NL5H00X_TP
  -----------------------------------------------------------
  [########################................]  62%

  pulled     4.74 GB / 7.65 GB
  block      18 of 29
  rate       10.4 MB/s   4 min left
  stalls     3 killed and retried  expected on this device
  -----------------------------------------------------------
  [INFO]   56%  4.28 GB / 7.65 GB
  [WARN] Transfer stalled 30s at 4.41 GB - killing it
  [WARN] Block at 4.41 GB: got 113156093 bytes, wanted 268435456 (try 1/3)
  [INFO]   62%  4.74 GB / 7.65 GB

  the backup keeps running even if you close this
```

`stalls killed` is normal on this hardware, not a warning sign — the remote
`dd` gets reaped periodically and each block is simply retried. A run that
shows three of them still produces a byte-exact image.

The individual scripts still work on their own if you prefer them, or want to
script against them:

```bash
./scripts/TOOLS.sh               # opens hidden settings screens; no root needed
./scripts/MAKE_BACKUP.sh         # full device image, resumable
./scripts/UNLOCK.sh --status     # what is applied; changes nothing
./scripts/UNLOCK.sh --apply-all
```

## Unlocking the launcher

The projector ships locked to `com.newlink.hisilauncher` and will not let you
change the home screen from Settings. `UNLOCK.sh` fixes that.

```bash
./scripts/UNLOCK.sh              # interactive menu
./scripts/UNLOCK.sh --status     # what is and is not applied; changes nothing
./scripts/UNLOCK.sh --apply-all  # do everything, then stop
./scripts/UNLOCK.sh --revert     # put the stock launcher back
```

**Copying a launcher APK into `/system/app` is not enough** — the package must
also win the home intent. But **do not get there by disabling anything.**

> ### Corrected 2026-07-30 — the previous advice here bricked a device
>
> This section used to say the stock launcher "re-claims the home screen on the
> next boot", so the unlock should disable it first and set the home activity
> second — "that ordering is the whole trick". **Both halves were wrong.**
>
> `com.newlink.hisilauncher` never wins HOME on its own. This firmware dispatches
> home as `MAIN` + `HOME` + **`SETUP_WIZARD`**, and the only component declaring
> `SETUP_WIZARD` is `com.newlink.wtprovision/.MainActivity` — it wins uniquely and
> then starts the stock launcher by explicit component name.
>
> Disabling that dispatcher leaves the intent with **zero** candidates, and the
> device stops booting: no home resolves → no activity starts → nothing goes idle
> → `finishBooting()` never runs → `sys.boot_completed` is never set. Wi-Fi, adb
> and recovery all disappear with it. Recovering ours took a soldered UART
> console. See [docs/BOOT_DEADLOCK.md](docs/BOOT_DEADLOCK.md).

**Change the launcher with a preference, never with a disable.** Leave
`wtprovision` enabled — it stays as the fallback, so a preference that ever goes
stale degrades to "boots to the stock launcher" instead of "does not boot".

The most reliable route is the system's own chooser: with a second launcher
installed, press HOME and pick it. Android then writes a preference recorded
against the *real* intent (including `SETUP_WIZARD`) with the correct candidate
set. `pm set-home-activity` is weaker — it reports `Success` without refreshing
the recorded candidate set, and a stale set resolves to nothing.

Verify before rebooting. This must name your chosen launcher, not `No activity found`:

```bash
adb shell 'su 0 pm resolve-activity --brief \
  -a android.intent.action.MAIN \
  -c android.intent.category.HOME \
  -c android.intent.category.SETUP_WIZARD'
```

Projectivy running as the home screen after a clean boot, with `wtprovision`
left enabled:

![Projectivy running as the launcher](assets/hardware/projectivy-running.jpg)

What it does, one step at a time — each is checked by reading the value back
off the device, not by trusting the command's exit code:

| Step | Change |
|------|--------|
| `dev_options` | Developer options on, install from unknown sources allowed |
| `launcher_present` | Projectivy installed (skipped if you already have it) |
| `launcher_default` | Stock launcher disabled, Projectivy set as home |
| `cleanup_leftovers` | Removes empty/duplicated folders from earlier attempts |

Safety behaviour worth knowing:

- Refuses to run on anything that is not an NL5H00X.
- Refuses to change anything without a verified backup (`--status` is exempt).
- Re-running it is a no-op; it reports what was already done.
- **The stock launcher is only disabled after the replacement has been seen to
  run.** Being installed is not the same as working — a launcher that crashes
  on start still appears in `pm list packages`, and disabling the stock one on
  that basis is how you end up with no home screen at all. So the new launcher
  is started and checked to still be alive before anything is taken away.
- If the stock launcher cannot be disabled, it re-enables it rather than
  leaving you with no home screen at all.
- `--revert` restores the stock launcher, and that too is verified.

Restart the projector afterwards for the new home screen to appear.

### Why Projectivy

The projector is driven by a remote, not a touchscreen. Projectivy is a
leanback launcher: it declares `LEANBACK_LAUNCHER`, lays out for a D-pad, and
is built for exactly this class of device. Nova — which an earlier attempt left
sitting in `/system/app` — is a phone launcher, workable with a mouse and
awkward with the remote that comes in the box.

The APK is taken from the developer's own GitHub releases rather than a mirror,
and its package, SDK range, ABIs and signing certificate are recorded in
[`apks/PROVENANCE.md`](apks/PROVENANCE.md). If you already installed Projectivy
from Google Play, keep it — `launcher_present` sees it and does nothing.

Nothing hardcodes Projectivy. To use a different launcher:

```bash
LAUNCHER_PKG=com.teslacoilsw.launcher \
LAUNCHER_NAME=Nova \
LAUNCHER_APK_GLOB='nova-launcher*.apk' \
  ./scripts/UNLOCK.sh --apply-all
```

The home activity is never hardcoded either — it is resolved off the device by
asking which component actually handles `CATEGORY_HOME`, so a launcher that
renames its activity between releases does not break anything.

## Features

- **Hidden Settings Access** - Unlock manufacturer-restricted features without modifications
- **Complete Backup** - 7GB+ forensic device image with chunked storage support
- **Custom Launcher** - Replace the locked stock launcher with Projectivy, Nova, or another launcher (requires root)

## Scripts

| Script | Purpose | Root Required |
|--------|---------|---------------|
| [`PROJECTOR.sh`](scripts/PROJECTOR.sh) | **Start here** — guided interface over everything below | Depends |
| [`TOOLS.sh`](scripts/TOOLS.sh) | Open hidden settings screens; can also reset the home screen | No |
| [`MAKE_BACKUP.sh`](scripts/MAKE_BACKUP.sh) | Create complete device backup | Yes |
| [`UNLOCK.sh`](scripts/UNLOCK.sh) | Replace the locked stock launcher | Yes |

## Documentation

| Document | Description |
|----------|-------------|
| [Technical Notes](docs/TECHNICAL_NOTES.md) | Device analysis, ADB commands, partition layout |
| [Security Analysis](docs/SECURITY_ANALYSIS.md) | Detailed security restriction analysis |
| [Docs README](docs/README.md) | Documentation overview |

## Tested Devices

| Device | Android | Status |
|--------|---------|--------|
| Newlink NL5H00X | 9 | Tested |

## Repository Structure

```
scripts/
  PROJECTOR.sh          # Guided interface -- start here
  TOOLS.sh              # Access hidden features
  MAKE_BACKUP.sh        # Complete device backup
  UNLOCK.sh             # Launcher unlock, interactive CLI
  lib/
    common.sh           # Shared functions
    unlock.sh           # Unlock steps (state/apply/revert per step)
tests/
  run-tests.sh          # Backup regression suite
  unlock-tests.sh       # Unlock end-to-end suite
  ui-tests.sh           # TOOLS.sh and PROJECTOR.sh front ends
  fake-adb/adb          # Emulated projector -- no hardware needed
  device-emu/seed.sh    # Seeds the emulator from measured firmware values
docs/
  TECHNICAL_NOTES.md    # Technical documentation
  SECURITY_ANALYSIS.md  # Security analysis
  README.md             # Docs overview
apks/
  projectivy-launcher-4.71.apk   # installed by default
  nova-launcher-7.0.57.apk       # fallback, via LAUNCHER_* overrides
  PROVENANCE.md                  # where each came from and what was verified
assets/
  img1.png              # Console demo
```

## Safety

- **Backup required** - Modification scripts require complete backup first
- **Root needed** - System modifications require existing root access
- **Voids warranty** - Use at your own risk

## If the projector stops booting: the `wtprovision` brick

**Never disable `com.newlink.wtprovision/.MainActivity`.** It is not a launcher and
it is not optional. Disabling it stops this projector from booting, and it takes
every remote channel down with it. This is the single most destructive thing you
can do to an NL5H00X short of writing a bad image.

### Why it bricks

This firmware does not dispatch the ordinary home intent. It adds a second
category:

```
act=android.intent.action.MAIN
cat=[android.intent.category.HOME, android.intent.category.SETUP_WIZARD]
```

Exactly one component on the device declares `SETUP_WIZARD` alongside `HOME`:
`com.newlink.wtprovision/.MainActivity`. It wins the home intent uniquely and then
starts `com.newlink.hisilauncher` by explicit component name. That is the vendor's
designed boot path — the stock launcher is *started by* wtprovision, it does not
win HOME on its own.

Disable that one component and `ActivityManagerService.systemReady()` logs:

```
E ActivityManager: No home screen found for Intent { act=android.intent.action.MAIN
    cat=[android.intent.category.HOME,android.intent.category.SETUP_WIZARD] flg=0x100 }
```

and then deadlocks:

> no home activity resolves → no activity ever starts → nothing ever goes idle →
> `finishBooting()` is never called → `sys.boot_completed` is never set → user 0
> stays in `BOOTING` → components of non-direct-boot-aware apps stay filtered out
> of resolution → still no home.

`android.intent.category.SETUP_WIZARD` is also why Android's own `FallbackHome`
cannot rescue the boot by itself: `FallbackHome` declares `HOME` but not
`SETUP_WIZARD`, so it does not match the intent the firmware actually sends.

### Why you lose every channel at once

All of these are consequences of the same stall, not separate faults:

| Symptom | Cause |
|---|---|
| Stuck on the vendor logo forever | `bootanim` exits; the last frame is left on screen. It is frozen, not loading. |
| No Wi-Fi | The network stack never brings up saved networks because boot never completes. |
| No adb over network | Follows from the above. |
| No adb over USB | The chassis USB-A ports are **host** ports. A host cannot enumerate to your PC. The device-side USB footprint on the board is unpopulated. |
| Recovery unreachable | On the units seen so far, U-Boot accepts `reboot recovery` (`starting system with command 'recovery'`) and then boots the normal Android image anyway — there is no usable recovery partition. |

A device in this state still runs: `system_server` is alive, Bluetooth works, and
a serial console will give you a root shell. It looks dead and is not.

### Recovering it

If the device still answers adb, the toolkit does it for you:

```bash
./scripts/UNLOCK.sh --repair
```

It skips the usual device and backup checks on purpose — this failure leaves
neither — and with nothing on adb it prints the serial commands instead.

Otherwise you need the UART console. On the `NL-5H000-MAIN-V1` board the pads are two plated
through-holes labelled `TX RX` on the silkscreen, immediately to the right of the
4-pin speaker connector (`VOR+ VOR- VOL- VOL+`). There is no ground pad next to
them — take `GND` from the keypad connector (`LED-G LED-R KEY0-IN2 KEY0-IN1 GND`).
**115200 8N1**, no flow control, 3.3 V logic. You get `console:/ $`.

Root uses Android's `su`, not the GNU form:

```bash
su 0 id          # works
su -c id         # fails: "su: invalid uid/gid '-c'"
```

**Permanent fix — one command:**

```bash
su 0 pm enable com.newlink.wtprovision/.MainActivity
```

Verify before rebooting. This must return `wtprovision`, not "No activity found":

```bash
su 0 pm resolve-activity --brief \
  -a android.intent.action.MAIN \
  -c android.intent.category.HOME \
  -c android.intent.category.SETUP_WIZARD
```

**If you need the screen back before you fix it**, start Android's fallback home
explicitly. This breaks the deadlock for the current boot: an activity finally
starts, boot completes, the user unlocks, Wi-Fi and adb come back.

```bash
su 0 am start -n com.android.tv.settings/.system.FallbackHome
```

Do not expect `am start` on a launcher to work while the device is stuck. During
`BOOTING`, component resolution is filtered and both
`com.newlink.hisilauncher/.MainActivity` and `.WizardAciticity` answer
`Activity class ... does not exist`, even though `pm list packages` shows the
package installed. Check `su 0 dumpsys user | grep -i State` first — if it reads
`BOOTING`, only a direct-boot-aware component such as `FallbackHome` can be
started.

### Diagnosing it yourself

`pm list packages -d` lists disabled **packages** and will show nothing here — the
package is enabled and only one **component** is disabled. Ask the right question:

```bash
su 0 dumpsys package com.newlink.wtprovision | grep -A3 disabledComponents
```

Boot progress markers tell you how far the system got. A healthy boot ends with
`boot_progress_enable_screen`; this brick stops right after
`boot_progress_ams_ready`:

```bash
su 0 logcat -d -b events | grep boot_progress
```

Note that `load average` near 8.0 with no process using CPU is **normal** on this
SoC — those are HiSilicon kernel monitor threads parked in uninterruptible sleep.
It is not evidence of failing storage.

## Emergency Recovery

```bash
# Put the stock launcher back (the supported way -- it verifies the result)
./scripts/UNLOCK.sh --revert

# By hand, if you cannot run the script. Note that this alone does not
# survive a reboot while the stock launcher is disabled.
#
# The component is .WizardAciticity, spelled exactly like that in the firmware.
# .MainActivity is the screen you actually see, but it carries no HOME filter,
# so set-home-activity rejects it. Ask the device rather than trusting either:
adb shell 'echo "pm enable com.newlink.hisilauncher" | su'
adb shell cmd package query-activities --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell cmd package set-home-activity com.newlink.hisilauncher/.WizardAciticity
```

Full restore from the image is a different matter. `RESTORE.sh` is **generated
by `MAKE_BACKUP.sh` into the backup directory** -- it is not in `scripts/` --
so run it from there:

```bash
cd projector-backup-<timestamp>/
./RESTORE.sh
```

It refuses to write a full-device image that does not match `backup-manifest.txt`,
and refuses outright if the manifest is missing. Restoring a short image over
the whole device is how a projector stops booting.

## Development without a projector

The whole toolkit runs against an emulated device, so changes can be tested
without touching hardware — which matters when the thing under test is "the
backup you would restore from" or "the launcher you need to boot".

```bash
bash tests/run-tests.sh      # backup suite
bash tests/unlock-tests.sh   # unlock suite
bash tests/ui-tests.sh       # TOOLS.sh and PROJECTOR.sh
```

The UI suite runs the front ends through `/bin/bash` rather than whatever
`bash` resolves to on `$PATH`, because that is what the shebang picks. macOS
still ships bash 3.2, and testing against a newer bash from Homebrew hid a
`local -n` that broke `TOOLS.sh` outright for every Mac user.

The emulator is seeded from values measured on a real NL5H00X: its
`build.prop`, its `/system/app` inventory, piped-`su` only (`su -c` is
rejected, as on the device), `/system` mounted read-only, and a boot that
re-asserts the stock launcher while it is enabled. It **refuses what the
device refuses**, so an unlock that forgets to remount `/system` or forgets to
disable the stock launcher fails there too.

To drive the scripts against your own pulled firmware instead of the stand-in:

```bash
export FAKE_ADB_STATE=/tmp/fakedev
mkdir -p "$FAKE_ADB_STATE/sdcard"
cp projector-backup-*/full-system-backup.img "$FAKE_ADB_STATE/blockdev"
PATH="$PWD/tests/fake-adb:$PATH" ./scripts/TOOLS.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT License](LICENSE) - Educational use only.
