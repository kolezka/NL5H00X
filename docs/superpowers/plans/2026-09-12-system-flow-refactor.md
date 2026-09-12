# System Flow Refactor Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

## Goal

Separate the host toolkit into front ends, workflows, domain operations with an explicit safety policy,
and transport, without changing any CLI surface. Funnel every production ADB invocation through one
adapter. Replace the backup front end's prose parsing with an atomic status snapshot. Make the
generated recovery tools copy-independent.

## Architecture

One direction of dependency: front ends to workflow to policy to domain to transport. Presentation,
transport and progress are leaves. `scripts/lib/common.sh` is a low-level compatibility facade and must
never load `workflow/*`. `root/` is an external boundary no layer may depend on.

| Layer | May depend on | Home |
|---|---|---|
| front ends | workflow, presentation | `scripts/PROJECTOR.sh`, `scripts/TOOLS.sh` |
| CLI wrappers | workflow | `scripts/{MAKE_BACKUP,UNLOCK,INSTALL_APP}.sh` |
| workflow | domain, policy, progress, presentation, packaging; feature-local workflow modules | `scripts/lib/workflow/` (new), existing `scripts/lib/unlock.sh` |
| policy | domain | `scripts/lib/policy/` (new) |
| domain | transport | `scripts/lib/domain/` (new) |
| transport, presentation, progress | nothing | `scripts/lib/{transport,ui,progress}/` (new) |
| compatibility facade | domain, transport, progress, presentation | `scripts/lib/common.sh` |
| packaging | transport and local file operations, at generation time | `scripts/lib/packaging/` (new) |

The table lists cross-layer dependencies. Acyclic same-layer helper imports are allowed, such as
home operations loading the domain profile and render loading UI colors. The permitted feature-local
workflow edge is `workflow/unlock.sh` loading `lib/unlock.sh`, never the reverse. New modules must not source `common.sh`; it serves legacy consumers only. Each new module
sources its own lower-level dependencies with a guarded module-relative path. Wrappers compute
`SCRIPT_DIR` as the existing scripts directory and initialize feature options inside their workflow
entrypoint, not through source-time probes. `APK_DIR` defaults at unlock workflow initialization.

Settled, not open: transport must not source `ui/log.sh` nor call any `log_*` or `print_*`; it may
`printf` a plain diagnostic to stderr. Domain must not depend on presentation. Colors live in
`ui/colors.sh`. The source-time prohibition covers probes, device actions and output; path resolution
and dependency loading at source time are allowed.

## Tech Stack

Bash 3.2 is the **compatibility target, not a verified local version**. A local version check was
attempted and blocked by the worktree guard, so no version check completed successfully. The floor's
origin is a recorded rationale in `scripts/TOOLS.sh`: `local -n` needs bash 4.3, macOS ships 3.2, and
`TOOLS.sh` died on its first menu draw until the nameref was replaced with `eval` indirection.

No `declare -A`, no `local -n`, no `readarray`, no `mapfile`. No new package dependencies. Existing
tools only: `adb`, `python3`, `unzip`, `dd`, `awk`, `sed`, `grep`, `md5`/`md5sum`, `stat`. ShellCheck
0.11.0 is reported available by the coordinator as a static check; this session did not run it.

## Spec path

`docs/superpowers/specs/2026-09-12-system-flow-refactor-design.md`

## Global Constraints

- **Every code block below is a proposed example, not run.** Acceptance statements are future required
  checks, not observed results. Reading existing source verifies current code shape only, never a
  snippet here. Final runtime suite execution and behavior under an actual Bash 3.2 shell are
  explicitly unverified.
- Commands quote the worktree root, defined once per shell:
  `WT="/Users/me/Development/NL5H00X/.claude/worktrees/docs+system-flow-refactor"`. No raw
  `git worktree` operations.
- A script named NEW is implemented in its own task before any later task invokes it.
- Main checkout and device stay untouched. No commits; checkpoints need the operator's go-ahead.
- No device action, no `adb` against hardware, no raw restore write anywhere. Restore paths are
  exercised only through an intercepting fake that records command traces.
- Pure extractions keep semantics. A behavior change is a separate task with its own regression test.
- Characterization is not red/green: those tests pass on the untouched baseline and none may require a
  change.
- No blanket fallback in a shared layer.
- **Legacy terminating wrappers stay.** `require_device` and `require_backup` exit from inside the
  facade. Do not convert exit to return globally. New lower-level operations return status; a wrapper is
  removed only after a call-site scan shows every consumer handles the returned status.
- **Legacy `print_status`, `print_success`, `print_step` keep their current stdout routing.** New
  `log_*` helpers write to stderr from introduction. There is no global stream-flip task.
- Domain and workflow functions must not rely on `errexit`, since invoking a function in a conditional
  disables it. Check each relevant command explicitly and characterize CLI strict-mode behavior.
- Private module functions take a module prefix; workflows expose only the public functions named in
  their task. No nested function definitions. Inside extracted domain modules, replace calls to legacy
  transport aliases with `adb_t_*` calls and load the adapter explicitly; do not rely on caller-loaded
  `common.sh` functions. Test sourcing each module alone under `set -u` before testing composition.

## Dependency order and commands

Tasks 1 and 2 establish the test foundation. Tasks 3 through 8 build shared modules. Tasks 9 through 14
migrate workflows and front ends. Tasks 15 through 20 cover packaging, contracts and release holds.
Within this plan use the listed order; multiple writers must not share a worktree. Each task is a
review checkpoint, not permission to create a commit.

After Task 1 exists, run `"$PT_TEST_BASH" "$WT/tests/local/run.sh"` from the assigned worktree.
The runner derives the repository root from its own location, discovers only `tests/contracts/*.sh`
and explicitly listed legacy/control suites, and runs each in a fresh shell with controlled PATH and
state. Add newly created suites to this runner in their owning task. Set `PT_TEST_BASH` to a verified
absolute interpreter path; Task 18 adds the separate actual-3.2 execution gate. Tool failures or absent
fixtures are failures, not skips. Examples below have not been executed.

---

## Task 1: Containment runner, owned-child lifecycle, suite cleanup

**Files (new):** `tests/local/{run.sh,lifecycle.sh,controls.sh,sentinel-adb}`
**Files (edit):** `tests/fake-adb/adb`, `tests/{run-tests,unlock-tests,ui-tests}.sh`
**Produces (new):** `child_spawn <label> <cmd...>`, `child_wait_reap <pid>`, `child_release_all`

Source-confirmed hazard, not a runtime-confirmed bug: `tests/unlock-tests.sh` ends by counting with
`pgrep -f 'sleep 600'` and killing with `pkill -f 'sleep 600'`, which match any process on the machine
carrying that text. The producer lives in `tests/fake-adb/adb`, reached by a knob whose only scenario is
in `tests/run-tests.sh`, a different suite, so the guard sits where the hazard is not. Never run the
existing reaper to demonstrate this.

