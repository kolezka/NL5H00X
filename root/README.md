# Root for apps — a socket daemon (proof of concept)

Giving an **app** root on this projector is not a matter of dropping a `su`
binary in place. This is the proof-of-concept that shows what actually works,
and why. It is for owners of this device modifying their own hardware.

**Status.** The daemon itself is built and verified on hardware: an app-uid
process with `NO_NEW_PRIVS` set gets root through it, and an unlisted app is
refused. It is now also wired into boot by an init service, and there is an
opt-in hybrid `su` that keeps the shell/root fast path the rest of the toolkit
depends on. Installing all of that is [`scripts/ROOT.sh`](../scripts/ROOT.sh),
covered below. The install path is green against the emulator; **the boot itself
has not been watched on hardware yet.**

## Why a setuid `su` cannot work here

The obvious approach — a setuid-root `su` that apps exec — fails on this device,
and the failure is not fixable by chmod or SELinux tweaks.

Zygote sets `PR_SET_NO_NEW_PRIVS` on every app process it spawns. With that flag
set, the kernel refuses to honour the setuid bit: an `execve` of a setuid binary
runs it with the caller's uid, not root. Measured on hardware:

```
# adb shell (no NO_NEW_PRIVS): setuid su elevates
$ su 2000 privtest plain su 0 id   ->  uid=0(root)

# with NO_NEW_PRIVS, as an app process is: setuid su cannot elevate
$ su 2000 privtest nnp   su 0 id   ->  su: setgid failed
```

`privtest` is the diagnostic that isolates exactly this: it optionally sets
`PR_SET_NO_NEW_PRIVS`, then execs whatever you give it. It is why we know the
setuid route is a dead end rather than a bug to chase — and it is the reason
every real root solution (Magisk, SuperSU, KernelSU) uses a daemon rather than a
setuid binary. Magisk itself cannot run here for an unrelated reason: both the
boot and the recovery image carry `ramdisk=0` in their Android headers, so
`magiskboot unpack` finds no cpio to inject into.

That header field is not the whole story, and the difference matters if anyone
picks this up again. `boot` genuinely has no ramdisk — its built-in initramfs is
the stock 462-byte empty cpio, and the kernel mounts `system` directly via
`root=/dev/mmcblk0p20`. `recovery` is the opposite: its ramdisk is real and
complete (20,690,944 B, 245 entries, with `init`, `sepolicy` and the UI images),
compiled into the kernel as a gzip blob rather than appended to the image. So
the recovery ramdisk exists — it is simply somewhere `magiskboot` does not look,
and replacing it means editing inside the zImage while preserving the region's
byte length.

## How the daemon works

The app never elevates itself. It asks a process that is **already** root to run
something on its behalf.

- **`sud`** — the daemon. Runs as root, listens on an abstract Unix socket
  (`@projector_su`). For each request it reads the caller's uid from
  `SO_PEERCRED` (kernel-supplied, unspoofable), resolves it to a package via
  `/data/system/packages.list`, and checks it against `/data/adb/su-allow`. If
  allowed, it forks a child that takes over the caller's stdin/stdout/stderr
  (passed as fds over `SCM_RIGHTS`), drops to the requested uid, and runs the
  command. No list, or an unlisted caller, is denied — it fails **closed**,
  because failing open silently roots every app on the device.

- **`suc`** — the client (PoC subset). Connects to the socket, hands over its
  three standard fds and the command, and returns the daemon's exit status. It
  needs no privilege of its own, which is exactly why it works where setuid does
  not. A real deployment replaces `/system/xbin/su` with a client that also
  keeps the direct fast-path for shell/root callers.

```
app (uid 10031, NO_NEW_PRIVS)                       sud (root)
   suc -c id  ──connect @projector_su──►  SO_PEERCRED → uid 10031
              ──stdin/out/err (SCM_RIGHTS), "id"──►    on su-allow? yes
                                                        fork → setuid(0) → exec
              ◄──────────── exit status ──────────      run as root
```

## Build

```bash
NDK=/path/to/android-ndk ./build.sh    # or let it find the newest NDK
```

This device is 32-bit `armeabi-v7a` only; the build targets exactly that.

## Try it (nothing persistent)

Everything lives in `/data/local/tmp` and a manually started daemon — a reboot
clears it, and `/system` is never touched.

