---
block: backup
doc: README
verified_against: f04ee86
verified_on: 2026-09-12
owns: [scripts/MAKE_BACKUP.sh]
depends_on: [device-access]
---

# Backup

This block captures a whole-device image from the projector over adb, captures a few narrower artifacts alongside it, and generates the restore path into the same directory. [verified]

It is the block that decides whether a backup counts as complete. Every other block that refuses to modify the device without a backup is reading the record this block writes. [verified]

## Boundary

The block owns one script. It owns the capture strategies, the resume logic, the size assertions, the tunables that shape a run, the generated `RESTORE.sh` text, and the decision to declare a run verified. [verified]

It does not own how a root command reaches the device, how a stalled transfer is detected and killed, how a local or remote file size is measured, or how the manifest file is written and read back. Those live in `scripts/lib/common.sh`, which belongs to [device-access](../device-access/README.md). [verified]

Restoring is only partly in scope. This block owns the text of the restore script it emits, but running a restore is a human action against the device and nothing here executes one. [verified]

## Owned sources

| Source | Role | Evidence |
|---|---|---|
| `scripts/MAKE_BACKUP.sh` | Whole-device capture, partition and system-info capture, restore script generation, and the single pass/fail verdict for a run | `[verified]` |

## Dependencies

| Block | Consequence | Evidence |
|---|---|---|
| [device-access](../device-access/README.md) | The script sources `scripts/lib/common.sh` at startup and cannot run without it. Root execution, stall-watched transfers, size probes and the manifest format come from there, so a change in that library changes how a backup is captured and what counts as verified without this block's owned file being touched. | `[verified]` |

## Intra-block flow

```mermaid
flowchart TD
    A["main: resolve backup directory"] --> B["get_device_size via blockdev getsize64"]
    B --> C["backup_system_info, backup_app_data"]
    C --> D["backup_partition: boot.img, system.img"]
    D --> E["backup_full_device_stream"]
    E -->|ok| G["create_restore_scripts"]
    E -->|failed| F{"device size > free space on /sdcard?"}
    F -->|yes| C1["backup_full_device_chunked"]
    F -->|no| C2["backup_full_device_direct"]
    C1 --> G
    C2 --> G
    G --> H["verify_backup: image size vs device size"]
    H -->|pass| I["write backup-manifest.txt, exit 0"]
    H -->|fail| J["remove manifest, exit 1"]
```
