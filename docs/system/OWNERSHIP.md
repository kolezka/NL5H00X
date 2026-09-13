---
block: _root
doc: OWNERSHIP
verified_against: f04ee86
verified_on: 2026-09-14
---

# Ownership map

The coverage denominator is the tracked source tree returned by `git ls-tree -r --name-only f04ee86`. [verified] The tables separate block ownership from deliberately unassigned paths. [verified]

The authoritative `owns:` list belongs in each block README, and all six are present in this tree. [verified] Their `owns:` values reproduce the boundaries below and the linter rejects an overlap between two of them. [verified] `docs/system/` did not exist at the pin, so the new documentation does not own itself as source. [verified]

## Block ownership

| Block | Source boundary | Documentation |
|---|---|---|
| `device-access` | `scripts/lib/common.sh` | [`device-access`](device-access/README.md) |
| `backup` | `scripts/MAKE_BACKUP.sh` | [`backup`](backup/README.md) |
| `unlock` | `scripts/UNLOCK.sh`, `scripts/lib/unlock.sh` | [`unlock`](unlock/README.md) |
| `app-install` | `scripts/INSTALL_APP.sh` | [`app-install`](app-install/README.md) |
| `front-ends` | `scripts/PROJECTOR.sh`, `scripts/TOOLS.sh` | [`front-ends`](front-ends/README.md) |
| `test-harness` | `tests/` | [`test-harness`](test-harness/README.md) |
| `app-root` | `root/` reserved, BLOCKED and not documented | none |

The six boundaries are disjoint at the pin: `scripts/lib/` is split file by file between `device-access` and `unlock`, and no entry contains another. [verified]
Planned dependencies, each confirmed by a load or a subprocess call at the pin: `device-access` depends on nothing, `backup` and `unlock` on `device-access`, `app-install` on `device-access` and `unlock`, `front-ends` on `device-access`, `backup` and `unlock`, and `test-harness` on `device-access`, `backup`, `unlock` and `front-ends`. [verified]
`test-harness` does not exercise `scripts/INSTALL_APP.sh` at the pin, so it carries no dependency on `app-install`. [verified]

## Intentionally unassigned paths

| Path | Reason | Evidence |
|---|---|---|
| `root/README.md`, `root/build.sh`, `root/privtest.c`, `root/suc.c`, `root/sud.c` | Reserved for the `app-root` block, which is BLOCKED. This map records the paths only; the block documentation remains undelivered. | `[verified]` |
| `apks/PROVENANCE.md`, `apks/nova-launcher-7.0.57.apk`, `apks/projectivy-launcher-4.71.apk` | Third party payload binaries and their provenance note, consumed by the toolkit but not source it owns. | `[verified]` |
| `assets/img1.png`, `assets/hardware/board-overview.jpg`, `assets/hardware/board-usb-device-footprint.jpg`, `assets/hardware/projectivy-running.jpg`, `assets/hardware/uart-pads-txrx-closeup.jpg` | Images used by narrative documents. No behaviour to contract. | `[verified]` |
| `docs/README.md`, `docs/BOOT_BRANDING.md`, `docs/BOOT_DEADLOCK.md`, `docs/DEV_OPTIONS_CRASH.md`, `docs/INSTALL_LOCKED.md`, `docs/SECURITY_ANALYSIS.md`, `docs/TECHNICAL_NOTES.md` | Existing narrative documents at the pin. They stay untouched and outside `docs/system/`; block pages may cite them but do not own them. | `[verified]` |
| `.editorconfig`, `.gitignore`, `CHANGELOG.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `LICENSE`, `README.md` | Repository root metadata and contributor documentation. Not owned by any block. | `[verified]` |

The unassigned rows explicitly name the paths outside the planned script and test boundaries, including the blocked `root/` scope. [verified]
Recount after any refresh by comparing the block boundaries against `git ls-tree -r --name-only <pin>`; a path that appears in neither table is an ownership gap, not an implicit exemption. [verified]
