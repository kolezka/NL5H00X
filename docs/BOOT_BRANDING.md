# Replacing what the projector shows at startup

**Summary:** startup is three independent stages — a U-Boot splash on the `logo`
partition, an unused `bootvideo` service, and an ordinary AOSP boot animation on
`/atv`. All three are replaceable, nothing rewrites them at boot, and the device
renders roughly **7 frames per second** at 1920x1080 no matter what you ask for.
That last number is why the stock animation is authored at 8 fps, and it is the
single constraint that decides how a replacement has to be built.

## The three stages

| Stage | What it is | Where | Shown by |
|-------|-----------|-------|----------|
| 1 | Static 1920x1080 JPEG | partition `logo` (`mmcblk0p8`, 40 MB) | U-Boot, before Android |
| 2 | MP4 player — **no media present** | `/system/bin/bootvideo` | init, gated by a property |
| 3 | AOSP boot animation | `/atv/bootvideo/bootanimation.zip` | `bootanimation` service |

## Stage 1 — the `logo` partition

A HiSilicon key/value container followed by a plain baseline JPEG.

```
0x0000  "###\0"                     magic
0x0004  uint32  124                 total header length
0x0008  char[0x20] "LOGO_TABLE"  + uint32 80    table length
0x002c  char[0x20] "LOGO_KEY_FLAG"+ uint32 4 + uint32 1
0x0054  char[0x20] "LOGO_KEY_LEN" + uint32 4 + uint32 <image bytes>
0x2000  JPEG payload, LOGO_KEY_LEN bytes
```

Entries are `name[0x20] + len[4] + value[4]` = 0x28 bytes each, and `0x2c + 80 =
0x7c = 124` closes the header exactly. There are only two entries. Everything
after the image is zero for the remaining 40 MB.

Stock payload is 87053 bytes: baseline JPEG, 4:2:0, three components, 1920x1080,
a white "SUREWHEEL" wordmark. **`LOGO_KEY_LEN` is authoritative — read the length
from the header rather than scanning for the `FFD9` terminator, and never assume
it.** Getting this wrong by 512 bytes still produces a JPEG that decoders happily
render, so a truncated extract does not announce itself.

To replace it, patch two regions and nothing else: the length field at `0x78` and
the payload at `0x2000`. Keep the new image within the stock 87053 bytes — the
header implies variable length is supported, but U-Boot's decode buffer size is
unknown, so staying under the original size is the conservative choice. Build the
patch locally, parse it back with your own reader before writing, and assert that
the region past the old image is zero so the write cannot clobber anything else.

**Not verified:** that U-Boot actually renders a replaced logo. This stage only
draws during a real power-on and cannot be exercised from a running Android, so
the only test is a reboot with someone watching the screen.

## Stage 2 — `bootvideo`

`/system/bin/bootvideo` is a real player, started from `init.bigfish.rc` at `on
init`, and it is selected by `prop.service.bootop.type` (currently `bootanim`;
`quickplay` also appears at `init.bigfish.rc:262`). Its embedded config points at
`/data/local/data/bootvideo.mp4` — **a directory that does not exist.** A search
across `/atv`, `/data/local`, `/vendor` and `/oem` finds no `.mp4` at all, and the
`bootmusic` partition is zero-filled.

So this stage is a place to *add* a boot video, not a place to find one.

## Stage 3 — the boot animation

Path comes from `ro.prop.bootanim.path`. Standard AOSP format. Stock is
1920x1080, 8 fps, 95 frames, `p 1 0 part0` — played once, then frozen on the last
frame for however long the rest of boot takes.

Hard requirements, each of which will silently break playback if violated:

- **Every zip entry must be `Stored`.** A deflated boot animation is not read.
- **Write entries in sorted order.** `zip -r` uses `readdir` order, which comes
  out scrambled. The stock zip is sorted; whether this build re-sorts frame names
  itself was never established, so do not rely on it.
- **`/atv` is small** — 44 MB total, 22 MB free with the 19 MB stock zip in place.

