---
block: _root
doc: README
verified_against: f04ee86
verified_on: 2026-09-14
---

# NL5H00X toolkit system documentation

All six planned blocks are present in this tree, each with the five required pages at the pin. [verified] The app-root block stays blocked and undocumented, so `root/` is recorded as a reserved path and not as covered scope. [verified]

This tree documents the shell toolkit at `f04ee86`, including its source contracts, ownership boundaries and test fixture. [verified] Static source review does not establish that a toolkit operation succeeds on the projector. [inferred] The pin predates the current branch head, so source added after `f04ee86` is outside this campaign and needs a full refresh before it can be described here. [verified]

## Block map

| Block | Boundary | Documentation status |
|---|---|---|
| device-access | Shared ADB helpers, output and backup-directory checks in `scripts/lib/common.sh`. | [Documented at the pin](device-access/README.md). [verified] |
| backup | Capture strategies and generated restore script in `scripts/MAKE_BACKUP.sh`. | [Documented at the pin](backup/README.md). [verified] |
| unlock | Step library, launcher preference management and repair CLI. | [Documented at the pin](unlock/README.md). [verified] |
| app-install | APK manifest checks, install fallback and guarded removal. | [Documented at the pin](app-install/README.md). [verified] |
| front-ends | `PROJECTOR.sh` guided workflow and `TOOLS.sh` settings menu. | [Documented at the pin](front-ends/README.md). [verified] |
| test-harness | Fake ADB, fixture setup and script-level assertions. | [Documented at the pin](test-harness/README.md). [verified] |
| app-root | Reserved source boundary `root/`. | Blocked; not documented. [verified] |

## Reading order

Start with [Conventions](CONVENTIONS.md), then [Data flow](DATA-FLOW.md), [Ownership](OWNERSHIP.md) and [Glossary](GLOSSARY.md).

Every block link above resolves inside this tree. [verified] A clean lint still checks structure only: it confirms that pages, front matter, citations and enforcement fields exist, never that a claim on a page is true. [verified]

## Scope and evidence

The campaign covers the shell toolkit and its test harness at the pin. [verified] app-root is blocked work, not removed scope, and `root/` stays in the unassigned table of [Ownership](OWNERSHIP.md). [verified] The narrative documents under `docs/` remain untouched, outside this tree. [verified]

Code claims are pinned to `f04ee86`; historical device observations keep their own evidence tags. [verified] This campaign read source only through `git show f04ee86:<path>`, ran no toolkit suite and issued no command to the projector. [verified] Several pages record behaviour that no suite asserts, most of it in each block's `GAPS.md`; read those before treating a contract as enforced. [verified]

The restore path deserves a direct warning here rather than only on a block page. `scripts/MAKE_BACKUP.sh::create_restore_scripts()` writes a `RESTORE.sh` whose full-device branch runs its raw `dd` write only in the failure branch of `adb push`, so a push that reports success copies the image to `/sdcard`, writes nothing to the block device and reboots. [verified] No suite executes that generated script. [verified] Details are in [backup GAPS](backup/GAPS.md).
