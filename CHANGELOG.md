# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- `nl5h00x` is the entry point for the toolkit commands.
- Unlock writes the wtprovision launcher cache and restarts wtprovision. On stock units, it reboots and resumes before making those changes.
- `nl5h00x install-gate off|on|status` controls the install gate separately from unlock.
- `nl5h00x tools` has a ROOT entry that blocks the vendor's update and reporting servers in `/system/etc/hosts`. It keeps a hash-checked backup, and running it again restores the original file byte for byte.

### Changed
- The README is being rewritten to explain the new entry point and flows.

### Removed
- The unused `cleanup_leftovers` unlock step.
- The unwired transport, UI, and progress modules.