- [ ] 1.1 Write `lifecycle.sh` around children owned by the current shell. `child_spawn` assigns
      `CHILD_PID=$!` in that shell; do not call it through command substitution. Register the child,
      intersect the registry with the shell's active jobs before signalling, wait to reap it, and remove
      its registry entry immediately. `child_wait_reap <pid>` returns the child's status.
      `child_release_all` sends TERM, allows a bounded grace period, then sends KILL only to still-owned
      active jobs and waits for them. A saved PID file is not proof of ownership. Test normal exit,
      cancellation, empty registry, already-exited child and a separate untracked witness.
- [ ] 1.2 Build the reaper RED using harmless `pgrep` and `pkill` executables on the controlled PATH.
      They record argv without signalling; the pgrep stub prints a synthetic PID to reach the old branch.
      Stub `kill` as a shell function as well, because Bash's builtin does not resolve through PATH.
      The test forbids pattern targets. It must fail against the instrumented old cleanup and pass for
      the owned-child implementation. Never invoke the live old `pkill`. Proposed test seam, not run:
      ```sh
      kill() { printf '%s\n' "$*" >> "$CONTROL_LOG"; }
      ```
- [ ] 1.3 Replace the reaper block in `tests/unlock-tests.sh` with `child_release_all`.
- [ ] 1.4 Give the fake process ownership of its simulated sleep child: launch it in the background,
      keep its live child handle, and trap cancellation to terminate and wait for it. The suite owns the
      fake process, not a sleep PID imported from another process. Record IDs for diagnostics only.
      Verify both the fake process and its sleep exit while an unrelated witness remains alive.
- [ ] 1.5 Change scenario cleanup **in each suite explicitly**, since an unconditional per-scenario
      `rm -rf` cannot be overridden by an outer runner. Edit those points in all three suites to keep the
      sandbox and print its path on failure. The truncation scenario's chunk-file evidence must survive.
- [ ] 1.6 Place the canonical fake on `PATH` as an executable named `adb` for legacy callers, which is
      how the suites already reach it. Explicit `PT_ADB_BIN` injection arrives in Task 4.
- [ ] 1.7 Write the positive control so it executes through the **actually selected command path**: the
      fake emits a token only it can produce from a value seeded into the fixture, and appends every
      invocation to a log in the state directory. The control asserts both the decoded token and the
      expected log entry. An adapter self-report naming its binary is not the control.
- [ ] 1.8 Install the harmless `tests/local/sentinel-adb` at `<control-dir>/sentinel/adb`, behind the
      fake on PATH. First invoke this sentinel explicitly and verify its recorded token to validate the
      detector. Clear only that control's log, then assert missing and non-executable fake selections
      stop before any suite or sentinel invocation. Validate both explicit adapter and legacy PATH
      routes. Real `adb` is never a control.
- [ ] 1.9 Enumerate and validate direct-path bypasses, since an absolute-path call or a dynamically built
      command string does not resolve through `PATH`. Record counts and forms as this run's baseline file
      and compare later runs against that file, not against a number in this plan:
      ```sh
      rg -n '(^|[^-_./[:alnum:]])adb[[:space:]]' "$WT/scripts/"
      rg -n '/adb|\$\{?ADB|command -v adb|which adb' "$WT/scripts/"
      rg -n '\beval\b' "$WT/scripts/"
      ```
- [ ] 1.10 Write `run.sh`: fixed suite order, `PATH` and state setup, traps on `EXIT`/`INT`/`TERM` calling
      `child_release_all`, and the controls plus the bypass audit **before** the suites. Its header states
      that this makes the toolkit's known invocation paths resolve to the stand-in and fails closed when
      the stand-in is absent, and that it is not an operating-system sandbox or a security boundary.

**Required checks:** runner executes the three suites and reports results. Positive control decodes the
seeded token and finds the expected invocation. Sentinel never recorded. A missing or non-executable fake
aborts before any suite. Stubbed reaper test shows only tracked-PID targets. A failed scenario leaves its
sandbox with the path printed. Bypass baseline recorded.

---

## Task 2: Real AXML fixtures and baseline characterization

**Files (new):** `tests/fixtures/make-apk.py`,
`tests/contracts/characterize-{app-install,recovery,backup-signal}.sh`

The app-install manifest gate parses a binary `AndroidManifest.xml` out of the APK zip with an embedded
Python decoder. A `.meta` sidecar is read by the fake device, so it exercises no part of that parser.

- [ ] 2.1 Write `make-apk.py` using only `struct` and `zipfile`. Emit minimal but structurally valid
      AXML: the chunk header, a string pool, and a `manifest` start tag carrying a `package` attribute.
      Four variants: UTF-16 pool without home categories, UTF-8 pool without them, one declaring
      `android.intent.category.HOME`, and one carrying `lib/<abi>/*.so` for an ABI the fixture device does
      not report.
- [ ] 2.2 Characterize the parser against those fixtures: package name extracted for both pool
      encodings; `HOME=yes` only for the declaring variant; an `ERROR=` result for a non-manifest input;
      the ABI mismatch refusal for the native variant. A `.meta` sidecar may still seed fake-device state
      where a test needs the device to know a package, never in place of a real fixture.
- [ ] 2.3 Characterize the rest of the install surface with no device write: home-declaration refusal
      without the allow flag, upload checksum comparison, removal refusal for each protected package, and
      help output.
- [ ] 2.4 Characterize the generated recovery artifact through an intercepting fake recording a command
      trace, running no raw write. Cover a success and a failure trace for each menu option, record the
      current option numbering and prompts, and add the relocation case by driving a copy from a fresh
      path. Record observed hazards for the Task 19 hold without changing any of them.
- [ ] 2.5 Characterize the current backup completion signal and the progress inputs the front end reads,
      giving Task 11 a baseline for what it replaces.
- [ ] 2.6 Build the fake block fixture later checks use: a small file standing in for a block device plus
      a manifest whose recorded size matches it.

**Required checks:** all characterization suites pass against unmodified `scripts/`, each recording
observations to a file later tasks read. No assertion requires a code change.

---

## Task 3: Presentation modules

**Files (new):** `scripts/lib/ui/{colors,log,render,legacy}.sh` **Files (edit):** `scripts/lib/common.sh`
**Produces (new):** `log_info|log_ok|log_warn|log_error|log_step <msg>` (all stderr);
`render_header <title>`, `render_section <title>`, `render_size <bytes>`, `render_bar <pct> [width]`,
`render_hr`

- [ ] 3.1 Create `colors.sh` holding the color constants, include-guarded so the `readonly` assignments
      run once. Only `log.sh` and `render.sh` source it; no other layer depends on it.
- [ ] 3.2 Create `log.sh` with the five writers, all to stderr from introduction, keeping the existing
      bracketed prefixes that operators and the suites read.
