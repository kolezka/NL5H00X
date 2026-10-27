# Documentation

Start with the [toolkit README](../README.md) for setup and commands. Use the
current guides below for an unlock, install, backup or recovery. The dated audit
is a snapshot, not the starting point for current procedures.

## Current guides

| Document | Topic |
|---|---|
| [Boot deadlock](BOOT_DEADLOCK.md) | The vendor HOME dispatcher and UART recovery from a disabled component. |
| [Install gate](INSTALL_LOCKED.md) | Why installs failed, the tested gate change and how to revert it. |
| [Recovery](RECOVERY.md) | Booting the stock recovery with a BCB and its limits. |
| [Will not boot](UNBOOTABLE.md) | Initial checks when Android does not start. |
| [Developer options](DEV_OPTIONS_CRASH.md) | The settings crash and the tested system APK patch. |
| [Boot branding](BOOT_BRANDING.md) | Startup images, animation and write checks. |
| [Security and recovery limits](SECURITY_ANALYSIS.md) | Observed root access, backup safety and the restore HOLD. |
| [Technical notes](TECHNICAL_NOTES.md) | Device and partition details. |
| [Vendor telemetry](VENDOR_TELEMETRY.md) | Vendor reporting, update limits and network blocking. |
| [Recovery tools](../tools/recovery/README.md) | Host BCB and serial-console tools. |
| [App root](../root/README.md) | Optional root daemon and client setup. |

## Dated observations

| Document | Topic |
|---|---|
| [Device audit, 2026-10-24](DEVICE_AUDIT_2026-10-24.md) | Snapshot of one modified unit. Later work supersedes parts of it. |
| [Vendor apps audit, 2026-10-26](VENDOR_APPS_2026-10-26.md) | Read-only inventory of vendor packages. |
| [Docs index](README.md) | This index. |

## Source-pinned system documentation

The [system documentation overview](system/README.md) is pinned to `f04ee86`.
The unlock and app-install blocks describe the model before October 2026.
Use the current guides above for present behavior.

| Document | Topic |
|---|---|
| [Conventions](system/CONVENTIONS.md) | Evidence and notation. |
| [Data flow](system/DATA-FLOW.md) | Toolkit flow at the source pin. |
| [Glossary](system/GLOSSARY.md) | Terms used by the blocks. |
| [Ownership](system/OWNERSHIP.md) | Source and block ownership. |
| [Review](system/REVIEW.md) | Documentation review record. |
| [System overview](system/README.md) | Block map and source pin. |

### Device access

| Document | Topic |
|---|---|
| [Overview](system/device-access/README.md) | Shared ADB behavior. |
| [Contracts](system/device-access/CONTRACTS.md) | Public command contracts. |
| [Decisions](system/device-access/DECISIONS.md) | Recorded design choices. |
| [Gaps](system/device-access/GAPS.md) | Known limits at the source pin. |
| [Invariants](system/device-access/INVARIANTS.md) | Safety rules. |
| [Operations](system/device-access/OPERATIONS.md) | Operator steps. |

### Backup

| Document | Topic |
|---|---|
| [Overview](system/backup/README.md) | Backup flow. |
| [Contracts](system/backup/CONTRACTS.md) | Backup and restore contracts. |
| [Decisions](system/backup/DECISIONS.md) | Recorded design choices. |
| [Gaps](system/backup/GAPS.md) | Known limits and later restore-test correction. |
| [Invariants](system/backup/INVARIANTS.md) | Safety rules. |
| [Operations](system/backup/OPERATIONS.md) | Operator steps. |

### Unlock

| Document | Topic |
|---|---|
| [Overview](system/unlock/README.md) | Source-pinned unlock model. |
| [Contracts](system/unlock/CONTRACTS.md) | Source-pinned step contracts. |
| [Decisions](system/unlock/DECISIONS.md) | Older decisions and current cache correction. |
| [Gaps](system/unlock/GAPS.md) | Known limits at the source pin. |
| [Invariants](system/unlock/INVARIANTS.md) | Source-pinned safety rules. |
| [Operations](system/unlock/OPERATIONS.md) | Source-pinned operator steps. |

### App install

| Document | Topic |
|---|---|
| [Overview](system/app-install/README.md) | Install route and current gate correction. |
| [Contracts](system/app-install/CONTRACTS.md) | Source-pinned install contracts. |
| [Decisions](system/app-install/DECISIONS.md) | Recorded design choices. |
| [Gaps](system/app-install/GAPS.md) | Known limits at the source pin. |
| [Invariants](system/app-install/INVARIANTS.md) | Source-pinned safety rules. |
| [Operations](system/app-install/OPERATIONS.md) | Source-pinned operator steps. |

### Front ends

| Document | Topic |
|---|---|
| [Overview](system/front-ends/README.md) | Guided menu and tools. |
| [Contracts](system/front-ends/CONTRACTS.md) | Source-pinned interface contracts. |
| [Decisions](system/front-ends/DECISIONS.md) | Recorded design choices. |
| [Gaps](system/front-ends/GAPS.md) | Known limits at the source pin. |
| [Invariants](system/front-ends/INVARIANTS.md) | Source-pinned safety rules. |
| [Operations](system/front-ends/OPERATIONS.md) | Source-pinned operator steps. |

### Test harness

| Document | Topic |
|---|---|
| [Overview](system/test-harness/README.md) | Fake ADB and runner. |
| [Contracts](system/test-harness/CONTRACTS.md) | Test contracts. |
| [Gaps](system/test-harness/GAPS.md) | Test limits. |
| [Invariants](system/test-harness/INVARIANTS.md) | Fixture safety rules. |
| [Operations](system/test-harness/OPERATIONS.md) | Running tests. |

## Design records

| Document | Topic |
|---|---|
| [System flow design, 2026-09-12](superpowers/specs/2026-09-12-system-flow-refactor-design.md) | Earlier design. |
| [System flow plan, 2026-09-12](superpowers/plans/2026-09-12-system-flow-refactor.md) | Earlier plan. |
| [Unlock and toolkit design, 2026-10-27](superpowers/specs/2026-10-27-make-unlock-work-and-simplify-design.md) | Current design and corrections. |
| [Unlock and toolkit plan, 2026-10-27](superpowers/plans/2026-10-27-make-unlock-work-and-simplify.md) | Implementation steps. |
