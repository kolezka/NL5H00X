---
block: device-access
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Operations

## Start and stop

There is nothing to start. `scripts/lib/common.sh` is sourced, not executed, by `scripts/INSTALL_APP.sh`, `scripts/MAKE_BACKUP.sh`, `scripts/PROJECTOR.sh`, `scripts/TOOLS.sh` and `scripts/UNLOCK.sh`, each through a path derived from its own script directory. [verified] Loading it twice in one shell is a no-op. [verified]

The lifecycle a caller does control is the preflight. `scripts/lib/common.sh::require_device()` takes one argument that defaults to `false`, always checks for an `adb` binary and a connected device, and probes root only when passed `true`. [verified] Every failing branch calls `exit 1`, so the call ends the process rather than returning a status. [verified]

The one piece of long running work this block owns is a watched transfer. `adb_root_stream_watched()` runs the stream in a background subshell and ends it either when the stream finishes or when `kill_tree()` kills a stalled one. [verified] Nothing else here holds a process, a port or a file handle between calls. [verified]

## Observe

Operator output is prefixed and split by stream: `[INFO]`, `[OK]` and `[STEP]` on stdout, `[WARN]` and `[ERROR]` on stderr, all wrapped in ANSI colour constants. [verified] This block writes no log file; a run directory or a captured log belongs to whichever caller redirects the output. [verified]

The root probe is visible: `require_device true` prints a status line before probing and then either a success line or `scripts/lib/common.sh::"Root access required but not available"` before exiting. [verified] Nothing prints which su form won, so the value of `SU_MODE` is only observable from inside the process. [verified]

A stalled transfer announces itself with `scripts/lib/common.sh::"Transfer stalled"` followed by the timeout and the number of bytes received when it gave up. [verified] The backup gate prints one line per candidate directory, naming a missing image, an unusable manifest, or an image length that disagrees with the manifest. [verified] Those three lines are the only place the `verify_backup_dir()` return codes become visible to an operator. [verified]

## Configuration and paths

This library reads no environment variable. [verified] Its behaviour comes from three places only: the arguments a caller passes, the process's current working directory, and the value of `SU_MODE` left by the last probe. [verified]

`SU_MODE` resolves in a fixed order: `check_root_access()` tries `su -c 'whoami'` and takes `direct` on a `root` answer, otherwise tries the piped form and takes `piped`, otherwise sets the empty string and returns 1. [verified] The empty value is also the library's initial state, so a helper called before any probe behaves exactly as it does after a failed one. [verified] A caller that runs the probe and discards its status, which `scripts/INSTALL_APP.sh::main()` does deliberately after a reboot, leaves that empty value in place and the next root helper refuses with 125. [verified]

The stall timeout is the third argument of `adb_root_stream_watched()` and defaults to 30 seconds when omitted. [verified] Callers pass different values for different kinds of read, and which value goes with which read belongs to [`backup`](../backup/README.md), the only block that calls this helper. [verified]

Paths are fixed constants, not resolvers. The manifest filename is `scripts/lib/common.sh::MANIFEST_NAME`, the verified image name is `scripts/lib/common.sh::"full-system-backup.img"`, and backup directories are found by globbing `scripts/lib/common.sh::"projector-backup-*"`. [verified] All three are relative, so they resolve against the working directory of the calling process, and `write_backup_manifest()` in particular writes into that directory rather than into a directory it was told about. [verified]

`adb` itself is always invoked unqualified, so it resolves through `PATH`. [verified] That is what lets [`test-harness`](../test-harness/README.md) put a stand-in ahead of a real one, and equally what makes the binary in use worth confirming before trusting any reading. [inferred]

## Failure and recovery

Two return values from this block are not device statuses. 125 means a root helper refused: root was never established, the command held a single quote, or no exit-status sentinel came back. [verified] 124 means the watchdog killed a transfer that stopped growing. [verified] Any other value from `adb_root_exec()` is the remote command's own. [verified]

A 125 is recovered by establishing root first, through `require_device true` or a checked `check_root_access()`, in the same process that will call the helper. [verified] Root state does not cross a process boundary, so re-probing in the parent does not help a child. [inferred]

After a stall the output file holds a partial transfer and the helper has already killed the process tree it started. [verified] Retrying and deciding what to do with the partial file are the caller's, and the resume logic lives in [`backup`](../backup/README.md). [verified] `kill_tree()` exists because killing only the direct child leaves ADB's own children running; if a transfer was interrupted some other way, identify leftover processes before killing anything, since nothing here tracks which ones it started. [inferred]

A status of 0 from `adb_root_stream_watched()` is not evidence that data arrived, because the background subshell's status is discarded. [verified] Check the output file's length against what was requested before treating a stream as successful. [inferred]

`require_backup()` ends the process when no directory verifies, and prints advice about hand-writing a manifest for a backup made before manifests existed. [verified] That advice makes an unverified image pass the gate, so it is only safe once the image has been confirmed complete by other means; the printed text says so as well. [verified]
