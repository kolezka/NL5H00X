# Documentation

This directory contains detailed technical documentation for the Android Projector Toolkit.

## Contents

| Document | Description |
|----------|-------------|
| [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md) | Device specifications, ADB commands, partition layout, compatibility notes |
| [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) | Analysis of security restrictions and bypass methods |
| [BOOT_DEADLOCK.md](BOOT_DEADLOCK.md) | The `wtprovision` brick: why disabling one component stops the device booting, how to diagnose it over UART, and the one-command fix |
| [UNBOOTABLE.md](UNBOOTABLE.md) | Step by step for a projector that stopped booting after a flash or Magisk attempt: UART wiring, proving the adapter, capturing and reading a boot log |
| [BOOT_BRANDING.md](BOOT_BRANDING.md) | The three startup visual stages, the `logo` partition format, the ~7 fps rendering ceiling, and why `adb push` silently fails on `/atv` |
| [VENDOR_TELEMETRY.md](VENDOR_TELEMETRY.md) | Manufacturer reporting from `com.newlink.service` (MAC, geo-IP city, usage) over plain HTTP, the dead OTA channel, why Android cannot be updated, and the router-level block |
| [DEV_OPTIONS_CRASH.md](DEV_OPTIONS_CRASH.md) | Why Developer options die on open (no USB device controller), and the published AOSP platform key that lets system APKs be re-signed |
| [../root/README.md](../root/README.md) | Root for apps: why `NO_NEW_PRIVS` kills setuid `su`, the socket daemon that works instead, and the init service plus hybrid `su` that make it survive a reboot |

## Quick Reference

For getting started, see the main [README](../README.md).

For emergency recovery procedures, see [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md#emergency-recovery).
