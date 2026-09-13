---
block: backup
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Operations

## Start and stop

The entry point is `bash scripts/MAKE_BACKUP.sh` with no arguments. [verified] `scripts/MAKE_BACKUP.sh::main()` begins with `require_device true`, so ADB, a connected device and working root are all required before anything is captured and a missing one exits immediately. [verified]

Where the command is launched from matters. The run directory is created relative to the current working directory and the script then `cd`s into it, so the parent directory is both the place the outputs appear and the search root for a resumable earlier run. [verified] `scripts/PROJECTOR.sh::run_backup()` launches it inside its own working directory for exactly this reason. [verified]

There is no stop command and no signal handler: `git show f04ee86:scripts/MAKE_BACKUP.sh | grep -n 'trap '` returns nothing. [verified] Interrupting the run is the supported way to stop it, and what survives depends on the phase, covered under recovery below. [inferred]

A completed run is closed to further work. `main()` reuses only a directory that holds an image and no manifest, so re-running after a success starts a fresh timestamped directory rather than touching the finished one. [verified]

## Observe

The block writes no log. Progress goes to stdout and diagnostics to stderr through the shared print helpers, and the caller captures the stream: `scripts/PROJECTOR.sh::".backup-progress.log"` for the guided front end, and a per-run `log` file for the harness in `tests/run-tests.sh::run_backup()`. [verified]

Streaming prints a percentage line per completed block, so progress granularity is one `scripts/MAKE_BACKUP.sh::STREAM_CHUNK_MB` block. [verified] The staged paths report per chunk, and the direct path prints `scripts/MAKE_BACKUP.sh::"Progress:"` every 30 seconds from a background subshell that reads the staged file's length on the device. [verified]

The durable signal is not the text. A run passed if and only if the manifest exists, because `scripts/MAKE_BACKUP.sh::verify_backup()` writes it on the passing branch and removes it on the failing one. [verified] To check a directory without rerunning anything, use `scripts/lib/common.sh::verify_backup_dir()`, which is also what `scripts/lib/common.sh::require_backup()` and the front end's status view call. [verified] Its return codes distinguish a missing image, an unusable manifest and a truncated image; the meanings belong to [`device-access`](../device-access/README.md).

Stall reports come from the watcher in `scripts/lib/common.sh::adb_root_stream_watched()`, not from this block, so the phrase `scripts/PROJECTOR.sh::"Transfer stalled"` that the front end counts is owned there. [verified] Its presence in a log means a transfer was killed and retried, which is a normal recoverable event, not a failed run. [inferred]

## Configuration and paths

Every knob is read once at load time as `${VAR:-default}` and none is validated, so an unset variable and an empty one behave identically and a nonsense value is used as given. [verified]

