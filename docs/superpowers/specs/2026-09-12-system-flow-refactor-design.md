# System Flow Refactor Design Record

Date: 2026-09-12
Workspace: `.claude/worktrees/docs+system-flow-refactor` (docs-only delta over the code pin)
Companion plan: `docs/superpowers/plans/2026-09-12-system-flow-refactor.md`

## Status of this record

**User-approved direction.** An incremental Bash refactor keeping CLI compatibility, the current
entrypoint names and the unlock-local step protocol. Scope is the host toolkit plus the generated
recovery artifact contract. Target shape: front ends, then workflows, then domain operations with an
explicit safety policy, then transport. Presentation stays out of transport. Sentinel return codes and
binary stream behavior are preserved. No shared-layer blanket fallback. Transport gets explicit fake
injection rather than a PATH fallback to live ADB. Consumers migrate one at a time. Tests guard
behavioral contracts. Pure extractions keep semantics; bug fixes are proven separately. Restore tools
stay usable inside a backup directory with no checkout. No universal workflow engine, no language
rewrite.

**Coordinator-settled architecture.** The rules in "Settled rules" below were decided by the
coordinator during self-review and are not open questions.

**Newly proposed detail awaiting review.** The module layout, signatures, status schema, packaging
approach, containment design and checker design are proposals.

Planning being complete is not implementation being approved. No suite, toolkit script, ADB command
or build was executed. The newly created worktree was fast-forwarded to 6321040 after inspection of
its documentation-only delta from f04ee86; no commit was created. Source checks establish code shape,
not runtime or device behavior. The Bash version query was blocked; Bash 3.2 compatibility remains
unverified. ShellCheck 0.11.0 was identified, but the toolkit was not linted during planning.

**Every code block in this record is a proposed example, not run.** Reading existing source verifies
the current code's shape; it does not verify any snippet proposed here. Signatures, schemas and
return codes below are design intent awaiting implementation and execution. Final runtime suite
execution and behavior under an actual Bash 3.2 shell are explicitly unverified.

## Problem

Four coupled defects, each read from source rather than observed at runtime.

**Presentation, transport, policy and artifact handling share one file.** `scripts/lib/common.sh`
holds the color constants and the `print_*` writers alongside the ADB helpers, the backup manifest
reader and writer, the backup directory search, `require_backup`, the interactive prompts and the size
and checksum utilities. The stdout and stderr split documented at its head is maintained by reviewer
attention, not by structure.

**The unlock library mixes reusable operations with a step driver.** `scripts/lib/unlock.sh` holds
mount, package, settings and home-intent operations next to the four-function step protocol, the
launcher constants and the repair mode. `scripts/INSTALL_APP.sh` sources the whole file for three of
those operations, so the app-install path carries the step protocol and the launcher constants it
never uses, and inherits `launcher_apk`'s unguarded `$APK_DIR` dereference, which `INSTALL_APP.sh`
never assigns. That coupling is latent, not live: there is no `launcher_apk` call site there.

**The backup front end reads progress and completion out of prose.** `scripts/PROJECTOR.sh` starts
the backup with stdout and stderr merged into a per-invocation log which it truncates before the run,
then derives the stall count, the block total and the completed-block count by matching message text.
Completion is decided by matching a fixed success string. So the machine channel is operator-facing
English: rewording a message changes program behavior, the block counter is derived from a rendered
percentage line rather than from the producing loop's own counter, and the child's exit status is
captured but used only inside a failure message rather than as the authority. Progress rendering and
the completion decision are separate concerns here, and only the latter currently gates the operator.

**Direct ADB calls sit outside any adapter.** Device invocations appear in every entry script and in
both libraries, not only behind the shared root helpers: bare `adb shell` calls in the front ends and
in `check_supported_device`, and direct `adb install` and `adb push` in `launcher_present_apply`. No
single place can intercept a device call, which is what makes containment and a layering rule
unenforceable today. Cancellation is also unhandled, with no signal handler installed anywhere, while
the front end tells the operator the backup survives closing the window, which the new cancellation
policy must either make true or stop claiming.

## Settled rules

