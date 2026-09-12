---
block: _root
doc: GLOSSARY
verified_against: f04ee86
verified_on: 2026-09-12
---

# Glossary

Terms a reader needs before opening a block page. Definitions were read from source at `f04ee86` and describe naming, not behaviour observed on hardware. [verified]

## Terms

| Term | Meaning | Evidence |
|---|---|---|
| toolkit | The shell scripts under `scripts/` that an operator runs against the projector from a host machine. | `[verified]` |
| entry script | A script under `scripts/` that loads a library and owns a command line, as opposed to a library under `scripts/lib/`. | `[verified]` |
| library guard | The include-once flag each library sets on first load, `scripts/lib/common.sh::_COMMON_SH_LOADED` and `scripts/lib/unlock.sh::_UNLOCK_SH_LOADED`. | `[verified]` |
| root escalation mode | `SU_MODE`, selected by `scripts/lib/common.sh::check_root_access()` and consumed by the root helpers. | `[verified]` |
| unlock step | One named change with four functions of the same shape, describe, state, apply and revert, enumerated in `scripts/lib/unlock.sh::UNLOCK_STEPS`. | `[verified]` |
| step state | The value a step's state function returns: applied, not-applied, or blocked with a reason. | `[verified]` |
| stock launcher | The launcher shipped on the device, named in `scripts/lib/unlock.sh::STOCK_LAUNCHER`. | `[verified]` |
| target launcher | The replacement launcher the unlock installs and prefers, named in `scripts/lib/unlock.sh::LAUNCHER_PKG` and overridable by environment. | `[verified]` |
| home dispatcher | The firmware component that owns the home intent, named in `scripts/lib/unlock.sh::HOME_DISPATCHER_COMP`. | `[verified]` |
| fallback home | The platform home component named in `scripts/lib/unlock.sh::FALLBACK_HOME_COMP`, kept as a recovery target. | `[verified]` |
| repair | The recovery path that checks and restores home handling, `scripts/lib/unlock.sh::repair_run()`. | `[verified]` |
| backup manifest | The metadata file a backup run writes, produced by `scripts/lib/common.sh::write_backup_manifest()` and read back by `scripts/lib/common.sh::read_manifest_field()`. | `[verified]` |
| verified backup | A backup directory that passes `scripts/lib/common.sh::verify_backup_dir()`, which is what `scripts/lib/common.sh::require_backup()` demands before destructive work. | `[verified]` |
| protected package | A package the installer refuses to remove, listed in `scripts/INSTALL_APP.sh::PROTECTED_PKGS`. | `[verified]` |
| fake adb | The stand-in `adb` used by the tests instead of a device, driven by state and knobs such as `tests/fake-adb/adb::FAKE_ADB_STATE`. | `[verified]` |
| sandbox | A throwaway state directory one test case runs against, built by `tests/run-tests.sh::new_sandbox()`. | `[verified]` |
| device profile | The seeded starting state of the emulated device, selected by `tests/device-emu/seed.sh::PROFILE`. | `[verified]` |
