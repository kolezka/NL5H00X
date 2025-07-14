#!/bin/bash

# Projector Hidden Apps Access Script
# Provides easy access to hidden system features and settings on locked Android projectors
# Based on discovered working commands for Newlink/Hisilicon devices

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${CYAN}=================================="
    echo -e "   PROJECTOR ACCESS TOOLKIT"
    echo -e "==================================${NC}"
    echo ""
}

print_menu() {
    echo -e "${BLUE}Available Hidden Features:${NC}"
    echo ""
    echo -e "${GREEN}SYSTEM SETTINGS:${NC}"
    echo "  1.  Android TV Settings (WORKING ✅)"
    echo "  2.  Standard Android Settings"
    echo "  3.  WiFi Settings"
    echo "  4.  Bluetooth Settings" 
    echo "  5.  Display Settings"
    echo "  6.  Security Settings"
    echo "  7.  Developer Options"
    echo "  8.  Application Management"
    echo ""
    echo -e "${GREEN}PROJECTOR-SPECIFIC:${NC}"
    echo "  9.  Hisilicon TV Settings"
    echo "  10. Newlink Settings"  
    echo "  11. TV Menu"
    echo "  12. TV Quick Settings"
    echo "  13. External Input Settings"
    echo ""
    echo -e "${GREEN}MEDIA & FILES:${NC}"
    echo "  14. File Manager (via monkey)"
    echo "  15. Gallery"
    echo "  16. Music Player"
    echo "  17. Video Player"
    echo "  18. Office Apps"
    echo ""
    echo -e "${GREEN}CONNECTIVITY:${NC}"
    echo "  19. Cast/Screen Mirroring"
    echo "  20. Miracast"
    echo "  21. Bluetooth Settings (Advanced)"
    echo ""
    echo -e "${GREEN}LAUNCHER OPTIONS:${NC}"
    echo "  22. Choose Default Launcher"
    echo "  23. RGTPLauncher (if available)"
    echo "  24. WTProvision (if available)"
    echo "  25. Reset to Original Launcher"
    echo ""
    echo -e "${GREEN}SYSTEM TOOLS:${NC}"
    echo "  26. Package Installer"
    echo "  27. Input Method Settings"
    echo "  28. Default Apps Management"
    echo "  29. System Information"
    echo "  30. Hardware Information"
    echo ""
    echo -e "${YELLOW}ADVANCED:${NC}"
    echo "  31. All Launcher Activities"
    echo "  32. All System Activities"
    echo "  33. Service Status Check"
    echo "  34. Install APK via File Manager"
    echo ""
    echo -e "${RED}  0.  Exit${NC}"
    echo ""
}

# Function to check if device is connected
check_device() {
    if ! command -v adb &> /dev/null; then
        echo -e "${RED}Error: ADB is not installed or not in PATH${NC}"
        exit 1
    fi

    if ! adb devices | grep -q "device$"; then
        echo -e "${RED}Error: No Android device connected${NC}"
        echo "Make sure your projector is connected and USB debugging is enabled"
        exit 1
    fi
}