1. **Transport depends on nothing.** `scripts/lib/transport/` must not source `ui/log.sh` and must not
   call any `log_*` or `print_*` function. It may `printf` a plain diagnostic to stderr. There is no
   open decision here.
2. **Domain depends on transport only.** Domain modules must not depend on presentation. Existing
   `print_error` calls inside the mount and package operations become either a plain stderr `printf`
   or a returned diagnostic. The compatibility facade may keep the old rendering until its callers
   migrate.
3. **`common.sh` is a low-level compatibility facade only.** It must never load `workflow/*`, which
   would create a cycle, because workflows load domain and transport which the facade also aliases.
4. **Colors live in `ui/colors.sh`**, included by `ui/log.sh` and `ui/render.sh`. They stop being an
   implicit global that other layers depend on.
5. **Source ordering is dependency-closed and include-guarded.** Every module guards itself and
   sources exactly what it uses.
6. **The source-time prohibition is scoped:** no probes, no device actions, no output at source time.
   Path resolution and dependency loading at source time are allowed.
7. **New `log_*` helpers write to stderr from introduction.** The legacy `print_status`,
   `print_success` and `print_step` keep their current stdout routing inside the compatibility
   wrappers, because the goal is an unchanged CLI surface and external stdout consumers are unknown.
   There is no global stream-flip task.
8. **All production ADB invocations funnel through the adapter**, and the architecture checker enforces
   that rather than a reviewer explaining audit differences. The generated recovery artifact receives
   an inlined copy of the same executor.

## Target layering and ownership

| Layer | May depend on | Home |
|---|---|---|
| front ends | workflow, presentation | `scripts/PROJECTOR.sh`, `scripts/TOOLS.sh` |
| CLI wrappers | workflow | `scripts/{MAKE_BACKUP,UNLOCK,INSTALL_APP}.sh` |
| workflow | domain, policy, progress, presentation, packaging; feature-local workflow modules | `scripts/lib/workflow/` (new), existing `scripts/lib/unlock.sh` |
| policy | domain | `scripts/lib/policy/` (new) |
| domain | transport | `scripts/lib/domain/` (new) |
| transport | nothing | `scripts/lib/transport/` (new) |
| presentation | nothing | `scripts/lib/ui/` (new) |
| progress | nothing | `scripts/lib/progress/` (new) |
| compatibility facade | domain, transport, progress, presentation | `scripts/lib/common.sh` |
| packaging | transport and local file operations at generation time | `scripts/lib/packaging/` (new) |

The table lists cross-layer dependencies; acyclic same-layer helpers such as UI colors and the
domain profile are allowed. The feature-local workflow edge is `workflow/unlock.sh` loading
`lib/unlock.sh`, never the reverse.
New modules load their own guarded dependencies, not the compatibility facade. Human output wrappers
and prompts live in `ui/legacy.sh`; the facade re-exports them for existing callers.

`root/` is an external boundary. The root daemon and its socket protocol are out of scope, no layer
may depend on it, and the checker neither reads nor classifies it.

Front ends end up using workflow and presentation interfaces only. The three CLI wrappers forward
argv and propagate the workflow's return code.

## Where existing functions go