- [ ] 3.3 Create `render.sh`: `render_header` and `render_section` from the facade, `render_size` from
      `human_size` preserving its decimal arithmetic exactly, and `render_bar` and `render_hr` from the
      front end's own `bar` and `hr`, which gives `render_bar` its consumer in Task 11.
- [ ] 3.4 Define the legacy presentation names in `ui/legacy.sh`, sourced by the facade and by migrated
      CLI workflows that retain old human output. `print_warning` and `print_error` keep stderr;
      `print_status`, `print_success` and `print_step` keep stdout. `print_header`, `print_section`
      and `human_size` delegate to render functions. Move `confirm` and `pause` here as well, preserving
      their signatures and input channels. No migrated workflow should import the whole facade merely
      to obtain a presentation helper.

**Required checks:** existing suites pass. Size-formatting and `print_warning` stderr assertions hold.
`/bin/bash -n` parses changed files. Legacy `print_*` definitions are confined to `ui/legacy.sh`;
new log/render code does not call them.

---

## Task 4: Transport adapter with validated selection

**Files (new):** `scripts/lib/transport/{adb,select}.sh`, `tests/contracts/transport.sh`
**Files (edit):** `scripts/lib/common.sh`
**Produces (new):** `transport_init`, `transport_selected_bin`, `adb_t_run <verb> [args...]`,
`adb_t_root_probe`, `adb_t_root_exec <cmd>`, `adb_t_root_stream <cmd>`,
`adb_t_root_stream_watched <cmd> <out> [stall_secs]`, `adb_t_remote_size <path>`,
`adb_t_kill_tree <pid>`

- [ ] 4.1 Write the generic executor, with no `eval` of a command string. Verb coverage: `shell`,
      `exec-out`, `push`, `pull`, `install`, `reboot`, `backup`, `restore`, `devices`, `get-state`,
      `wait-for-device`. Proposed example, not run:
      ```sh
      adb_t_run() { transport_init || return 2; "$PT_ADB_BIN" "$@"; }
      ```
- [ ] 4.2 Write selection with the mode validated **first**, an absolute executable required, the
      canonical fake required in fake mode, an invalid explicit path refused in live mode rather than
      silently replaced, and `PATH` consulted only when `PT_ADB_BIN` is unset. Proposed example, not run:
      ```sh
      transport_init() {
          case "${PT_TRANSPORT:-live}" in
            fake)
              [[ -n "${PT_ADB_BIN:-}" ]] || { printf 'transport: fake needs PT_ADB_BIN\n' >&2; return 2; }
              [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] \
                  || { printf 'transport: PT_ADB_BIN must be absolute and executable\n' >&2; return 2; }
              [[ "$PT_ADB_BIN" == "${PT_FAKE_ADB_CANONICAL:-}" ]] \
                  || { printf 'transport: fake mode accepts only the canonical fake\n' >&2; return 2; } ;;
            live)
              if [[ -n "${PT_ADB_BIN:-}" ]]; then
                  [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] \
                      || { printf 'transport: explicit PT_ADB_BIN invalid; refusing\n' >&2; return 2; }
              else
                  PT_ADB_BIN=$(command -v adb 2>/dev/null) \
                      || { printf 'transport: adb not on PATH\n' >&2; return 2; }
                  [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] \
                      || { printf 'transport: PATH must select an absolute executable file\n' >&2; return 2; }
              fi ;;
            *) printf 'transport: unknown PT_TRANSPORT\n' >&2; return 2 ;;
          esac
          return 0
      }
      ```
      Every `adb_t_*` method calls the guard first.
- [ ] 4.3 Move the root helpers in unchanged in behavior: the sentinel carrying the true remote status,
      125 for a single quote in the command, 125 for an absent sentinel, 125 for unestablished root, the
      carriage-return normalisation, and the payload trim. Diagnostics are plain `printf` to stderr, never
      `log_*` or `print_*`.
- [ ] 4.4 Move the binary stream helper preserving `exec-out` rather than `shell` and keeping far-side
      stderr suppression inside the implementation, not at the call site. Move the watched variant
      preserving its 124 on a reaped stall, and `kill_tree` as `adb_t_kill_tree`.
- [ ] 4.5 Declare `SU_MODE` empty at source time and set it only in `adb_t_root_probe`, so sourcing
      performs no probe and has no root side effect. Document that ordering in the module header.
- [ ] 4.6 Add `adb_t_remote_size` distinguishing rc 0 present, rc 1 missing, rc 2 unreadable or
      malformed, with callers handling the statuses explicitly. Keep the legacy never-fails-the-caller
      size helper as a compatibility alias only, until its callers migrate.
- [ ] 4.7 Alias used legacy helper names in the facade to the adapter so current consumers keep working.
      Audit references to `adb_exec`, `adb_start_activity` and `adb_start_action` in tracked code,
      including dynamic dispatch. Remove unused helpers in a separately reviewed cleanup within this
      task; migrate any discovered consumer instead. Do not leave raw-ADB or eval-based execution in
      the facade for the final checker to exempt. Route `check_adb` and `check_device_connected`
      through adapter selection and `adb_t_run devices` while preserving their existing CLI behavior.
- [ ] 4.8 Write the contract suite: 125 for a single-quoted command; 125 with `SU_MODE` empty; payload
      excludes the sentinel; the binary helper emits bytes with no diagnostic on stdout; 124 on a stalled
      watched stream with the child registered; rc 0, 1 and 2 from the size API; and each selection
      refusal from 4.2.
- [ ] 4.9 Switch the Task 1 controls to explicit `PT_ADB_BIN` injection, keeping `PATH` placement for
      suites not yet migrated.

**Required checks:** existing suites pass. Contract suite passes every enumerated case.
`rg -n 'log_|print_|source .*ui/' "$WT/scripts/lib/transport/"` returns nothing.

---

## Task 5: Backup artifact, backup IO and file operations

**Files (new):** `scripts/lib/domain/{backup_artifact,backup_io,file_ops}.sh`,
`tests/contracts/backup-artifact.sh` **Files (edit):** `scripts/lib/common.sh`
**Produces (new):** `backup_manifest_write <dir> <size> <block> <method>`,
`backup_manifest_field <dir> <field>`, `backup_artifact_verify <dir>`,
`backup_dir_find_verified <base>`, `backup_dir_find_incomplete <base>`, `backup_device_size`,
`backup_device_free`, `backup_stage_and_pull <partition> <out>`, `file_size <path>`, `file_md5 <path>`,
`file_script_dir <source_path>`

- [ ] 5.1 Move the manifest and verification functions into `backup_artifact.sh`, keeping the manifest
      filename and its four recorded fields.
- [ ] 5.2 Preserve the four distinct verification return codes: verified, no image, no usable manifest,
      size mismatch. The facade renders a different message per code, and missing versus truncated is the
      point of that path.
- [ ] 5.3 Preserve the incomplete-directory test exactly: image present, manifest absent, newest by the
      existing glob ordering.