`p 0 0 part0` (loop until boot finishes) **is** honored by this OEM build,
verified by watching frame indices wrap around. Looping beats the stock
play-once behaviour: a full-cycle animation never freezes, however long boot runs.

### The frame-rate ceiling

Measured on hardware by matching screen captures against the shipped frames:

| Frames | `desc.txt` fps | Measured |
|--------|---------------|----------|
| 78 | 15 | 7.68 |
| 39 | 8 | 6.97 |
| 10 | 8 | ~7.96 (phase fit) |

Asking for 15 does not get you 15. Budget frame counts against ~7 fps, not
against the number in `desc.txt`. A cycle of N frames lasts roughly `N / 7`
seconds.

## Writing to the device

**`adb push` straight to `/atv/bootvideo/` reports success and writes nothing.**
It prints `1 file pushed, N bytes` while the target keeps its old checksum and
its old mtime. The directory is `755 root:root`, so adbd (running as `shell`)
cannot create anything in it; why the client still reports success was not
established. Stage through a writable directory and write as root:

```sh
adb push new.zip /data/local/tmp/staged.zip
adb shell 'su 0 sh -c "cat /data/local/tmp/staged.zip > /atv/bootvideo/bootanimation.zip"'
adb shell 'su 0 sha256sum /atv/bootvideo/bootanimation.zip'   # always verify
```

The `>` redirect preserves the inode, its `0777` mode and its `atv_file` SELinux
context. For the raw partition, `dd` needs care — see gotchas below.

## Nothing rewrites these at boot

Verified rather than assumed, and confirmed by an actual reboot in which both
checksums survived unchanged:

| Check | Result |
|-------|--------|
| Other copy of `bootanimation.zip` anywhere on the filesystem | none — only the file itself and `/system/bin/bootanimation` |
| init scripts touching it | only `chmod 0777` at `init.bigfish.rc:61`; no copy |
| `/atv` fstab flags | `wait` only — no `check`, no verity |
| References to `by-name/logo` or `mmcblk0p8` in system binaries | none |
| Its mtime across many boots | still 2022, while `/atv/db/` shows 2026 writes |

That last row is the load-bearing one, and it needs its control: `/atv` *is*
written at runtime (`bootvideo_sound_volume.bin` carries a 2026 timestamp), so a
2022 mtime means untouched rather than a frozen filesystem or a wrong clock.

`init.bigfish.rc:34` does run `restorecon_recursive /atv`, but that resets SELinux
labels, not contents — it works in your favour, repairing a replacement file's
context and mode on every boot.

**Not verified:** whether a factory reset formats `/atv`. Check before resetting.

## Gotchas that cost time

- **toybox `dd` rejects `bs=1M`** — it produced a 0-byte dump that looked like a
  successful read. Use `bs=4096`. It also rejects `conv=notrunc` outright
  (`dd: conv option disabled`); that failure is loud and writes nothing.
- **`screencap` takes ~1.6 s per frame**, which is slower than a short animation
  cycle. Sampling the screen that way aliases, and the naive reading comes out
  confidently wrong (1.69 fps for an animation actually running near 8). Moving
  the captures on-device does not help — `screencap` itself is the bottleneck,
  not the transfer. Resolve it by fitting the rate against jittered sample
  intervals, or measure on a build with enough frames that no cycle completes
  between samples.
- **Take a control capture before concluding anything about the screen.** A blank
  or unchanged frame is as easily a broken measurement as a broken animation.

## Testing without rebooting

Stage 3 can be run on a live system, which catches everything except the U-Boot
logo:

```sh
adb shell 'su 0 sh -c "setprop service.bootanim.exit 0; start bootanim"'
# ... capture, watch ...
adb shell 'su 0 sh -c "setprop service.bootanim.exit 1; stop bootanim"'
```

Both commands need root — as `shell` they fail with `must be root`, and the
failure is easy to miss because everything around them still succeeds.