```bash
adb push sud suc privtest /data/local/tmp/
adb shell 'chmod 755 /data/local/tmp/{sud,suc,privtest}'

# allow-list: one package per line, root-only so an app cannot add itself
adb shell 'su 0 sh -c "mkdir -p /data/adb; chmod 700 /data/adb;
  printf com.spocky.projengmenu\\\\n > /data/adb/su-allow; chmod 600 /data/adb/su-allow"'

# start the daemon as root
adb shell 'su 0 sh -c "nohup /data/local/tmp/sud >/data/local/tmp/sud.log 2>&1 &"'

# an allowed app uid, with NO_NEW_PRIVS set, gets root:
adb shell 'su 10031 /data/local/tmp/privtest nnp /data/local/tmp/suc 0 -c id'
#   -> uid=0(root) ...

# an unlisted app uid is refused:
adb shell 'su 10029 /data/local/tmp/privtest nnp /data/local/tmp/suc 0 -c id'
#   -> sud: uid 10029 (com.apkpure.aegon) not allowed
```

Tear down by killing `sud`; the binaries and `/data/adb/su-allow` are the only
traces, and a reboot removes the daemon regardless.

## Making it persistent

Two pieces turn the PoC above into something that is still there after a reboot.

**`sud.rc`**, an init service that starts the daemon at boot:

```
service sud /system/xbin/sud
    class late_start
    user root
    seclabel u:r:su:s0
```

The `seclabel` line is not optional and not decoration. AOSP pie init
(`system/core/init/service.cpp`, `ComputeContextFromExecutable`) rejects a
service whose executable has no policy-defined domain transition, and it returns
that error *before* fork. It is a policy computation, not an AVC decision, so
SELinux Permissive does not bypass it. `u:r:su:s0` is used because this firmware
is userdebug and Permissive, where the `su` domain exists. Name a domain the
device's policy does not define and init logs an error, the service never
starts, and boot continues normally. The failure mode is a missing daemon.

The service is deliberately not `oneshot`, so init restarts `sud` about five
seconds after a crash.

**`su.c`**, a hybrid `su` that keeps both callers working. It dispatches on its
own uid, because that is what decides whether it can elevate at all:

- **uid 0 or 2000 (`AID_SHELL`)** have no `NO_NEW_PRIVS`, so the stock setuid
  `su` still works. It is exec'd unchanged with argv untouched, which keeps the
  behaviour byte-identical to stock for every script in this toolkit. The stock
  binary is preserved as `/system/xbin/su_orig` and is never deleted.
- **any other uid** is an app, where setuid is already neutralised. The request
  goes to `sud` over the socket, same as `suc`.

Both clients share one implementation of the wire protocol in `suclient.c`, so
they cannot drift apart.

Installing it is [`scripts/ROOT.sh`](../scripts/ROOT.sh), which handles the
`/system` remount, the hashes, the allow-list and the revert path:

```bash
NDK=/path/to/android-ndk ./build.sh
../scripts/ROOT.sh --status
../scripts/ROOT.sh --apply-all              # daemon + service + allow-list
../scripts/ROOT.sh --apply-all --with-su    # and the hybrid su, opt-in
```

The hybrid `su` is opt-in because it replaces the channel the rest of the
toolkit runs on. `ROOT.sh` stages it to a separate path, proves `su 0 id` still
returns uid 0 through that path, and only then promotes it.

`bash ../tests/root-tests.sh` exercises all of this against the emulator,
including a hybrid that fails live-verify and must leave the live `su` alone.

## What root gets you

Two different things are called "root" here, and they are worth keeping apart.

**Shell root** is what `su 0 <command>` in an adb shell gives you. It exists on
the stock firmware — the daemon does not create it, and everything in this
section works before `ROOT.sh` has ever run. Note the form: this device takes
`su <uid> <command>`, not `su -c`. `su -c 'id'` answers `invalid option -- c`.

**App root** is what `sud` adds: an app you put on the allow-list can run one
command as uid 0 through the socket. Nothing else changes for that app.

The examples below are run by the **ROOT** section of
[`scripts/TOOLS.sh`](../scripts/TOOLS.sh), which does the same work with the
read-back checks already in place. The raw commands are here so you can see what
the menu actually does.

### Read what an app hides

App data lives under `/data/data/<pkg>` with mode 700. As `shell` you get
`Permission denied`; as root you can read it, and copy it off with `exec-out` so
binary content survives.

```bash
su 0 ls /data/data/com.newlink.hisilauncher/shared_prefs
su 0 cat /data/system/packages.list          # uid -> package, what sud reads
adb exec-out "echo 'cat /data/data/<pkg>/databases/app.db 2>/dev/null' | su" > app.db
```

Hash the result against the device before you trust it — `adb pull` of a
root-only path reports success and gives you nothing.

### Freeze the vendor apps that keep waking up

`pm disable-user` survives reboots, keeps the APK installed, and is undone with
`pm enable`. It is the safe alternative to deleting anything from `/system`.