- [ ] 5.4 Move the device size and free-space queries and the remote staging and pull steps into
      `backup_io.sh`, so a workflow reaches the device through domain rather than the adapter directly.
      Migrate them to the new size API's explicit statuses.
- [ ] 5.5 Move size and checksum operations into `file_ops.sh`, preserving their portable fallbacks.
      Add `file_script_dir <source_path>` with an explicit argument for new callers. Keep the legacy
      `get_script_dir` body in the facade until its consumers migrate: its `BASH_SOURCE[0]` refers to
      its defining file, so moving it would change its result. Test paths containing spaces, symlinks,
      the actual worktree/main split and a caller whose working directory is elsewhere.
- [ ] 5.6 Keep `require_backup` in the facade with its `exit` and its full operator explanation. Alias
      every moved name.
- [ ] 5.7 Write the contract suite asserting each verification code from constructed directories, and
      that a hand-built pre-refactor directory holding only an image and a manifest with a recorded size
      still verifies. That is the archive compatibility contract.

**Required checks:** existing suites pass, including truncation rejection. Contract suite passes. The
legacy directory verifies. `rg -n 'print_|log_' "$WT/scripts/lib/domain/"` returns nothing.

---

## Task 6: Mount, package, settings and home domain modules

**Files (new):** `scripts/lib/domain/{profile,mount,package,settings,home}.sh`,
`tests/contracts/domain-unlock.sh` **Files (edit):** `scripts/lib/unlock.sh`
**Produces:** existing names in new homes: `system_mountpoint`, `system_is_rw`, `system_rw`,
`system_ro`; `package_installed <pkg>`, `package_disabled <pkg>`, `package_path <pkg>`,
`component_disabled <pkg> <comp>`; `setting <namespace> <key>`; `home_activity`,
`home_component_of <pkg>`, `home_interceptor`, `home_owner`. Names are preserved, not renamed.

- [ ] 6.1 Move the mount operations, keeping the positional-field mount test, the system-as-root
      fallback, and the read-back verification before reporting success. Replace their `print_error` calls
      with a plain stderr `printf` or a returned diagnostic, per the settled domain rule.
- [ ] 6.2 Move the package predicates, keeping the disabled-components parser, which answers a different
      question from the disabled-packages listing.
- [ ] 6.3 Move `setting` into `settings.sh` and the four home resolvers into `home.sh`, keeping the
      two-pass preference read, on-device component resolution rather than a hardcoded component, and the
      interceptor precedence.
- [ ] 6.4 Put shared vendor identity constants (`STOCK_LAUNCHER`, `HOME_DISPATCHER_PKG`,
      `HOME_DISPATCHER_COMP`, `FALLBACK_HOME_COMP`) in guarded `domain/profile.sh`, preserving values.
      Domain modules source that profile rather than reading caller-defined workflow globals. Keep
      replacement-launcher selection (`LAUNCHER_*`), the step protocol/list, settings and leftovers
      tables, launcher checks, APK glob lookup and repair sequencing in `lib/unlock.sh`. It sources
      the new modules so existing consumers keep working. TOOLS migrates its duplicate vendor identity
      to the same profile in Task 14; do not generalize this into a multi-device plugin system.
- [ ] 6.5 Do not change the tolerated-failure calls in the apply and revert paths. Each is followed by a
      read-back that decides success; removing the tolerance under `errexit` would change control flow.
- [ ] 6.6 Write the contract suite: the mountpoint answer for both mount layouts; the remount reporting
      failure rather than success when it does not take; interceptor precedence in the home owner; and
      exercise the seeded fixture's partially-unlocked profile, which no suite currently uses.

**Required checks:** unlock suite passes every scenario. Contract suite passes. `scripts/INSTALL_APP.sh`
is unedited and still works.

---

## Task 7: APK and device-info domain modules

**Files (new):** `scripts/lib/domain/{apk,device_info}.sh`, `tests/contracts/apk.sh`
**Files (edit):** `scripts/INSTALL_APP.sh`
**Produces (new):** `apk_facts <apk>`, `apk_abis <apk>`, `abi_to_isa <abi>`, `apk_default_name <apk>`,
`device_model`, `device_prop <name>`, `device_storage_line`, `device_abilist`,
`device_service_running <name>`

- [ ] 7.1 Move the four APK functions into `apk.sh`. The embedded Python decoder moves verbatim,
      including its offset-array comment, its default pool encoding, its sanity check against a string
      every manifest must contain, and its `ERROR=` outputs.
- [ ] 7.2 Delete the duplicate checksum helper in `scripts/INSTALL_APP.sh`, which shadows the facade's
      identical intent. Confirm one definition remains with `rg -n 'local_md5|file_md5' "$WT/scripts/"`.
- [ ] 7.3 Repoint `scripts/INSTALL_APP.sh` to source the mount and package modules directly instead of
      the whole unlock library, since those are the operations its own comment says it needs.
- [ ] 7.4 Assert help output and a removal refusal still run with `APK_DIR` unset. This is a
      coupling check, not a reproduced crash: the old installer does not call `launcher_apk`, so its
      unguarded dereference is not reached on that path.
- [ ] 7.5 Move the device queries out of `scripts/TOOLS.sh` into `device_info.sh`, so the front end stops
      calling the device directly.
- [ ] 7.6 Extend the APK contract suite against the Task 2.1 fixtures: both pool encodings, the
      home-declaring variant, the non-manifest input, and the ABI mapping including an unknown ABI.

**Required checks:** Task 2 app-install characterization passes unchanged. One checksum helper remains.
The entrypoint runs with `APK_DIR` unset. Contract suite passes every fixture variant.

---

## Task 8: Explicit safety policy module

**Files (new):** `scripts/lib/policy/safety.sh`, `tests/contracts/policy.sh`
**Produces (new):** `policy_package_protected <pkg>`, `policy_model_supported <model> <device>`,
`policy_home_declaration_allowed <facts> <allow_flag>`, `policy_backup_gate <dir>`

- [ ] 8.1 Move the protected-package list behind `policy_package_protected`, keeping all entries and the
      `readonly` form.
- [ ] 8.2 Move the supported-device list and expose `policy_model_supported`, returning status only. The
      entrypoint's `check_supported_device` keeps its name, rendering and `exit`.
- [ ] 8.3 Add `policy_home_declaration_allowed`, wrapping the decision currently inline in the install
      path.
- [ ] 8.4 `policy_backup_gate` takes an **explicit directory** and returns rc only, mirroring the four
      verification codes. It prints nothing, so no path has to survive space-delimited formatting, and the
      caller already owns the directory it passed.
- [ ] 8.5 Add no fallback. Each function returns a decision; a policy answering "allow" on internal error
      would disable a gate for every consumer.
- [ ] 8.6 Write the contract suite: each protected package refused; an unknown model refused; each of the
      four gate codes from constructed directories; a directory path containing a space handled correctly;
      no policy function writing to stdout.