| From | To | Functions |
|---|---|---|
| `common.sh` | `ui/colors.sh` | the color constants |
| `common.sh` | `ui/render.sh` | `print_header`, `print_section`, `human_size` |
| `common.sh` | `transport/adb.sh` | `adb_root_exec`, `adb_root_stream`, `adb_root_stream_watched`, `kill_tree`, `adb_remote_size`, the `su` probing half of `check_root_access` |
| `common.sh` | `domain/backup_artifact.sh` | `write_backup_manifest`, `read_manifest_field`, `verify_backup_dir`, `find_backup_dir`, `find_incomplete_backup_dir`, `MANIFEST_NAME` |
| `common.sh` | `domain/file_ops.sh` | size and checksum operations; new `file_script_dir <source_path>` |
| `common.sh` | `ui/legacy.sh` | legacy presentation wrappers, `confirm`, `pause` |
| `common.sh` | stays as facade | adapter-backed checks, terminating `require_device`/`require_backup`, legacy `get_script_dir`, aliases for moved names |
| `common.sh` | cleanup after reference audit | remove unused `adb_exec`, `adb_start_activity`, `adb_start_action`, or migrate discovered consumers; no raw-ADB exception remains in the facade |
| `unlock.sh` | `domain/mount.sh` | `system_mountpoint`, `system_is_rw`, `system_rw`, `system_ro` |
| `unlock.sh` | `domain/package.sh` | `package_installed`, `package_disabled`, `package_path`, `component_disabled` |
| `unlock.sh` | `domain/settings.sh` | `setting` |
| `unlock.sh` | `domain/home.sh` | `home_activity`, `home_component_of`, `home_interceptor`, `home_owner` |
| `unlock.sh` | `domain/profile.sh` | shared vendor identity constants, preserving their values |
| `unlock.sh` | stays | step protocol, `UNLOCK_STEPS`, `DEV_SETTINGS`, `LEFTOVERS`, replacement-launcher selection, launcher checks and repair sequencing, with domain-backed device operations |
| `UNLOCK.sh` | `workflow/unlock.sh` | `step_line`, `show_status`, `all_applied`, `run_step`, `apply_all`, `revert_all`, `show_menu`, `single_step_menu`, `interactive` |
| `UNLOCK.sh` | `policy/safety.sh` | `SUPPORTED_DEVICES` and the model test inside `check_supported_device` |
| `MAKE_BACKUP.sh` | `workflow/backup.sh` | `backup_system_info`, `backup_app_data`, `backup_partition`, `backup_full_device_stream`, `backup_full_device_chunked`, `backup_full_device_direct`, `verify_backup`, the run sequence |
| `MAKE_BACKUP.sh` | `domain/backup_io.sh` | `get_device_size`, `get_device_free_space`, the remote staging and pull steps |
| `MAKE_BACKUP.sh` | `lib/packaging/restore/` | `create_restore_scripts` and its two heredocs |
| `INSTALL_APP.sh` | `domain/apk.sh` | `apk_facts`, `apk_abis`, `abi_to_isa`, `default_name_from_apk` |
| `INSTALL_APP.sh` | `workflow/app_install.sh` | install/remove sequencing, verification decisions, prompts, usage and argument dispatch |
| `INSTALL_APP.sh` | `domain/system_app.sh`, `domain/device_actions.sh` | device mutation/read-back bodies and reboot operations, preserving the existing uptime check |
| `INSTALL_APP.sh` | `policy/safety.sh` | `PROTECTED_PKGS` and the home-declaration gate |
| `INSTALL_APP.sh` | deleted | its local `local_md5`, which duplicates the facade's |
| `TOOLS.sh` | `domain/device_info.sh` | the device, storage, memory, CPU, display and service queries |
| `TOOLS.sh` | `domain/tool_actions.sh` | `run_adb_command`'s device half, the launcher-activity query, the stock-launcher home reset |
| `TOOLS.sh` | `workflow/tools.sh` | `reset_default_launcher`, `get_menu_entry`, `count_menu_items`, the menu tables |
| `TOOLS.sh` | stays | `section_items` and the menu rendering, which are presentation |
| `PROJECTOR.sh` | `ui/render.sh` | `bar`, `human`, `hr`, `clear_screen` as `render_*` |
| `PROJECTOR.sh` | `workflow/device_status.sh` | `detect_state`'s device and backup probing |

## Transport contract

One generic executor, no shell `eval` of a command string. Proposed signatures, not run:

```sh
adb_t_run <verb> [args...]     # runs: "$PT_ADB_BIN" "$verb" "$@"
```

Verb coverage sufficient for the toolkit: `shell`, `exec-out`, `push`, `pull`, `install`, `reboot`,
`backup`, `restore`, `devices`, `get-state`, `wait-for-device`.

Proposed signatures, not run:

