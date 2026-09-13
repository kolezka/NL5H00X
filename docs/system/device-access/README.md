---
block: device-access
doc: README
verified_against: f04ee86
verified_on: 2026-09-14
owns: [scripts/lib/common.sh]
depends_on: []
---

# Device access

`scripts/lib/common.sh` is the shared library every entry script loads before it touches the projector. [verified] It owns operator output routing, the ADB preflight gates, the root handshake, the two root transports, the stall watchdog, the backup manifest format and its verification, the confirmation prompts, and the local size and checksum utilities. [verified]

## Boundary

The block owns one file. [verified] The library defines functions, a few constants and the mutable global `scripts/lib/common.sh::SU_MODE`; it is never run as a program, so everything here executes inside a caller's shell process. [verified]

Sharing a library is not interception. Entry scripts also issue ADB commands directly, and such a command gets none of the root wrapping, stderr suppression or exit-status recovery described on these pages. [verified] Those direct calls belong to the blocks that write them, not here. [verified]

`scripts/lib/unlock.sh` is a separate library owned by [`unlock`](../unlock/README.md), even though it runs against helpers this block defines and its caller loaded. [verified]

## Owned sources

| Source | Role | Evidence |
|---|---|---|
| `scripts/lib/common.sh` | The one shared library: print helpers, `scripts/lib/common.sh::require_device()` preflight, the `SU_MODE` root handshake, `adb_root_exec()` and `adb_root_stream()` transports, the `adb_root_stream_watched()` watchdog with `kill_tree()`, the backup manifest and verification helpers, prompts, and size and checksum utilities. | `[verified]` |

## Dependencies

The block has no dependencies. `scripts/lib/common.sh` sources no other file and calls no script at the pin, confirmed by reading the whole file. [verified] The include guard `scripts/lib/common.sh::_COMMON_SH_LOADED` means a second load is a no-op rather than a redefinition. [verified]

## Consumers

Each row records what the consumer gets from this block, not how the consumer works. [verified]

| Block | Consequence | Evidence |
|---|---|---|
| [`backup`](../backup/README.md) | Loads the library and drives the bulk path: `scripts/MAKE_BACKUP.sh` is the only caller of `scripts/lib/common.sh::adb_root_stream_watched()` and it chooses the stall timeout per call. | `[verified]` |
| [`unlock`](../unlock/README.md) | Uses `scripts/lib/common.sh::require_backup()` as its gate before destructive work, so a backup that fails verification here stops an unlock there. | `[verified]` |
| [`app-install`](../app-install/README.md) | Re-probes root after a reboot through `scripts/lib/common.sh::check_root_access()` and sends root commands through `adb_root_exec()`. | `[verified]` |
| [`front-ends`](../front-ends/README.md) | Draws menu state from this block's read-only helpers, including `scripts/lib/common.sh::verify_backup_dir()` and `check_root_access()`, and uses `pause()` for its prompts. | `[verified]` |
| [`test-harness`](../test-harness/README.md) | Sources the library directly to assert on its load behaviour, diagnostic routing, size formatting and backup gate. | `[verified]` |

`SU_MODE` is never exported, confirmed by the absence of any `export` in the library. [verified] A front end that starts a backup as a subprocess therefore hands over no root state, and the child probes again in its own process. [inferred]

## Intra-block flow

```mermaid
flowchart TD
    SRC["entry script sources the library"] --> G["_COMMON_SH_LOADED guard"]
    G --> RD["require_device need_root"]
    RD --> CA["check_adb"]
    RD --> CD["check_device_connected"]
    RD -->|need_root true| CR["check_root_access"]
    CR -->|su -c works| DIRECT["SU_MODE=direct"]
    CR -->|echo cmd pipe su works| PIPED["SU_MODE=piped"]
    CR -->|neither| EMPTY["SU_MODE empty, gate exits 1"]
    DIRECT --> EX["adb_root_exec: status via __RC__ sentinel"]
    PIPED --> EX
    DIRECT --> ST["adb_root_stream: exec-out, remote stderr dropped"]
    PIPED --> ST
    EMPTY -.->|helper called anyway| RC125["return 125"]
    ST --> W["adb_root_stream_watched: 124 on stall"]
    W --> KT["kill_tree"]
    MAN["write_backup_manifest"] --> VD["verify_backup_dir: 0, 1, 2 or 3"]
    RMF["read_manifest_field"] --> VD
    VD --> FBD["find_backup_dir"]
    FBD --> RB["require_backup: exits 1 when unsatisfied"]
    OUT["print_status, print_success, print_step to stdout"]
    ERR["print_warning, print_error to stderr"]
```