**Required checks:** contract suite passes. `rg -n 'exit |printf|echo' "$WT/scripts/lib/policy/"` shows
no output statement and no exit.

---

## Task 9: Status snapshot and work-directory lock

**Files (new):** `scripts/lib/progress/{status,lock}.sh`, `tests/contracts/status-protocol.sh`
**Produces (new):** `status_run_dir_alloc <workdir>`, `status_write <run_dir> <field>=<value>...`,
`status_read <run_dir>`, `status_field <record> <key>`, `status_validate <record> <expected_run>`,
`lock_acquire <workdir>`, `lock_release <workdir>`

- [ ] 9.1 Allocate the run directory with `mktemp -d` under `.projector-status/run.XXXXXXXX` in the work
      directory. The caller allocates and passes `PT_RUN_DIR`; a workflow started standalone allocates its
      own when absent. The per-run human log lives there, so no log file is shared between runs.
- [ ] 9.2 Write the snapshot to a temporary file **inside the same run directory** and rename it over
      `status`, keeping the rename same-filesystem so a reader sees either the old or the new complete
      record. Exactly one writer per run directory; there is no pointer file.
- [ ] 9.3 Fixed-field single-line schema, all required in this order: `v`, `run`, `state`, `phase`,
      `rc`, `artifact`, `backup_dir`, `bytes`, `total`, `blocks_done`, `blocks_total`, `stalls`.
      `run` equals the basename of the newly allocated run directory. Reject a supplied `PT_RUN_DIR`
      containing a prior snapshot; it is a handoff to one writer, never permission to reuse an old run.
- [ ] 9.4 `status_validate <record> <expected_run>` returns 0 for valid and 2 for malformed input.
      Reject multiline input, unknown or reordered keys, duplicate/missing fields, wildcard characters,
      invalid phases and integer overflow. Parse without word expansion, source or eval. Proposed
      field-reader example, not run; implement the value checks immediately after this block:
      ```sh
      local rec="$1" expected_run="$2" i
      local -a fields keys
      case "$rec" in *$'\n'*|*$'\r'*|*$'\t'*) return 2 ;; esac
      keys=(v run state phase rc artifact backup_dir bytes total blocks_done blocks_total stalls)
      IFS=' ' read -r -a fields <<< "$rec"
      [[ "${#fields[@]}" -eq "${#keys[@]}" ]] || return 2
      for ((i=0; i<${#keys[@]}; i++)); do
          [[ "${fields[$i]}" == "${keys[$i]}="* ]] || return 2
      done
      [[ "${fields[0]}" == v=1 && "${fields[1]}" == "run=$expected_run" ]] || return 2
      ```
      Value checks: state is running/complete/failed/cancelled; phase is
      init/sysinfo/appdata/partitions/image/packaging/verify; artifact is
      none/unverified/verified/truncated/missing. Counters are canonical decimal (`0` or a nonzero
      leading digit followed by digits), at most 16 digits, so planned percentage arithmetic fits
      signed 64-bit Bash arithmetic. `rc` is `none` or a decimal status from 0 to 255.
      `backup_dir` is `none` before selection or `projector-backup-` followed by letters, digits,
      underscores, dots or hyphens, never a slash. Complete requires rc 0, artifact verified, phase
      verify and a selected directory; running requires rc none; failed requires nonzero rc;
      cancelled requires 129, 130 or 143. End with an explicit return 0 only after every check.
- [ ] 9.5 Bind `backup_dir` to the **basename the producer selected**, so the consumer never picks a
      directory by listing for the newest. The basename contains no tab and no newline; the work directory
      path may contain spaces.
- [ ] 9.6 Implement the one-active-backup-per-work-directory lock. Acquisition fails busy rather than
      waiting. A stale lock is never auto-deleted on a PID guess; recovering one is an explicit operator
      action.
- [ ] 9.7 Write the contract suite covering: missing status file; unknown field; duplicated field;
      malformed integer; malformed state token; truncated line; a reader seeing old then new across a
      rename; terminal failed; a complete marker contradicted by a nonzero child rc; a non-terminal record
      whose bytes equal its total; missing status with child rc 0; a stale run directory from an earlier
      run; a busy lock refusing a second acquisition.

**Required checks:** contract suite passes every enumerated case. Nothing consumes the module yet, so
existing suites are unaffected.

---

## Task 10: Backup workflow and CLI wrapper

**Files (new):** `scripts/lib/workflow/backup.sh` **Files (edit):** `scripts/MAKE_BACKUP.sh`
**Produces (new):** `workflow_backup_run [args...]` as the single public entrypoint, with private
`_backup_sysinfo`, `_backup_appdata`, `_backup_partition`, `_backup_stream`, `_backup_chunked`,
`_backup_direct`, `_backup_verify`

- [ ] 10.1 Move phases into module-level private functions with the `_backup_` prefix, with no nested
      definitions. Keep phase order, method selection, recorded method and existing tunables. Carry
      `create_restore_scripts` unchanged as `_backup_create_restore_scripts` in this module until
      Task 15 extracts packaging; do not leave the new wrapper depending on a removed function.
- [ ] 10.2 Keep the stall tunable applying to transfer blocks only, and the fixed value at the two probe
      call sites. Unifying them is a behavior change and is out of scope.
- [ ] 10.3 Route device calls through `domain/backup_io.sh` and the adapter, never `adb` directly, so the
      checker's raw-adb rule holds for this file.
- [ ] 10.4 Emit a snapshot at each phase boundary. Take `blocks_done` and `blocks_total` from the transfer
      loop's own counters, never a rendered percentage. Increment `stalls` when the watched stream reports
      a reaped stall. Write the selected backup directory basename into every snapshot.
- [ ] 10.5 Keep the existing human output, including the current success line, so the CLI surface and the
      current suites are unchanged. The snapshot is added beside it.
- [ ] 10.6 Emit the terminal snapshot from the one place that already decides pass or fail: complete with
      rc 0 and a verified artifact only when verification succeeded and the manifest was written, otherwise
      failed with the observed rc and the artifact state from verification. Failing to write a terminal
      snapshot must leave a non-success or indeterminate outcome, never an assumed success.
- [ ] 10.7 Install cancellation: INT records cancelled and exits 130; TERM does the same with 143;
      HUP does the same with 129. Stop and reap owned transfer children before releasing the workdir
      lock. Preserve partial evidence. Release only this process's acquired lock, never a pre-existing
      lock. The new cancellation behavior needs dedicated tests. SIGKILL cannot be trapped: its stale
      lock remains an explicit recovery action and its non-terminal snapshot is not success.
- [ ] 10.8 Do not rely on `errexit`. Check each relevant command explicitly and use a guarded wait so a
      failing child cannot be hidden: `if wait "$pid"; then rc=0; else rc=$?; fi` (proposed, not run).
