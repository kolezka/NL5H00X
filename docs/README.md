# Documentation

This directory contains detailed technical documentation for the Android Projector Toolkit.

## Contents

| Document | Description |
|----------|-------------|
| [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md) | Device specifications, ADB commands, partition layout, compatibility notes |
| [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) | Analysis of security restrictions and bypass methods |
| [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) | The `wtprovision` brick: why disabling one component stops the device booting, how to diagnose it over UART, and the one-command fix |
| [BOOT_BRANDING.md](BOOT_BRANDING.md) | The three startup visual stages, the `logo` partition format, the ~7 fps rendering ceiling, and why `adb push` silently fails on `/atv` |
| [DEV_OPTIONS_CRASH.md](DEV_OPTIONS_CRASH.md) | Why Developer options die on open (no USB device controller), and the published AOSP platform key that lets system APKs be re-signed |

## Quick Reference

For getting started, see the main [README](../README.md).

For emergency recovery procedures, see [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md#emergency-recovery).
