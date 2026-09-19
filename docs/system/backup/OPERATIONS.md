---
block: backup
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

Run the owned script directly with no arguments. [verified] It calls the shared device check in requiring-root mode before anything else, so a device that is absent or not rooted stops the run at the start rather than partway through a transfer. [verified] The front-end block also launches it in the background rather than reimplementing it. [verified]

There is no stop command. Interrupting the process is the way to stop it, and doing so is safe: the streaming path leaves the bytes it has already assembled in place, and the next run resumes from the last completed block after proving the existing prefix against the device. [verified] A run interrupted during a staged path leaves a temporary file on the device that the next run overwrites by name. [inferred, from both staged paths writing to fixed paths under `/sdcard` on every attempt]

## Observe

Progress and errors go to the terminal through the shared print helpers, with warnings and errors on standard error. [verified] The streaming path prints a percentage and a running total after each completed block, so the cadence of output is the block size rather than a timer. [verified] The direct path prints progress every thirty seconds from a side process, reading the size of the staged file on the device. [verified]

Do not treat the log as the progress signal. The image file growing on disk is the thing being produced, and the front end watches its size for exactly that reason. [verified] The line `Transfer stalled` is the marker for a killed block, and counting it gives the number of stalls in a run. [verified]

The end of a run is unambiguous in the output. A passing run prints a completion line and writes the manifest; a failing run prints an incomplete line, removes the manifest and returns non-zero. [verified]

## Configuration and paths

There is no configuration file and no command-line flag. Every input is an environment variable read once when the script loads, using a literal default, so the precedence is the caller's environment first and the built-in default otherwise. [verified]

| Variable | Default | Effect |
|---|---|---|
| `CHUNK_SIZE_MB` | 3000 | Size of each staged chunk on the chunked path |
| `DEVICE_BLOCK` | `/dev/block/mmcblk0` | Whole-device node that is read |
| `DD_BLOCK_SIZE` | 1048576 | Block size passed to `dd`, a plain byte count rather than a suffixed form, see [INVARIANTS](INVARIANTS.md) and [GAPS](GAPS.md) |
| `STREAM_CHUNK_MB` | 256 | Size of each streamed block, which bounds how long a single remote read has to survive |
| `STREAM_RETRIES` | 3 | Attempts allowed per block, reset for each new block |
| `STREAM_STALL_SECS` | 30 | Seconds without new bytes before a block transfer is killed |
| `BACKUP_DIR` | unset | Forces the output directory instead of resolving one |

The defaults are the literals in `scripts/MAKE_BACKUP.sh::"CHUNK_SIZE_MB=${CHUNK_SIZE_MB:-3000}"` and its neighbours. [verified] Read them from the configuration block at the top of the owned file rather than from this table if the two ever disagree. [verified] The test harness overrides several of them to drive a small stand-in device at the same arithmetic as real hardware. [verified]

The output directory is resolved in three steps by `scripts/MAKE_BACKUP.sh::main()`. [verified] An explicit `BACKUP_DIR` wins. [verified] Otherwise the newest resumable directory is reused, which means a directory matching the backup name pattern that holds an image but no manifest, resolved by a helper owned by [device-access](../device-access/README.md). [verified] Otherwise a fresh timestamped directory is created. [verified] A finished run is never reused, because its manifest disqualifies it. [verified]

That middle step is load bearing rather than a convenience. Without it every run would get its own empty directory and the streaming resume could never fire. [verified]

All artifact paths are relative, because the script changes into the resolved directory before capturing anything. [verified]

## Failure and recovery

A block that comes back short or stalls is retried within the same run and is not a fault. [verified] When a block exhausts its attempts the run stops and reports how much is kept in the image, and re-running resumes from that point. [verified]

A resume check that fails is different and must not be retried. The run refuses to continue and tells the operator to delete the image and start over, because the existing file does not match the device and extending it would produce a file of the right length and the wrong content. [verified]

After a failed chunked run the chunk files are kept on purpose. [verified] They are the only record of what came off the device, so inspect them before deleting anything. [verified]

Recovery for consumers is simple. No manifest means no verified backup, and the scripts that gate on one will refuse and tell the operator to run this block first. [verified] The gate lives in [device-access](../device-access/README.md) and is consumed by the unlock and front-end blocks. [verified]

Restoring is out of band. The generated `RESTORE.sh` sits in the backup directory and is run by a human against a connected device; nothing in this block runs it, and its whole-device option refuses unless the image matches the manifest. [verified]