- [ ] 10.9 Reduce `scripts/MAKE_BACKUP.sh` to a wrapper sourcing the library, forwarding `"$@"` and
      exiting with the return code. Keep the shebang, the strict-mode line and the path, and characterize
      the strict-mode behavior rather than assuming it.
- [ ] 10.10 Write cancellation checks for INT/130, TERM/143 and HUP/129 using fixture-owned children.
      Each yields a cancelled snapshot with the corresponding status, no success line, retained partial
      evidence and reaped transfer children. Check forced termination only inside the fake fixture:
      no terminal snapshot must mean aborted/indeterminate, and the stale lock must not be removed.

**Required checks:** backup suite passes every scenario, including truncation, hang, resume,
contamination and the staged fallback. Task 2.5 characterization passes. A healthy run's snapshot is
terminal complete with rc 0 and verified artifact; a truncated run's is terminal failed. The
cancellation and forced-termination cases pass. A second concurrent run in the same work directory fails busy.

---

## Task 11: Front-end backup migration

**Files (new):** `scripts/lib/workflow/device_status.sh`, `tests/contracts/front-end-status.sh`
**Files (edit):** `scripts/PROJECTOR.sh`, `scripts/lib/workflow/backup.sh`
**Produces (new):** `workflow_device_status`, `workflow_backup_start <workdir>`,
`workflow_backup_status <run_dir>`, `workflow_backup_outcome <run_dir> <child_rc> <workdir>`,
`workflow_backup_cancel <INT|TERM|HUP> <pid>`.
`workflow_device_status` retains the existing `DEV_*` display fields as explicit output variables.
`workflow_backup_start` allocates the run directory, starts the child with that directory and its
per-run log, and sets `PT_RUN_DIR` and `PT_BACKUP_PID` in the calling shell. Do not capture it with
command substitution. `workflow_backup_status` validates the snapshot and sets `PT_BACKUP_STATE`,
`PT_BACKUP_BYTES`, `PT_BACKUP_TOTAL`, `PT_BACKUP_BLOCKS_DONE`, `PT_BACKUP_BLOCKS_TOTAL` and
`PT_BACKUP_STALLS`; it prints no data. It returns 1 for absent status, 2 for malformed status and
clears prior display fields on either. `workflow_backup_outcome` prints exactly one of complete,
failed, cancelled, aborted or indeterminate and returns 0 for a classified outcome, 2 for invalid
arguments. Neither API exposes raw ADB or asks the UI to parse the snapshot schema.

- [ ] 11.1 Move device and backup probing out of the front end into `device_status.sh`, so the front end
      stops calling the device directly and uses workflow and presentation interfaces only.
- [ ] 11.2 Replace the three text-matching progress reads with the snapshot's stall count, block total
      and completed-block count.
- [ ] 11.3 Replace the success-string test with the conjunction: guarded wait rc 0, snapshot rc 0,
      snapshot state complete, and an independent manifest-size check on the directory the snapshot named.
      Percentage is not a term. Record in the comment that this check detects a short or unverifiable image
      and is not a checksum, not provenance and not a hardware safety judgement.
- [ ] 11.4 Let `workflow_backup_start` allocate and pass the run directory. The front end uses the
      returned run handle with workflow status APIs only. The workflow binds artifact verification to
      the snapshot's selected backup basename and rejects a record whose run token disagrees with its
      run handle; it never lists for the newest backup.
- [ ] 11.5 Render each non-success outcome distinctly: terminal failed; terminal cancelled; a dead child
      with a non-terminal snapshot; a missing or malformed snapshot, including with child rc 0, which is
      indeterminate and never success; a complete marker with a nonzero child rc, which is a failure; and a
      non-terminal snapshot whose bytes equal its total, which is not completion.
- [ ] 11.6 Handle INT, TERM and HUP through `workflow_backup_cancel`, which signals only the live
      child created by `workflow_backup_start` in this shell and waits for it before returning its
      status. Reject any other PID or signal. The child owns transfer cleanup and lock release.
      Production modules must not import `tests/local/lifecycle.sh`. Render cancellation consistently:
      closing the terminal cancels a managed run; do not retain the old survival reassurance.
- [ ] 11.7 Write the contract suite asserting every outcome in 11.5 from constructed snapshots without
      running a backup, plus a space-containing work directory path.

**Required checks:** front-end suite passes. Contract suite passes every enumerated outcome.
`rg -n 'BACKUP COMPLETE|grep -ac' "$WT/scripts/PROJECTOR.sh"` returns nothing.

---

## Task 12: App-install workflow and CLI wrapper

**Files (new):** `scripts/lib/workflow/app_install.sh`, `scripts/lib/domain/system_app.sh`,
`scripts/lib/domain/device_actions.sh`, `tests/contracts/app-install-workflow.sh`
**Files (edit):** `scripts/INSTALL_APP.sh`
**Produces (new):** `workflow_app_install_main [args...]`; private `_appinstall_install`,
`_appinstall_remove`, `_appinstall_verify`, `_appinstall_reboot_wait`, `_appinstall_usage`.
Domain interfaces: `system_app_install <apk> <directory_name>`, `system_app_remove <package>`,
`system_app_verify <package>` return status with diagnostics on stderr; `device_request_reboot`
requests a restart without adding a wait; `device_reboot_wait` retains the installer's existing wait
and uptime check. Both return status only. The domain operations own staging, transfers,
root commands, native-library placement and read-back. Workflow owns policy, prompts and sequencing.

- [ ] 12.1 Move the install, remove, post-reboot verification, reboot-and-wait and usage functions behind
      the `_appinstall_` prefix, with one public entrypoint.
- [ ] 12.2 Keep the uptime-regression check in the reboot wait: a device answering again only proves a
      reboot if uptime went backwards.
- [ ] 12.3 Route gates through `policy/safety.sh` and facts through `domain/apk.sh`. Move the existing
      device mutation and verification bodies into the domain interfaces above, preserving command order
      and accepted inputs. These domain modules use the adapter. The workflow neither issues raw ADB
      calls nor calls the transport directly. Keep launcher installation policy separate from generic
      system-app installation; do not merge those distinct workflows during extraction.
- [ ] 12.4 Reduce `scripts/INSTALL_APP.sh` to a wrapper forwarding argv and propagating the return code.
      Preserve every flag, the positional APK argument, the help output and the interactive prompts,
      including those reading from the terminal because the device call consumes stdin.
- [ ] 12.5 Extend the contract suite with argv-forwarding cases: each flag reaches the workflow, an
      unknown flag still produces usage and a nonzero status, and the wrapper's status equals the
      workflow's.

**Required checks:** Task 2 app-install characterization passes unchanged. Flag-forwarding cases pass.
`rg -n '(^|[^-_./[:alnum:]])adb[[:space:]]' "$WT/scripts/INSTALL_APP.sh"` returns nothing.

---

## Task 13: Unlock workflow, step driver and CLI wrapper

