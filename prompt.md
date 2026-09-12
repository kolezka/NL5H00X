# System Flow Refactor Session Handoff

Start implementing the NL5H00X system-flow refactor using the `orchestrator` skill.
Invoke that skill before exploration, then use `superpowers:subagent-driven-development`
for task-by-task execution. Use specialized Agent subagents, not a large Workflow fan-out.

## Read first

Repository: `/Users/me/Development/NL5H00X`.

- `CLAUDE.md` and the installed global instructions.
- `docs/superpowers/specs/2026-09-12-system-flow-refactor-design.md`.
- `docs/superpowers/plans/2026-09-12-system-flow-refactor.md`.
- `docs/system/DATA-FLOW.md`, `OWNERSHIP.md`, `REVIEW.md` and
  `test-harness/GAPS.md` for current implementation and documentation caveats.
- The existing Outline `system-flow-refactor` entries under this project's
  Specs, Plans and Tasks, through the `outline` skill and active world manifest.

The architecture direction was approved. The detailed plan was written and
self-reviewed, not implemented. Its proposed code examples were not executed.
Document-structure and whitespace checks are not runtime verification. Validate
an example against the real code and test fixture before treating it as working.
The full Markdown files are the execution recipe; Outline contains linked summaries.

## Scope and target

Keep Bash, public CLI names, flags, prompts and supported exit behavior compatible.
Use front ends -> workflows -> domain operations and explicit safety policy ->
transport. Preserve the unlock-local step protocol; do not invent a universal
workflow engine or rewrite the toolkit in another language.

All production device execution must eventually use the adapter. Domain and
transport modules must not depend on presentation. Keep legacy output channels
through compatibility wrappers, and do not replace terminating legacy gates with
returns until each consumer handles the status explicitly.

Replace backup log scraping with the plan's validated atomic per-run snapshot,
producer-bound artifact identity and single-writer work-directory lock. Preserve
backup formats, resume semantics and recovery tools usable without the checkout.
Keep structural extraction separate from intentional behavior changes.

## Workspace and delegation

1. Inspect actual local HEAD, branch, status and registered worktrees. Do not assume
   the planning source pin is today's HEAD or reuse another session's workspace.
2. Create a fresh isolated worktree from current local main using the native tool.
   Verify its starting revision; native defaults can select an older upstream ref.
   Never edit the main checkout or move its untracked documentation/configuration.
3. Keep architecture, integration and final verification in the main context.
   Delegate bounded implementation and tests. Give each worker exact owned files,
   interfaces, acceptance cases and permission limits.
4. Run independent read-only work in parallel. Serialize writers sharing a worktree;
   use separate worktrees only when their outputs can genuinely be integrated later.
5. Review each task before starting the next. Prefer an independent model family
   for review when one is available and eligible. Check important subagent claims
   against the actual diff and decoded test output, not the report alone.

## Start with the test foundation

Begin with plan Task 1, then Task 2. Do not run the legacy aggregate of suites first.
The current unlock suite contains a host-wide `pkill -f 'sleep 600'` cleanup. Prove
its regression through harmless process-command stubs, never by executing that
old reaper against real host processes. Fix the producer/owner cleanup and retain
failed fixtures before relying on suite results.

Prove fake-device routing through the actual selected command path: a decoded
fixture-only token plus its invocation log. Validate the harmless downstream
sentinel before using its absence as evidence. Missing fake selection must abort
before any suite; PATH shadowing is not an operating-system sandbox.

Use real binary AXML APK fixtures for parser coverage. A fake-device `.meta`
sidecar does not exercise the installer's manifest parser. Characterization tests
record existing behavior; regression tests require an observed failing and passing
run of the same intended contract. Preserve failure evidence and report skips.

After the foundation passes independent review, continue through the plan's ordered
migration tasks. Stop on unresolved findings or decisions that change scope. Do not
redo the whole architecture discussion merely because this is a fresh session.

## Hard boundaries

- No real ADB, projector writes, reboots, package installs or raw restore writes.
  Recovery tests use an intercepting fake and local fixtures only.
- `root/` daemon and protocol changes are out of scope.
- The recovery safety HOLD remains open. Interface-preserving extraction is not
  proof that existing restore algorithms are safe. Their fixes need separate approval.
- Bash 3.2 is a compatibility target, not a verified property of the local shell.
  Use an actual 3.2 interpreter for that gate or leave it explicitly unverified.
- Respect a denied action. Report it and stop that action; do not retry through a
  different tool or delegate the same denied action to another worker.
- Do not commit, merge, push, delete branches/worktrees or perform hardware validation
  without fresh authorization. The previous local documentation merge is not that
  authorization for this session.
- Keep Outline checkpoints and parent statuses current. Never store secrets there.

At each checkpoint report completed task contracts, meaningful test results,
remaining limitations and the next task. Do not call the entire refactor complete
because one suite or a structural checker passed.