| Variable | Default | Scope | Evidence |
|---|---|---|---|
| `BACKUP_DIR` | unset | Run directory, used verbatim when nonempty. Highest precedence of the three. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::DEVICE_BLOCK` | `/dev/block/mmcblk0` | Whole-device reads in all three full-device paths and in `scripts/MAKE_BACKUP.sh::get_device_size()`. Recorded in the manifest. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::DD_BLOCK_SIZE` | `1048576` | Remote `bs` for the partition, chunked and streaming reads. Treat as fixed; see `GAPS.md`. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::CHUNK_SIZE_MB` | `3000` | Chunked fallback only. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::STREAM_CHUNK_MB` | `256` | Streaming block size, and therefore the resume granularity and the progress granularity. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::STREAM_RETRIES` | `3` | Attempts per streaming block. Not applied anywhere else. | `[verified]` |
| `scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS` | `30` | Stall budget for streaming transfer blocks only. | `[verified]` |

### The stall tunable does not reach the probes

`scripts/MAKE_BACKUP.sh::STREAM_STALL_SECS` is passed at exactly one call site, the watched transfer read inside the retry loop of `scripts/MAKE_BACKUP.sh::backup_full_device_stream()`. [verified] The two md5 probes pass a literal 20 instead: the resume-point probe in the same function, and the tail probe in `scripts/MAKE_BACKUP.sh::backup_partition()`. [verified]

An operator on a slow or intermittent link who raises the variable therefore lengthens the budget for bulk block reads and changes nothing about either probe, which keep a fixed 20 seconds of silence before they are killed. [inferred] The consequence is not symmetric between the two probes. A killed tail probe costs a re-pull of one partition, while a killed resume probe produces `scripts/MAKE_BACKUP.sh::"Resume check FAILED"` and discards the accumulated image, which is recorded in `GAPS.md`. [verified]

Reproduce the scope with `git show f04ee86:scripts/MAKE_BACKUP.sh | grep -n 'adb_root_stream_watched' -A2`, which shows the three call sites and their third argument. [verified]

### Path resolution

The run directory resolves in three steps: a nonempty `BACKUP_DIR`, then the directory returned by `scripts/lib/common.sh::find_incomplete_backup_dir()`, then a new `scripts/MAKE_BACKUP.sh::"projector-backup-"` name with a local timestamp. [verified] All output names below it are literals in the script, not derived from configuration. [verified]

Staging paths on the device are literals too and differ per strategy: `scripts/MAKE_BACKUP.sh::"temp_backup.img"` for a partition, `scripts/MAKE_BACKUP.sh::"chunk.img"` for the chunked path, `scripts/MAKE_BACKUP.sh::"full_backup.img"` for the direct path, and nothing at all for streaming. [verified] The generated `RESTORE.sh` ignores `DEVICE_BLOCK` and writes hard coded partition paths. [verified]

## Failure and recovery

**An interrupted run.** Start it again from the same parent directory. `main()` finds the unfinished directory and `backup_full_device_stream()` continues from the last whole block after checking the resume point against the device. [verified] Partition images already present are reused rather than re-pulled when their length and tail both match. [verified] Nothing cleans up on interrupt, so `scripts/MAKE_BACKUP.sh::"stream_block.tmp"`, a stray `full-system-backup.img.part` and any device-side staging file may be left behind; the next run removes the temporary block file itself but not the others. [verified]

**A stalled transfer.** The watcher kills it after the configured budget and the retry loop tries again, up to `STREAM_RETRIES` times for that block. [verified] Repeated stall lines for the same offset mean the retries are being consumed; the run continues until they are exhausted. [inferred]

**Resume check failed.** The run does not stop there. `main()` deletes the image and falls back to a staged capture from scratch, which is why the harness scenario for a corrupt prefix still ends with a byte-identical image. [verified] Do not act on the printed advice to delete the file by hand: it has already been deleted, and the run is still going. [inferred]

**A streaming block that failed every retry.** The message says the transferred prefix is kept for a later resume; it is not, because `main()` deletes it before the fallback. [verified] If the staged fallback then fails, the next run starts from zero. [inferred]

**A short chunk.** The chunked path stops and the run exits nonzero, and `scripts/MAKE_BACKUP.sh::"Chunk files kept for inspection"` names the evidence deliberately left in place. [verified] Inspect those files before rerunning, because the next run overwrites them. [inferred]

**A run that ends with `scripts/MAKE_BACKUP.sh::"BACKUP INCOMPLETE"`.** There is no manifest, so the unlock CLI's gate stays shut and option 4 of the generated restore script refuses. [verified] The other restore options carry no such gate, so do not run `RESTORE.sh` out of a directory that failed. [inferred]

**Restoring.** Read `GAPS.md` before using `RESTORE.sh`. No suite executes it, its whole-device branch has a path that reboots without writing anything, and both of its write paths use the `su` form the recorded hardware measurement says this device rejects. [verified] Treat it as unverified code on the one operation that can end the projector, and confirm each step against the device rather than against the script's output. [inferred]