**Files (new):** `scripts/lib/workflow/unlock.sh`, `tests/contracts/unlock-workflow.sh`
**Files (edit):** `scripts/UNLOCK.sh`, `scripts/lib/unlock.sh`, `scripts/lib/domain/package.sh`,
`scripts/lib/domain/device_info.sh`, `scripts/lib/domain/settings.sh`
**Produces (new):** `workflow_unlock_main [args...]` as the public entrypoint, with private
`_unlock_step_line`, `_unlock_show_status`, `_unlock_all_applied`, `_unlock_run_step`,
`_unlock_apply_all`, `_unlock_revert_all`, `_unlock_menu`, `_unlock_single_step`, `_unlock_interactive`

- [ ] 13.1 Move the status reporting, step driver, apply-all and revert-all sequences and the interactive
      menu into the module. The revert order stays reversed, so the launcher is restored before its files
      are removed.
- [ ] 13.2 Preserve the local step protocol and state vocabulary in `scripts/lib/unlock.sh`, not its
      raw transport calls. Route those through domain operations and load `ui/legacy.sh` for its human
      output. Add domain APIs `package_try_adb_install <apk>`, `package_stage_apk <apk> <remote>`,
      `device_is_connected`, `setting_put <namespace> <key> <value>` and
      `setting_delete <namespace> <key>` for the corresponding existing calls. Preserve the current
      root/plain-shell choice, command ordering and read-back checks. Inventory each remaining inline
      root command in the steps and give it a named domain operation before declaring this task done.
- [ ] 13.3 Keep the read-back verification after each apply: the step's own return code is not trusted,
      the re-read state decides.
- [ ] 13.4 Replace the model check's direct calls with `domain/device_info.sh`; use the domain's
      `device_request_reboot` for the restart action. Preserve the no-device repair path and keep
      terminating compatibility helpers out of the new workflow's lower-level error handling.
- [ ] 13.5 Reduce `scripts/UNLOCK.sh` to a wrapper forwarding argv and propagating the return code,
      preserving every mode flag, the confirmation flag, the help output, and the ordering rule that repair
      runs before the device requirement gate because that failure leaves no working device channel.
- [ ] 13.6 Keep the read-only mode exempt from the backup requirement, as it is today.
- [ ] 13.7 Extend the contract suite: each mode flag reaches the workflow; an unknown flag produces usage
      and a nonzero status; the wrapper's status equals the workflow's; repair still runs with no device.

**Required checks:** unlock suite passes every scenario. Flag-forwarding cases pass.
`rg -n '(^|[^-_./[:alnum:]])adb[[:space:]]' "$WT/scripts/UNLOCK.sh"` returns nothing.

---

## Task 14: Tools workflow and device actions

**Files (new):** `scripts/lib/domain/tool_actions.sh`, `scripts/lib/workflow/tools.sh`
**Files (edit):** `scripts/TOOLS.sh`
**Produces (new):** `tool_action_run <verb> [args...]`, `tool_launcher_home_component`,
`tool_launcher_activities`, `workflow_tools_main`, `workflow_tools_reset_launcher`,
`workflow_tools_menu_entry <index>`, `workflow_tools_menu_count`

- [ ] 14.1 Move the device half of the menu command runner into `tool_actions.sh`, keeping the rule that
      the activity starter reports failure from its output text because its exit status is unreliable.
- [ ] 14.2 Move the stock-launcher home reset and the launcher-activity query into the domain module,
      keeping on-device component resolution rather than a hardcoded component name.
- [ ] 14.3 Move the menu tables, entry lookup, entry count and the launcher-reset guard into
      `workflow/tools.sh`. Keep the guard that explains why the reset cannot proceed while the stock
      launcher is disabled and points at the command that does work.
- [ ] 14.4 Leave the menu rendering and the array-indirection helper in the front end as presentation.
      Keep the `eval`-based indirection: namerefs need bash 4.3 and that is the recorded reason it was
      removed.
- [ ] 14.5 Reduce the front end to presentation plus workflow calls, with no direct device call.
- [ ] 14.6 Extend the front-end suite: entries render with continuous numbering across sections; the
      disabled-launcher guard still explains and redirects; the reset works when the launcher is enabled.

**Required checks:** front-end suite passes.
`rg -n '(^|[^-_./[:alnum:]])adb[[:space:]]' "$WT/scripts/TOOLS.sh" "$WT/scripts/PROJECTOR.sh"` returns
nothing.

---

## Task 15: Generated recovery packaging with an inlined executor

**Files (new):** `scripts/lib/packaging/restore/*.frag`, `scripts/lib/packaging/generate.sh`
**Files (edit):** `scripts/lib/workflow/backup.sh` **Produces (new):**
`packaging_write_restore_tools <dir>`

- [ ] 15.1 Move the two heredocs into fragment files and assemble the output by concatenation at
      generation time.
- [ ] 15.2 Inline the helpers the artifact actually needs, including the transport executor, so the
      generated tools reference no checkout at runtime. This satisfies the approved requirement that they
      remain usable inside a copied backup directory.
- [ ] 15.3 Preserve the menu, option numbering, prompts and interface. State compatibility as **interface
      and format compatibility, not byte compatibility**, since adding a marker comment changes the bytes.
- [ ] 15.4 Assert copy-independence by behavior, not by grepping for an absent `source` line: copy the
      generated directory to a fresh path, drive every menu option there under the intercepting fake, and
      compare recorded traces against the Task 2.4 baseline.
- [ ] 15.5 Change no restore algorithm here, add no menu choice, disable nothing. Hazards go to Task 19.
- [ ] 15.6 Assert archive compatibility: the directory still holds the image, the manifest with its four
      fields and both generated tools, and still satisfies verification.

**Required checks:** generated interface matches the Task 2.4 baseline. Traces from the relocated copy
match the in-place traces. No raw write occurs. Archive compatibility holds.

---

## Task 16: New-contract stream discipline regression

This tests a new contract, not a historical bug; the legacy writers are not being moved.

**Files (new):** `tests/contracts/stream-discipline.sh`

- [ ] 16.1 Write the regression around a fixture function calling the **real** `log_*` helper while its
      caller captures stdout in a command substitution. The required expectation is that captured stdout is
      the payload only, with the diagnostic asserted separately on stderr. Avoid the shape where the human
      line is emitted outside the substitution, which was never capturable and proves nothing.
- [ ] 16.2 For binary output, assert **byte-for-byte equality** against the fixture. Do not scan bytes for
      bracketed text prefixes: a legitimate payload may contain them.
- [ ] 16.3 Classify each new function as value, binary or none and assert accordingly: a value function's
      captured stdout is exactly its value; a binary function's output is byte-identical; a none function's
      captured stdout is empty.
- [ ] 16.4 Assert the compatibility direction too: the legacy writers that keep stdout still write to
      stdout, so the public CLI surface is unchanged.

**Required checks:** suite passes for every classified function, with the binary case compared by bytes
and the legacy stdout routing still asserted.

---