```bash
su 0 pm disable-user --user 0 com.apkpure.aegon
su 0 pm list packages -d                     # what is frozen right now
su 0 pm enable com.apkpure.aegon
```

**Do not freeze `com.newlink.wtprovision`.** It is the only package that owns
MAIN + HOME + SETUP_WIZARD on this firmware, and freezing it stops the boot
before adb and Wi-Fi come up. Recovery is a USB job. `TOOLS.sh` refuses that
package outright, along with the launcher, TV settings, SystemUI and `android`.

### Set properties, and get ADB over Wi-Fi

`setprop` on a service property and `start` / `stop` both fail as `shell` with
`must be root`, while every command around them still succeeds.

```bash
su 0 setprop service.adb.tcp.port 5555
su 0 stop adbd && su 0 start adbd
adb connect <projector-ip>:5555              # unplug the cable after this
su 0 setprop service.adb.tcp.port -1         # off again
```

The property is not persistent: a reboot turns it back off. Restarting `adbd`
drops the current connection for a second, so re-check that root still answers
afterwards rather than reading the silence as "it did not work".

### Write `/system`

This is a system-as-root device: `/system` is a directory on `/`, so the remount
targets `/` and `mount -o remount,rw /system` answers `not in /proc/mounts`.

```bash
su 0 mount -o remount,rw /
su 0 cp /data/local/tmp/staged /system/app/Foo/Foo.apk
su 0 mount -o remount,ro /
```

`adb push` straight into `/system` reports bytes written and changes nothing.
Stage in `/data/local/tmp`, copy as root, then compare `sha256sum` on both ends.

### Read a partition

Whole-device and single-partition dumps are a root read of a block device. Use
`bs=4096`; toybox `dd` rejects `bs=1M` and leaves a 0-byte file that looks like a
success.

```bash
su 0 ls -l /dev/block/platform/soc/f9830000.emmc/by-name/
adb exec-out "echo 'dd if=/dev/block/by-name/logo bs=4096 2>/dev/null' | su" > logo.img
```

[`scripts/MAKE_BACKUP.sh`](../scripts/MAKE_BACKUP.sh) already does the full-device
version, with the size assertion and the hash.

### What an app on the allow-list can do

```bash
./scripts/TOOLS.sh            # ROOT -> "Give an app root"
# or, by hand:
su 0 sh -c "echo com.example.app >> /data/adb/su-allow"
```

`sud` re-reads that file on every request, so the change is live with no reboot.
From then on the app can run a command as root through `suc` (or the hybrid
`su`): a shell script, a `pm` call, a write to `/system`. This is the whole point
of the daemon — an app process has `NO_NEW_PRIVS` set and cannot elevate itself
by any other route on this firmware.

Treat the allow-list as a list of apps you are handing the device to. An allowed
app can read every other app's data, write `/system` and stop the projector
booting.

### What root does not get you

- **Normal installs still fail.** `pm install` and the package installer are
  locked by the vendor and root does not lift it. Apps go to `/system/app`. See
  [docs/INSTALL_LOCKED.md](../docs/INSTALL_LOCKED.md).
- **No Magisk, no modules, no systemless anything.** Both boot and recovery carry
  `ramdisk=0`; see above and [docs/BOOT_DEADLOCK.md](../docs/BOOT_DEADLOCK.md).
- **The stock launcher still wins the boot intent** unless the home preference is
  set the way [`scripts/UNLOCK.sh`](../scripts/UNLOCK.sh) sets it. That is an
  intent-resolution problem, not a permission one.

## Files

| File | What it is |
|---|---|
| `sud.c` | The root daemon: socket, `SO_PEERCRED` gate, allow-list, fd-passed exec |
| `suc.c` | The client (PoC subset) that talks to it |
| `su.c` | The hybrid `su`: stock fast path for shell/root, daemon for app uids |
| `suclient.c`, `suclient.h` | The wire protocol, shared by `suc` and `su` |
| `sud.rc` | init service that starts `sud` at boot |
| `privtest.c` | Diagnostic: sets `PR_SET_NO_NEW_PRIVS`, then execs — proves why setuid fails |
| `build.sh` | Builds all of them for `armeabi-v7a` |

## Related

- See also: [docs/INSTALL_LOCKED.md](../docs/INSTALL_LOCKED.md) — the same device,
  the vendor's other lock, and why root does **not** fix installs.
- See also: [docs/BOOT_DEADLOCK.md](../docs/BOOT_DEADLOCK.md) — `system_root_image`
  and the ramdisk situation that also rules Magisk out.
