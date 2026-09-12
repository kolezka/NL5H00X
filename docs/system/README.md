---
block: _root
doc: README
verified_against: f04ee86
verified_on: 2026-09-12
---

# NL5H00X toolkit system documentation

**CANDIDATE / INCOMPLETE.** This worktree contains the root pages and the test-harness block; the other drafted blocks remain in the main checkout, pending correction and integration. [verified] The app-root documentation dispatch was blocked and that part of the requested scope remains unfinished. [verified]

This tree documents the shell toolkit at `f04ee86`, including its source contracts, ownership boundaries and test fixture. [verified] Static source review does not establish that a toolkit operation succeeds on the projector. [inferred]

## Block map

| Block | Boundary | Documentation status |
|---|---|---|
| device-access | Shared ADB helpers, output and backup-directory checks in `scripts/lib/common.sh`. | [Draft pending integration](device-access/README.md). [verified] |
| backup | Capture strategies and generated restore script in `scripts/MAKE_BACKUP.sh`. | [Draft pending integration](backup/README.md). [verified] |
| unlock | Step library, launcher preference management and repair CLI. | [Draft pending integration](unlock/README.md). [verified] |
| app-install | APK manifest checks, install fallback and guarded removal. | [Draft pending integration](app-install/README.md). [verified] |
| front-ends | `PROJECTOR.sh` guided workflow and `TOOLS.sh` settings menu. | [Draft pending integration](front-ends/README.md). [verified] |
| test-harness | Fake ADB, fixture setup and script-level assertions. | [Candidate block](test-harness/README.md). [verified] |
| app-root | Reserved source boundary `root/`. | Blocked; not documented. [verified] |

## Reading order

Start with [Conventions](CONVENTIONS.md), then [Data flow](DATA-FLOW.md), [Ownership](OWNERSHIP.md) and [Glossary](GLOSSARY.md).

The links marked pending intentionally name their intended integrated location; those pages are not present in this worktree. [verified] A clean lint of the files present cannot establish campaign completeness because the linter does not require absent block directories to exist. [verified]

## Scope and evidence

The intended campaign includes the shell toolkit, its test harness and the reserved app-root block; app-root is blocked work, not removed scope. [verified] The narrative documents under `docs/` remain untouched, outside this tree. [verified]

Code claims are pinned to `f04ee86`; historical device observations keep their own evidence tags. [verified] This continuation did not run the toolkit suites or issue commands to the projector. [verified] Lint and citation checks concern documentation structure, not device behavior. [inferred]
