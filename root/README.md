# Root for apps — a socket daemon (proof of concept)

Giving an **app** root on this projector is not a matter of dropping a `su`
binary in place. This is the proof-of-concept that shows what actually works,
and why. It is for owners of this device modifying their own hardware.

**Status: proof of concept.** It has been built and verified on hardware — an
app-uid process with `NO_NEW_PRIVS` set gets root through the daemon, and an
unlisted app is refused — but it is **not yet wired into boot**. Making it
permanent (an `init.rc` service plus a hybrid `su` that keeps the shell/root
path working for the rest of the toolkit) is the next step and is not done here.

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

## Files

| File | What it is |
|---|---|
| `sud.c` | The root daemon: socket, `SO_PEERCRED` gate, allow-list, fd-passed exec |
| `suc.c` | The client (PoC subset) that talks to it |
| `privtest.c` | Diagnostic: sets `PR_SET_NO_NEW_PRIVS`, then execs — proves why setuid fails |
| `build.sh` | Builds all three for `armeabi-v7a` |

## Related

- See also: [docs/INSTALL_LOCKED.md](../docs/INSTALL_LOCKED.md) — the same device,
  the vendor's other lock, and why root does **not** fix installs.
- See also: [docs/BOOT_DEADLOCK.md](../docs/BOOT_DEADLOCK.md) — `system_root_image`
  and the ramdisk situation that also rules Magisk out.
