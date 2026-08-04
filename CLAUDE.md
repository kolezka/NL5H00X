## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Working on the device

The projector is a single, irreplaceable unit. Assume every reading is wrong until
its instrument is proven, and verify every write against the device rather than
against a tool's success message.

### Writes

- **`adb push` to a root-owned directory reports success and writes nothing.** It
  prints `1 file pushed, N bytes` while the target keeps its old checksum and
  mtime. Stage in `/data/local/tmp`, then write as root with a redirect
  (`su 0 sh -c "cat staged > target"`) — that preserves the inode, mode and
  SELinux context — and **always confirm with `sha256sum` on the device.**
- `su 0` in an adb shell gives uid 0 and SELinux is Permissive, so root is
  available. It is never automatic: `start`, `stop` and `setprop` on service
  properties fail as `shell` with `must be root`, and that failure is easy to miss
  because the surrounding commands still succeed.
- Normal package installs always fail here — see `docs/INSTALL_LOCKED.md`. Apps go
  to `/system/app`, so "just install an app" is a `/system` change.
- The device is signed with the **published AOSP test platform key**, so system
  APKs can be patched and re-signed with a matching signature. See
  `docs/DEV_OPTIONS_CRASH.md`.

### Instruments that lie

- toybox `dd` rejects `bs=1M` and produced a **0-byte dump that read as success**.
  Use `bs=4096`. It also rejects `conv=notrunc`, but that failure is loud.
- `screencap` takes ~1.6 s per frame. Sampling a short animation with it aliases
  and yields a confident wrong number. Capturing on-device does not help — the
  bottleneck is `screencap`, not the transfer.
- Take a control reading before diagnosing anything visual. An unchanged or blank
  frame is as easily a broken measurement as a broken system.
- Length fields beat terminator scans. Reading the `logo` partition with a
  hand-computed length produced a truncated JPEG that still decoded and still
  rendered — a silent 512-byte error.

### Before anything destructive

Back up, verify the backup against its source by checksum, and know the restore
command before you need it. Raw-partition writes get built and parsed locally
first, with an assertion that the region past the payload is what you think it is.
Reboots are the only test for anything U-Boot draws, and their result cannot be
read over adb — a human has to watch the screen.
