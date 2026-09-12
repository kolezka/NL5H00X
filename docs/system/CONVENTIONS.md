---
block: _root
doc: CONVENTIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Documentation conventions

## Source pin

The campaign uses code mode at `f04ee86`; it is a candidate, not an integrated system documentation release. [verified]

Read source with `git show f04ee86:<path>` or a read-only checkout at that pin. Keep the pin on incremental updates; refresh the whole active tree before adopting a newer pin.

## Evidence tags

- `[verified]`: primary source was read at the pin, or a specified measurement was performed. For code claims, this proves the stated code shape, not device behavior.
- `[inferred]`: a consequence derived from stated facts; include the derivation.
- `[assumption]`: a claim carried from memory or secondary material without rechecking.
- `[historical: <date>, <source>]`: a past observation, with its recorded source and date. Use `undated` when the source records no date.
- `[design: §<N>]`: a proposal from a named design section, not implemented behavior.

A source comment can verify that a rationale was recorded; it does not upgrade the event described into a fresh device measurement. If reporting a test run, record its command, environment, scope and result. Do not infer a passing run from a test's existence.

Campaign status statements refer to inspected draft files or recorded tool outcomes, not source behavior. Keep those statements separate from the pinned contracts.

## Citation style

Use repository-relative symbol citations in backticks, for example `scripts/lib/common.sh::adb_root_exec()` or `scripts/INSTALL_APP.sh::PROTECTED_PKGS`. [verified] Do not cite line numbers. Tag claim-bearing sentences and give every contract a nonempty `enforcement:` field. Use `convention` when a boundary has no enforcing mechanism.

Mechanism detail belongs to the owning block. Dependent blocks state the consequence and link back. Ownership entries must be disjoint.

## Verification

Set `CLAUDE_PLUGIN_ROOT` to the installed block-docs plugin root supplied by the loader or coordinator, then run from the repository root:

```sh
python3 "${CLAUDE_PLUGIN_ROOT:?Set the block-docs plugin root}/scripts/blockdocs_lint.py" docs/system --repo . --strict
```

The linter checks citation paths and symbol presence at the pin, but not the truth of the surrounding claim. [verified] It can also return clean for a partial tree whose missing blocks have no directories, so compare the directory inventory with the [block map](README.md) separately. [verified]

Before closing a campaign, verify ownership coverage against `git ls-tree -r --name-only <pin>`, check local links and dependencies, and review evidence tags against the cited source. A partial check must name the omitted scope.

## Local exceptions

The approved docs root is `docs/system/`, not `docs/`; the older narrative pages remain outside the active lint scope. [verified] `root/` remains reserved for the blocked app-root work and is listed explicitly in [Ownership](OWNERSHIP.md). [verified]