# Function to execute commands with error handling
execute_command() {
    local description="$1"
    local command="$2"
    
    echo -e "${BLUE}[INFO]${NC} $description"
    echo -e "${YELLOW}Command:${NC} $command"
    
    eval "$command"
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $description completed"
    else
        echo -e "${RED}[ERROR]${NC} $description failed (exit code: $result)"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

# Main menu function
show_menu() {
    while true; do
        clear
        print_header
        print_menu
        
        read -p "Select option (0-34): " choice
        echo ""
        
        case $choice in
            1)
                execute_command "Opening Android TV Settings" \
                "adb shell am start -n com.android.tv.settings/.MainSettings"
                ;;
            2)
                execute_command "Opening Standard Android Settings" \
                "adb shell am start -a android.settings.SETTINGS"
                ;;
            3)
                execute_command "Opening WiFi Settings" \
                "adb shell am start -a android.settings.WIFI_SETTINGS"
                ;;
            4)
                execute_command "Opening Bluetooth Settings" \
                "adb shell am start -a android.settings.BLUETOOTH_SETTINGS"
                ;;
            5)
                execute_command "Opening Display Settings" \
                "adb shell am start -a android.settings.DISPLAY_SETTINGS"
                ;;
            6)
                execute_command "Opening Security Settings" \
                "adb shell am start -a android.settings.SECURITY_SETTINGS"
                ;;
            7)
                execute_command "Opening Developer Options" \
                "adb shell am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS"
                ;;
            8)
                execute_command "Opening Application Management" \
                "adb shell am start -a android.settings.MANAGE_APPLICATIONS_SETTINGS"
                ;;
            9)
                execute_command "Opening Hisilicon TV Settings" \
                "adb shell am start -n com.hisilicon.tvsetting/.MainActivity"
                ;;
            10)
                execute_command "Opening Newlink Settings" \
                "adb shell am start -n com.newlink.hisetting/.MainActivity"
                ;;
            11)
                execute_command "Opening TV Menu" \
                "adb shell am start -n com.hisilicon.tv.menu/.MainActivity"
                ;;
            12)
                execute_command "Opening TV Quick Settings" \
                "adb shell am start -n com.android.tv.quicksettings/.MainActivity"
                ;;
            13)
                execute_command "Opening External Input Settings" \
                "adb shell am start -n com.hisilicon.tvinput.external/.MainActivity"
                ;;
            14)
                execute_command "Opening File Manager" \
                "adb shell monkey -p com.newlink.filemanager -c android.intent.category.LAUNCHER 1"
                ;;
            15)
                execute_command "Opening Gallery" \
                "adb shell am start -n com.hisilicon.higallery/.MainActivity"
                ;;
            16)
                execute_command "Opening Music Player" \
                "adb shell am start -n com.hisilicon.android.music/.MainActivity"
                ;;
            17)
                execute_command "Opening Video Player" \
                "adb shell am start -n com.hisilicon.android.videoplayer/.MainActivity"
                ;;
            18)
                execute_command "Opening Office Apps" \
                "adb shell am start -n com.mobisystems.editor.office_registered/.MainActivity"
                ;;
            19)
                execute_command "Opening Cast/Screen Mirroring" \
                "adb shell am start -n com.newlink.cast/.MainActivity"
                ;;
            20)
                execute_command "Opening Miracast" \
                "adb shell am start -n com.hisilicon.miracast/.MainActivity"
                ;;
            21)
                execute_command "Opening Bluetooth Settings (Advanced)" \
                "adb shell am start -n com.example.bluetoothsetting/.MainActivity"
                ;;
            22)
                execute_command "Choose Default Launcher" \
                "adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME"
                ;;
            23)
                execute_command "Opening RGTPLauncher" \
                "adb shell am start -n com.rgt.launcher/.MainActivity"
                ;;
            24)
                execute_command "Opening WTProvision" \
                "adb shell am start -n com.newlink.wtprovision/.MainActivity"
                ;;
            25)
                execute_command "Resetting to Original Launcher" \
                "adb shell cmd package set-home-activity com.newlink.hisilauncher"
                ;;
            26)
                execute_command "Opening Package Installer" \
                "adb shell am start -n com.android.packageinstaller/.PackageInstallerActivity"
                ;;
            27)
                execute_command "Opening Input Method Settings" \
                "adb shell am start -a android.settings.INPUT_METHOD_SETTINGS"
                ;;
            28)
                execute_command "Opening Default Apps Management" \
                "adb shell am start -a android.settings.MANAGE_DEFAULT_APPS_SETTINGS"
                ;;
            29)
                echo -e "${BLUE}[INFO]${NC} Gathering System Information..."
                echo ""
                echo -e "${CYAN}Device Properties:${NC}"
                adb shell getprop | grep -E "ro.product.model|ro.build.version|ro.product.manufacturer"
                echo ""
                echo -e "${CYAN}Storage Information:${NC}"
                adb shell df /sdcard/
                echo ""
                echo -e "${CYAN}Memory Information:${NC}"
                adb shell cat /proc/meminfo | head -5
                echo ""
                read -p "Press Enter to continue..."
                ;;
            30)
                echo -e "${BLUE}[INFO]${NC} Hardware Information..."
                echo ""
                echo -e "${CYAN}CPU Information:${NC}"
                adb shell cat /proc/cpuinfo | grep -E "processor|model name|Hardware" | head -10
                echo ""
                echo -e "${CYAN}Display Information:${NC}"
                adb shell dumpsys display | grep -E "mDisplayId|mCurrentDisplayRect" | head -5
                echo ""
                echo -e "${CYAN}Thermal Information:${NC}"
                adb shell cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -5 || echo "Thermal info not available"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            31)
                echo -e "${BLUE}[INFO]${NC} Finding All Launcher Activities..."
                echo ""
                adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
                echo ""
                read -p "Press Enter to continue..."
                ;;
            32)
                echo -e "${BLUE}[INFO]${NC} Finding All System Activities..."
                echo ""
                adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
                echo ""
                read -p "Press Enter to continue..."
                ;;
            33)
                echo -e "${BLUE}[INFO]${NC} Checking Critical Service Status..."
                echo ""
                echo -e "${CYAN}Power Management Services:${NC}"
                adb shell dumpsys activity services | grep -E "zhiying.powerservice|hisilicon.tv.service|newlink.service" || echo "Services not found in current output"
                echo ""
                echo -e "${CYAN}Running System Services:${NC}"
                adb shell ps | grep -E "system_server|servicemanager" | head -5
                echo ""
                read -p "Press Enter to continue..."
                ;;
            34)
                echo -e "${BLUE}[INFO]${NC} Opening File Manager for APK Installation..."
                echo ""
                echo -e "${YELLOW}Instructions:${NC}"
                echo "1. File manager will open on your projector"
                echo "2. Navigate to your APK file"
                echo "3. Tap on the APK to install"
                echo "4. Follow on-screen prompts"
                echo ""
                read -p "Press Enter to open file manager..."
                adb shell monkey -p com.newlink.filemanager -c android.intent.category.LAUNCHER 1
                echo ""
                echo -e "${GREEN}File manager opened on projector screen${NC}"
                read -p "Press Enter when done..."
                ;;
            0)
                echo -e "${GREEN}Exiting Projector Access Toolkit${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 0-34.${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Main execution
main() {
    # Check if device is connected
    check_device
    
    # Show main menu
    show_menu
}

# Run the script
main