#!/bin/bash
# Build an emulated NL5H00X device state directory.
#
# Every value here was read off the real projector or out of its firmware image
# on 2026-07-28 -- see DECISIONS ADR-009 and the probe results. The point of
# seeding from measured reality rather than invention is that an unlock which
# works here has a fair chance of working there; one tested against a guessed
# device proves nothing.
#
# Usage: seed.sh <state-dir> [--locked|--partially-unlocked]

set -euo pipefail

STATE="${1:?usage: seed.sh <state-dir> [profile]}"
PROFILE="${2:---locked}"

rm -rf "$STATE"
mkdir -p "$STATE"/{sdcard,system/app,system/priv-app,data}

# ---------------------------------------------------------------------------
# Properties (verbatim from system/build.prop in the pulled image)
# ---------------------------------------------------------------------------
cat > "$STATE/props" <<'EOF'
ro.product.model=NL5H00X_TP
ro.product.name=NL5H00X_TP
ro.product.device=NL5H00X
ro.product.manufacturer=Hisilicon
ro.build.version.release=9
ro.build.version.sdk=28
ro.build.type=userdebug
ro.product.cpu.abi=armeabi-v7a
ro.secure=1
ro.debuggable=1
EOF

# ---------------------------------------------------------------------------
# /system/app -- the real inventory, including the leftovers from earlier
# unlock attempts. comteslacoilswlaunch IS Nova Launcher and is already
# present, yet the device still boots the stock launcher: dropping an APK into
# /system/app is demonstrably not sufficient, and the tool must not assume it.
# ---------------------------------------------------------------------------
for d in APKPurev32051ap APKPurev32051apkpure Bluetooth BluetoothMidiService \
         comteslacoilswlaunch ExtShared HBCastNew HiExternalTvInput \
         HiFactoryMenu HiGalleryL HiMusic HiPinyinIME HiRMService HiTvPlayer \
         HiTvService HiTvSetting IjkPlayer KeyChain Magiskv290 Miracast \
         NLOfficeSuit NovaLauncher PacProcessor PowerService RGTPLauncher \
         SimAppDialog WallpaperBackup webview WTProvision ZYBluetooth \
         ZYCustomer ZYCustomUI ZYFileManager ZYSetting; do
    mkdir -p "$STATE/system/app/$d"
done

# APKs that actually exist (sizes as measured; contents are stand-ins)
mkapk() { mkdir -p "$(dirname "$1")"; head -c "$2" /dev/zero > "$1"; }
mkapk "$STATE/system/app/RGTPLauncher/RGTPLauncher.apk"                 4825338
mkapk "$STATE/system/app/comteslacoilswlaunch/comteslacoilswlaunch.apk" 8687535
mkapk "$STATE/system/app/Magiskv290/Magiskv290.apk"                    11801932
mkapk "$STATE/system/app/APKPurev32051ap/APKPurev32051ap.apk"          20878645
mkapk "$STATE/system/app/APKPurev32051apkpure/APKPurev32051apkpure.apk" 20878645
# NovaLauncher/ exists but is empty -- a failed earlier attempt, kept on purpose
head -c 3052 /dev/zero > "$STATE/system/build.prop"

# ---------------------------------------------------------------------------
# Package database: path=package, mirroring `pm list packages -f`
# ---------------------------------------------------------------------------
cat > "$STATE/packages" <<'EOF'
/system/app/RGTPLauncher/RGTPLauncher.apk=com.newlink.hisilauncher
/system/app/comteslacoilswlaunch/comteslacoilswlaunch.apk=com.teslacoilsw.launcher
/system/app/Magiskv290/Magiskv290.apk=com.topjohnwu.magisk
/system/app/APKPurev32051apkpure/APKPurev32051apkpure.apk=com.apkpure.aegon
/system/app/ZYFileManager/ZYFileManager.apk=com.newlink.filemanager
/system/app/HiTvSetting/HiTvSetting.apk=com.hisilicon.tv.setting
/system/app/PowerService/PowerService.apk=com.zhiying.powerservice
/system/priv-app/TvSettings/TvSettings.apk=com.android.tv.settings
EOF
: > "$STATE/packages_disabled"

# ---------------------------------------------------------------------------
# Mutable device state
# ---------------------------------------------------------------------------
echo "com.newlink.hisilauncher/.MainActivity" > "$STATE/home_activity"
echo "ro"        > "$STATE/mount_system"     # /system starts read-only
echo "Enforcing" > "$STATE/selinux"
echo "0"         > "$STATE/reboots"

# settings: <namespace> <key> <value>
cat > "$STATE/settings" <<'EOF'
global development_settings_enabled 0
global adb_enabled 1
global stay_on_while_plugged_in 0
global package_verifier_enable 1
global verifier_verify_adb_installs 1
secure install_non_market_apps 0
system screen_off_timeout 120000
EOF

# A stand-in block device so the backup path still works against this state.
head -c 41943040 /dev/urandom > "$STATE/blockdev"

if [[ "$PROFILE" == "--partially-unlocked" ]]; then
    # What the real projector looks like today: Nova present, dev options on,
    # and the launcher still stubbornly the stock one.
    sed -i '' 's/^global development_settings_enabled 0/global development_settings_enabled 1/' "$STATE/settings" 2>/dev/null || \
        sed -i 's/^global development_settings_enabled 0/global development_settings_enabled 1/' "$STATE/settings"
fi

echo "seeded $PROFILE device at $STATE"
