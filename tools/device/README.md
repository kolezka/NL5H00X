# Device-side checks

Tools for checking a **deployed** `sud` on the projector, and for settling a
measurement question about it. All of them run against real hardware except the
fd loop, which runs in a container.

| Tool | Runs on | Purpose |
| --- | --- | --- |
| `sudcheck.c` | device | Drop to a caller uid, send one request, print sud's status |
| `sud-check.sh` | host + device | Full check of a deployed sud, or `--smoke` for two cases |
| `sud-fd-loop.sh` | host, container | Loop the fd check with a control, to see whether an extra fd belongs to sud or to the probe |

Build the device tools with `root/build.sh`; it builds `sudcheck` and `sudprobe`
into `root/` along with the rest. They are build outputs, not sources, so they are
not committed.

## Why the probe is shaped this way

`sudcheck` drops uid and sends the request **in one process**. Relaying through
a second process (the way `su_hybrid` works) reports the relay's exit code rather
than sud's, and `adb shell` can rewrite quoted arguments on the way in. Both
produced false results on the first deploy of the concurrency fix, including a
"denied caller returns 0" reading that was purely the wrapper.

Sud reports its status as `sudcheck`'s exit status; the command's own output comes
back on stdout. Read both, or a served command and a refused one look the same.

## sud-check.sh

```sh
bash root/build.sh                 # builds the device tools
bash tools/device/sud-check.sh     # full check
bash tools/device/sud-check.sh --smoke   # two cases, after a deploy
```

It resolves the allow-listed uid from the device's own `su-allow` and
`packages.list`, pushes `sudcheck` and `sudprobe`, and verifies the hashes on
arrival. It needs a device on adb with working root (`su_hybrid 0`; the vendor
`su` answers `setgid failed` on this unit).

Covers: allow-listed caller served, unlisted caller refused, unknown uid refused,
unswitchable target uid fails closed, target uid 2000 honoured, command exit
status passed through, and the command inherits only fds 0/1/2.

Does not cover a reboot. To confirm sud starts under init from a clean boot,
reboot and rerun `--smoke`.

## sud-fd-loop.sh

```sh
bash tools/device/sud-fd-loop.sh 500
```

Three loops over the same question, differing only in who runs the command:

- **A** the shell pipeline with no daemon at all,
- **B** the same pipeline through sud,
- **C** a compiled lister through sud, the form `tests/sud-tests.sh` asserts on.

When A and B both show hits and C does not, the extra fd belongs to the pipeline,
not to sud. The deviations are load-dependent: on an idle host all three loops
report zero and the run proves nothing. To reproduce, run it alongside other
container or build work.
