# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- `TOOLS.sh` ROOT section - eight tools that use the device's root: root status, the app allow-list (grant and revoke), a one-off root command, a hash-verified copy of a root-only file, ADB over Wi-Fi, and freeze/unfreeze. Refuses to freeze the boot path, including `com.newlink.wtprovision`
- `root/README.md` "What root gets you" - worked examples of what shell root and app root can each do on this device, and what root does not fix
- `ROOT.sh` - Persistent root: installs the `sud` daemon, its init service and the su allow-list, with an opt-in hybrid `su` behind `--with-su`
- `root/sud.rc`, `root/su.c`, `root/suclient.{c,h}` - init service and the hybrid `su` that keeps the shell/root fast path
- `tests/root-tests.sh` - End-to-end root suite against the fake-adb emulator
- Initial release of Android Projector Toolkit
- `TOOLS.sh` - Hidden feature access script with 34 menu options
- `MAKE_BACKUP.sh` - Complete device backup system with chunked storage
- `UNLOCK.sh` - System unlock script (work in progress)
- Documentation for security analysis and technical notes
- Nova Launcher APK for custom launcher installation

### Fixed
- dd command compatibility (use `bs=1048576` instead of `bs=1M`)
- Root shell syntax compatibility for interactive sessions

### Security
- Backup verification required before any system modifications
- Emergency restore procedures documented

## [0.1.0] - 2024-01-01

### Added
- Initial project structure
- Basic ADB command documentation
- Device analysis for Newlink NL5H00X
