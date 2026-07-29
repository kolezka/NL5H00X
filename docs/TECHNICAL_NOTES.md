# Technical Notes: Android Projector Modification

## Device Overview

**Target Device**: Newlink NL5H00X Android Projector

| Property | Value |
|----------|-------|
| Android Version | 9 (API 28) |
| Architecture | ARM (armeabi-v7a) |
| Total Storage | 7.65GB |
| Chipset | Hisilicon |
| Firmware | Locked |

## Security Restrictions

The projector implements multiple security layers preventing standard APK installation:

1. **Install Location Restrictions** - `INSTALL_FAILED_INVALID_INSTALL_LOCATION`
2. **SELinux Enforcement** - `avc: denied` errors
3. **Package Manager Restrictions** - Permission denials
4. **Custom Launcher Lock** - `com.newlink.hisilauncher` cannot be changed via standard methods
5. **Enterprise/Kiosk Design** - Commercial appliance architecture

## Device Compatibility Notes

### dd Command Syntax

The device does not support unit suffixes in `dd` commands:

```bash
# Does NOT work
dd if=/dev/block/mmcblk0 of=/sdcard/backup.img bs=1M

# Works correctly
dd if=/dev/block/mmcblk0 of=/sdcard/backup.img bs=1048576
```

### Root Shell Syntax

The `su -c` flag does not work on this device. Use interactive shell sessions:

```bash
# Does NOT work
adb shell su -c "whoami"

# Works correctly
adb shell << 'EOF'
su
whoami
exit
EOF
```

## Storage Architecture

### Partition Layout

| Partition | Mount Point | Size | Purpose |
|-----------|-------------|------|---------|
| mmcblk0p1 | - | 8MB | Boot |
| mmcblk0p20 | /system | 1.8GB | System |
| mmcblk0p25 | /data | 4.6GB | Userdata |

Total partitions: 25

### Storage Limitations

- Total device storage: 7,650,410,496 bytes (7.65 GB)
- Available free space on `/sdcard`: 3,923,068 KB (~3.7 GB, measured 2026-07-28)
- Full backup streams to the host in 256 MB blocks and stages nothing on the
  device; the older `/sdcard`-staged path remains only as a fallback

## System Packages

### Critical Services

These services must be preserved for hardware functionality:

| Package | Purpose |
|---------|---------|
| `com.zhiying.powerservice` | Power management |
| `com.hisilicon.tv.service` | Display control |
| `com.newlink.service` | Hardware interface |

### Default Launcher

| Package | Status |
|---------|--------|
| `com.newlink.hisilauncher` | Locked default launcher |
| `RGTPLauncher` | Shows in chooser but activity missing |
| `WTProvision` | Shows in chooser but activity missing |

## Working ADB Commands

### Access Hidden Settings

```bash
# Android TV Settings
adb shell am start -n com.android.tv.settings/.MainSettings

# Standard Android Settings
adb shell am start -a android.settings.SETTINGS

# Developer Options
adb shell am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS

# File Manager
adb shell monkey -p com.newlink.filemanager -c android.intent.category.LAUNCHER 1

# Launcher Selection Prompt
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
```

### System Modification (Requires Root)

```bash
# Mount system as writable
mount -o remount,rw /system

# Install APK as system app
cp nova-launcher.apk /system/app/NovaLauncher.apk
chmod 644 /system/app/NovaLauncher.apk
pm install -r -t /system/app/NovaLauncher.apk

# Remount read-only
mount -o remount,ro /system
```

## Emergency Recovery

### Reset Launcher

```bash
adb shell cmd package set-home-activity com.newlink.hisilauncher
```

### Full System Restore

Requires complete backup created by `MAKE_BACKUP.sh`:

```bash
dd if=full-system-backup.img of=/dev/block/mmcblk0 bs=1048576
```

## Root Requirement

Root access is required for system modifications because:

- Package manager completely blocks user-space installation
- APKs must be installed to `/system/app/` as system apps
- Only root can bypass all security layers
- SELinux policies prevent modification without elevated privileges