## Task 17: Architecture checker

Narrow by design, not an AST project. It enforces the rules rather than leaving differences to review.

**Files (new):** `tests/arch/check-layers.sh` **Files (edit):** every new module, for header lines

- [ ] 17.1 Add `# layer: <name>` and `# requires: <name> ...` headers to each new module.
- [ ] 17.2 Enforce: exactly one recognised layer per module; every `requires` entry permitted by the
      Architecture table; no `source` directive naming a forbidden layer; no `log_*`, `print_*` or
      `source .*ui/` inside `transport/`; no presentation reference inside `domain/`; no `workflow/` load
      inside `common.sh`.
- [ ] 17.3 Enforce the raw-adb rule: outside `scripts/lib/transport/` and the packaging fragments, no
      production file may invoke `adb` by bare word, absolute path, or through a variable. Front ends,
      wrappers, workflows and domain modules all reach the device through the adapter.
- [ ] 17.4 Treat `root/` as out of scope explicitly: no layer header, not read, not classified.
- [ ] 17.5 Include the banned-construct scan, labelled in the output as a **heuristic only**. It is not
      proof of Bash 3.2 compatibility and must never substitute for Task 18. Proposed example, not run:
      ```sh
      rg -n 'declare -A|local -n|\breadarray\b|\bmapfile\b' "$WT/scripts/"
      ```
- [ ] 17.6 Prove each rule fails on a real violation, in a **copy** of the tree and never in the worktree
      tree: a `source` of a forbidden layer; a `print_*` call inside `transport/`; a bare `adb` call inside
      a workflow; a `workflow/` load inside `common.sh`. Each must exit nonzero naming the file and rule.
- [ ] 17.7 Add the checker to the runner ahead of the suites.

**Required checks:** checker passes on the real tree. All four deliberate violations fail with a message
naming file and rule. `root/` appears in no result. One shell file, no new dependency.

---

## Task 18: Bash 3.2 compatibility gate

- [ ] 18.1 Obtain an actual Bash 3.2 shell: a pinned interpreter path, a container image, or a fixture
      runner. Record exactly what was used.
- [ ] 18.2 Execute the contract suites and the entry scripts under that shell, not merely a parse check.
      A parse check under a newer shell does not establish compatibility.
- [ ] 18.3 If no 3.2 shell is available, record the gate as **explicitly unverified** and say so in the
      release notes. The Task 17.5 heuristic does not close this gate and must not be reported as if it did.

**Required checks:** either a recorded 3.2 execution with results, or an explicit unverified statement
naming what was unavailable. No substitution of the heuristic for execution.

---

## Task 19: Recovery safety review, HOLD deliverable

The approved scope is the recovery artifact **contract**, not a redesign of the raw restore algorithms.
This task produces a reviewed hold, not fixes.

**Files (new):** `docs/superpowers/specs/2026-09-12-recovery-safety-hold.md`

- [ ] 19.1 Reproduce each source-shaped hazard independently with fake command traces, running no raw
      write: the whole-device write reached through a fallback after a failed push; the option whose
      success path only pushes and reboots; the partition restore lacking the verification its sibling
      performs; and the saved-state value passed onward without validation.
- [ ] 19.2 Record for each: the trace, the source shape, the operator-visible consequence, and the class
      of change that would address it.
- [ ] 19.3 State two correctness constraints for any future fix, so a later task cannot get them wrong. A
      partition image must not be checked against the whole-device size, which is the wrong denominator. A
      malformed saved launcher state must not fall back silently to the stock launcher.
- [ ] 19.4 State the hold explicitly: these are not addressed in this refactor, they require separately
      approved safety changes, and no hardware use or release claim may proceed on this plan's completion.
      Extraction preserving the current interface is **not** an endorsement that the restore paths are safe.
- [ ] 19.5 Add no new menu choice and disable nothing in this task.

**Required checks:** every hazard has a recorded trace produced without a raw write. Both correctness
constraints written down. The hold statement present and unambiguous.

---

## Task 20: Review and release gates

- [ ] 20.1 Re-run the Task 1.9 bypass audit and compare against the recorded baseline file. The Task 17
      raw-adb rule is the enforcement; this comparison is the record.
- [ ] 20.2 Scan call sites before removing any compatibility wrapper. A wrapper is removed only when every
      consumer handles the returned status; until then it stays.
      ```sh
      rg -n '\b(require_device|require_backup|print_status|print_success|print_step|adb_root_exec|adb_root_stream|adb_root_stream_watched|adb_remote_size|verify_backup_dir|find_backup_dir|find_incomplete_backup_dir|human_size|local_md5|local_size)\b' "$WT/scripts/" "$WT/tests/"
      ```
- [ ] 20.3 Confirm the CLI surface is unchanged: every flag and mode of the three wrappers, their help
      output, argv forwarding and return-code propagation; both front ends' menu options and quit keys; and
      the interactive prompts. Enumerate the cases and their expected exit statuses rather than asserting a
      pass count, since new tests accumulate.
- [ ] 20.4 Confirm `/bin/bash -n` parses all five entrypoints and every new module, and extend the
      existing parse loop to the new library files. Pin the interpreter for the entry scripts the front-end
      suite currently invokes through the `PATH` shell. This is a parse gate only; Task 18 owns
      compatibility.
- [ ] 20.5 Run ShellCheck over `scripts/` and the new modules as a static gate, no device involved. Record
      the invocation and findings. Treat a finding as a question to answer, and add no suppression to quiet
      a shared layer.
- [ ] 20.6 Update the **tracked** documentation only: the `docs/system/` root pages and the test-harness
      pages, recording both the target architecture and what is currently true, following the repository's
      documentation conventions. The untracked sibling drafts are not present in this worktree, so their
      corrections are not applied here; integrating them is a separate owner-approved docs campaign, and a
      lint of the present pages does not close it.
- [ ] 20.7 Independent review gate. Hand the diff to a reviewer from a different model family with the
      spec, this plan, the Task 19 hold, and the recorded regression outputs. Unresolved findings block the
      next gate.
- [ ] 20.8 Commit authorization gate. Propose the commit sequence, one per task, Conventional Commits,
      subject at most 72 characters. Make no commit until the operator authorizes it.
- [ ] 20.9 Hardware approval gate. Everything above runs against the stand-in only. Before any device
      action, present what would run, the blast radius, the verified backup it depends on, the single
      restore command, and the open items from the Task 19 hold. A human watches the screen for anything a
      reboot decides. The operator decides; this plan does not.

**Required checks:** audit compared against its recorded baseline. No wrapper removed without a clean
call-site scan. CLI cases enumerated with expected statuses and all passing. All suites and contract
suites pass through the runner. Checker passes and every deliberate violation fails. Task 18 gate either
recorded or explicitly unverified. Tracked documentation updated and linting clean, with the
sibling-draft campaign named as outstanding. Independent review closed. Commits and any device action
await explicit operator authorization.