```sh
transport_init                 # rc 0 ready; rc 2 refused with a plain stderr reason. Idempotent.
transport_selected_bin         # VALUE: absolute path actually selected.
adb_t_root_probe               # NONE. Sets SU_MODE. rc 0 when root established.
adb_t_root_exec  <cmd>         # VALUE: payload, sentinel stripped. rc: true remote status.
                               #   125: quote in cmd, absent sentinel, or root not established.
adb_t_root_stream <cmd>        # BINARY only. Far-side stderr suppressed inside the implementation.
adb_t_root_stream_watched <cmd> <out> [stall_secs]   # NONE. rc 0 complete; 124 stalled and reaped.
adb_t_remote_size <path>       # VALUE: integer. rc 0 present; 1 missing; 2 unreadable or malformed.
```

Preserved unchanged: the sentinel mechanism carrying the true remote status, 125 for a single quote in
the command and for an absent sentinel, 125 for unestablished root, 124 for a reaped stall, `exec-out`
rather than `shell` for binary, the far-side stderr suppression living inside the implementation
rather than at the call site, and reaping grandchildren.

`adb_t_remote_size` is a new API that distinguishes zero from missing from error, and callers handle
the statuses explicitly. The legacy never-fails-the-caller `adb_remote_size` survives only as a
compatibility alias until its callers migrate.

**Selection, validated in this order.** Validate the mode token first; an unrecognised
`PT_TRANSPORT` is refused. In `fake` mode `PT_ADB_BIN` must be set, absolute, executable, and the
test runner's canonical fake; anything else is refused. In `live` mode an explicitly set `PT_ADB_BIN`
must be absolute and executable and is refused rather than silently replaced; `PATH` is consulted only
when it is unset. Every `adb_t_*` method calls the init guard first. `SU_MODE` is declared empty at
source time and set only by `adb_t_root_probe`, so sourcing the module performs no probe and has no
root side effect.

## Status protocol: atomic snapshot

No journal and no shared pointer file. One run directory, one snapshot file, exactly one writer.

The caller allocates a unique run directory with `mktemp -d` under `.projector-status/run.XXXXXXXX`
and passes it as `PT_RUN_DIR`. A workflow started standalone allocates its own when the variable is
absent. The snapshot is written to a temporary file **inside that same run directory** and renamed
over `status`, so the rename is same-filesystem and a reader sees either the old or the new complete
record. The per-run human log lives in the same directory rather than in one shared log file.

Single line, fixed field order, every field required. Proposed schema, not run:

```
v=1 run=<run-directory-basename> state=<running|complete|failed|cancelled> phase=<token> rc=<int|none> \
artifact=<none|unverified|verified|truncated|missing> backup_dir=<basename|none> \
bytes=<int> total=<int> blocks_done=<int> blocks_total=<int> stalls=<int>
```

The reader validates every field and its fixed position, rejects missing, unknown, reordered or
repeated keys, and compares `run` with the caller's run-directory basename. Counters are canonical
nonnegative decimal with at most 16 digits; `rc` is `none` or 0 through 255. Phases are
init/sysinfo/appdata/partitions/image/packaging/verify. Multiline input and wildcard expansion are
forbidden. Use array `read`, never unquoted shell expansion, source or eval. Complete requires rc 0,
artifact verified, phase verify and a selected backup directory; running requires rc none; failed
requires nonzero rc; cancelled requires 129, 130 or 143. Malformed is distinct from absent.
A supplied run directory with an existing snapshot is refused rather than reused.

`backup_dir` carries the **basename chosen by the producer**, so the front end never picks a directory
by listing for the newest one. The producer generates a basename containing no tab and no newline, and
the working directory path may contain spaces.

**Completion is a conjunction.** Proposed rule, not run:

```
complete := guarded_wait_rc == 0
            AND status.rc == 0
            AND status.state == complete
            AND status.artifact == verified
            AND status.run == expected_run
            AND backup_artifact_verify(<workdir>/<status.backup_dir>) == 0
```

The manifest-size check compares the image length against the manifest's recorded device size. It is
explicitly **not** a source checksum, not provenance, and not a hardware safety judgement; it detects
a short or unverifiable image and nothing more.

Every other combination is named rather than collapsed: terminal `failed` and `cancelled`; a
non-terminal record with a dead child; a missing or malformed snapshot, including with a child return
code of 0, which is indeterminate and never success; a complete marker contradicted by a nonzero child
return code, which is a failure; and a non-terminal record whose byte count equals its total, which is
not completion.

