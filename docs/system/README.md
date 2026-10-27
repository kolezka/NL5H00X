---
block: _root
doc: README
verified_against: f04ee86
verified_on: 2026-09-12
---

# NL5H00X toolkit system documentation

Source pin: `f04ee86`. The unlock and app-install blocks describe the model
before October 2026. For current behavior, start with [docs/README.md](../README.md).

**SOURCE-PINNED / PARTLY STALE.** The documented blocks are present here. The app-root block was not written in this tree; use [root/README.md](../../root/README.md) for that feature. The unlock and app-install blocks need the current corrections linked above.

This tree documents the shell toolkit at `f04ee86`, including its source contracts, ownership boundaries and test fixture. [verified] Static source review does not establish that a toolkit operation succeeds on the projector. [inferred]

## Block map

| Block | Boundary | Documentation status |
|---|---|---|
| device-access | Shared ADB helpers, output and backup-directory checks in `scripts/lib/common.sh`. | [Source-pinned block](device-access/README.md). |
| backup | Capture strategies and generated restore script in `scripts/MAKE_BACKUP.sh`. | [Source-pinned block](backup/README.md). |
| unlock | Step library, older preference model and repair CLI. | [Source-pinned block](unlock/README.md); see the current cache correction above. |
| app-install | APK manifest checks, install fallback and guarded removal. | [Source-pinned block](app-install/README.md); see the gate correction above. |
| front-ends | `PROJECTOR.sh` guided workflow and `TOOLS.sh` settings menu. | [Source-pinned block](front-ends/README.md). |
| test-harness | Fake ADB, fixture setup and script-level assertions. | [Candidate block](test-harness/README.md). [verified] |
| app-root | Separate source boundary `root/`. | [Root for apps](../../root/README.md) is documented outside this tree. |

## Reading order

Start with [Conventions](CONVENTIONS.md), then [Data flow](DATA-FLOW.md), [Ownership](OWNERSHIP.md) and [Glossary](GLOSSARY.md).

The blocks above exist in this tree. Their source pin is historical; use the
current guides linked at the top for changed device behavior.

## Scope and evidence

The source-pinned campaign covers the shell toolkit and test harness. App-root
is documented separately in [root/README.md](../../root/README.md). The
narrative docs have since been updated; see [docs/README.md](../README.md).

Code claims are pinned to `f04ee86`; historical device observations keep their own evidence tags. [verified] This continuation did not run the toolkit suites or issue commands to the projector. [verified] Lint and citation checks concern documentation structure, not device behavior. [inferred]