A unique run identity does not prevent two runs colliding on the same backup artifact directory, so a
separate **one-active-backup-per-workdir lock** is required. Acquiring it fails busy rather than
waiting, and a stale lock is never auto-deleted on a PID guess.

## Generated recovery packaging

The requirement is that the tools keep working inside a copied backup directory with no checkout.
Sourcing repository libraries was rejected: it breaks the moment the directory moves, which is the
situation a restore tool exists for. Instead the generator inlines the helpers the artifact actually
needs, including the transport executor, at generation time, with no runtime reference to a checkout.

Compatibility is stated as **interface and format compatibility**, not byte compatibility: adding a
marker comment changes the bytes. The menu, the option numbering and the prompts are preserved under
extraction and exercised against the fake. Copy-independence is asserted by running the relocated copy
under an intercepting fake, not by grepping for the absence of a `source` line.

This is not an endorsement that the restore paths are safe. See the safety hold below.

## Test containment, described precisely

This is not an operating-system sandbox and not a security boundary. It makes the toolkit's known
invocation paths resolve to a stand-in and fails closed when the stand-in is absent.

Legacy callers reach the stand-in because it is placed on `PATH` as an executable named `adb`, which
is how the existing suites already work; explicit injection through `PT_ADB_BIN` arrives with the
adapter and takes over as consumers migrate.

The positive control must execute through the actually selected command path and prove it by decoding
a token only the fixture can produce, together with the fake's own invocation log. A self-report from
the adapter naming its chosen binary is not the control. The negative control is a deliberately placed
harmless sentinel named `adb` further down the path, which records if it is ever reached; a missing
fake must fail before any suite runs. Real `adb` is never used as a control.

Direct-path bypasses are enumerated and validated rather than assumed absent, because a call by
absolute path or through a dynamically built command string would not resolve through `PATH`.

## Alternatives considered and rejected

A universal workflow engine and a language rewrite were both excluded by the approved direction.
Structured JSON was rejected in favour of a fixed-field single line because the parsing stays small and
Bash-friendly, not because a parser is unavailable: `python3` is already a hard requirement of the
app-install path. A journal with a shared `current` pointer was rejected in favour of the atomic
snapshot, since one writer and one rename remove the torn-read and stale-pointer cases instead of
asking the reader to filter them. Removing unused transport helpers is a separate reviewed cleanup
inside the transport migration, after a reference audit, rather than an unannounced part of a move.

## Unresolved tensions

Several existing assertions match operator-facing text. The status protocol makes those strings
redundant as a machine channel while they remain load-bearing for the current suites, so they stay as
human text until contract tests replace them.

The stall tunable governs transfer blocks only, while the two probe call sites pass a fixed value.
Unifying that is a behavior change and is out of scope.

The proposed cancellation contract is INT/130, TERM/143 and HUP/129. The workflow stops and reaps
its owned transfers before releasing its own lock. The front end asks its workflow cancellation API
to stop its live child and no longer promises survival after terminal closure. Forced termination
cannot publish a terminal snapshot; a stale lock is not automatically removed.

Bash 3.2 is a compatibility target inherited from a recorded past failure, not a measured local fact.
A banned-construct grep is a heuristic and cannot establish compatibility; only execution under an
actual 3.2 shell can, and if that shell is unavailable the gate stays explicitly unverified.

## Recovery safety hold

Plan Task 19 records fake command traces for the current recovery hazards: a failed push reaches a
whole-device write, the successful push branch reboots without a restore write, the partition branch
lacks comparable integrity gates, and launcher state is passed onward without validation. These are
source observations awaiting controlled reproduction, not device-test results. This refactor preserves
artifact interfaces; it does not repair or endorse those algorithms. Separate approved safety changes
are required before hardware use or a safe-release claim. A partition image must not be compared with
the whole-device size, and malformed saved launcher state must not silently select a fallback.

## Non-goals

Root daemon or socket protocol changes. Any device action. `root/` contents. A new package dependency.
An AST-based dependency analyzer. Redesigning the raw restore algorithms, which is held for a separate
approved safety review. Integrating the untracked sibling documentation drafts, which are not present
in this worktree and belong to a separate owner-approved docs campaign.
