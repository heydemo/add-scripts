#!/bin/bash

# Bluetooth Device Connection Script
# Uses device configuration from promptables/btdevice.yml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_CONFIG="${SCRIPT_DIR}/../../promptables/btdevice.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if bluetoothctl is available
check_bluetooth() {
    if ! command -v bluetoothctl &> /dev/null; then
        print_error "bluetoothctl not found. Please install bluez package."
        exit 1
    fi

    # Check if bluetooth service is running
    if ! systemctl is-active --quiet bluetooth; then
        print_warning "Bluetooth service is not running. Attempting to start..."
        sudo systemctl start bluetooth
        sleep 2
    fi
}

# Parse YAML file to get devices
parse_devices() {
    if [[ ! -f "$DEVICE_CONFIG" ]]; then
        print_error "Device configuration file not found: $DEVICE_CONFIG"
        exit 1
    fi

    # Read devices from YAML file
    devices=()
    labels=()

    while IFS= read -r line; do
        if [[ $line =~ ^-[[:space:]]+label:[[:space:]]+(.+)$ ]]; then
            label="${BASH_REMATCH[1]}"
            labels+=("$label")
        elif [[ $line =~ ^[[:space:]]+value:[[:space:]]+([0-9A-Fa-f:]+)$ ]]; then
            mac="${BASH_REMATCH[1]}"
            devices+=("$mac")
        fi
    done < "$DEVICE_CONFIG"

    if [[ ${#devices[@]} -eq 0 ]]; then
        print_error "No devices found in configuration file"
        exit 1
    fi
}

# Display device selection menu
show_device_menu() {
    echo
    print_info "Available Bluetooth Devices:"
    echo "================================"
    for i in "${!devices[@]}"; do
        printf "%2d) %-20s (%s)\n" $((i+1)) "${labels[i]}" "${devices[i]}"
    done
    echo
}

# Connect to device
connect_device() {
    local mac="$1"
    local label="$2"

    print_status "Attempting to connect to $label ($mac)..."

    # Turn on bluetooth adapter
    bluetoothctl power on &>/dev/null
    sleep 1

    # Connect to device
    if bluetoothctl connect "$mac" &>/dev/null; then
        print_status "Successfully connected to $label"
        return 0
    else
        print_error "Failed to connect to $label"
        return 1
    fi
}

# Remove and re-pair device
remove_and_pair() {
    local mac="$1"
    local label="$2"

    print_warning "Removing and re-pairing $label ($mac)..."

    # Remove device
    print_info "Removing existing pairing..."
    bluetoothctl remove "$mac" &>/dev/null
    sleep 1

    # Make device discoverable and scan
    print_info "Starting scan for devices..."
    bluetoothctl discoverable on &>/dev/null
    bluetoothctl scan on &>/dev/null
    sleep 3

    # Attempt to pair
    print_info "Attempting to pair with $label..."
    if bluetoothctl pair "$mac" &>/dev/null; then
        sleep 2
        print_info "Pairing successful, now connecting..."
        if bluetoothctl connect "$mac" &>/dev/null; then
            print_status "Successfully paired and connected to $label"
            bluetoothctl scan off &>/dev/null
            return 0
        else
            print_error "Pairing successful but connection failed"
        fi
    else
        print_error "Failed to pair with $label"
        print_info "Make sure the device is in pairing mode"
    fi

    bluetoothctl scan off &>/dev/null
    return 1
}

# Show device status
show_device_status() {
    local mac="$1"
    local label="$2"

    print_info "Status for $label ($mac):"

    # Check if device is known
    if bluetoothctl devices | grep -q "$mac"; then
        echo "  - Device is paired"

        # Check if connected
        if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
            echo "  - Device is connected"
        else
            echo "  - Device is not connected"
        fi

        # Show battery level if available
        battery=$(bluetoothctl info "$mac" | grep "Battery Percentage" | cut -d'(' -f2 | cut -d')' -f1)
        if [[ -n "$battery" ]]; then
            echo "  - Battery: $battery"
        fi
    else
        echo "  - Device is not paired"
    fi
}

# Main menu loop
main_menu() {
    while true; do
        show_device_menu
        echo "Options:"
        echo "  q) Quit"
        echo "  s) Show all device status"
        echo
        read -p "Select device number or option: " choice

        case "$choice" in
            q|Q)
                print_info "Goodbye!"
                exit 0
                ;;
            s|S)
                echo
                for i in "${!devices[@]}"; do
                    show_device_status "${devices[i]}" "${labels[i]}"
                    echo
                done
                continue
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#devices[@]} ]]; then
                    index=$((choice-1))
                    selected_mac="${devices[index]}"
                    selected_label="${labels[index]}"

                    echo
                    print_info "Selected: $selected_label ($selected_mac)"

                    if connect_device "$selected_mac" "$selected_label"; then
                        echo
                        read -p "Press Enter to continue..."
                    else
                        echo
                        echo "Connection failed. What would you like to do?"
                        echo "1) Try connecting again"
                        echo "2) Remove and re-pair device"
                        echo "3) Show device status"
                        echo "4) Return to main menu"
                        echo
                        read -p "Choose option (1-4): " retry_choice

                        case "$retry_choice" in
                            1)
                                connect_device "$selected_mac" "$selected_label"
                                ;;
                            2)
                                remove_and_pair "$selected_mac" "$selected_label"
                                ;;
                            3)
                                show_device_status "$selected_mac" "$selected_label"
                                ;;
                            4|*)
                                continue
                                ;;
                        esac
                        echo
                        read -p "Press Enter to continue..."
                    fi
                else
                    print_error "Invalid selection. Please try again."
                    sleep 1
                fi
                ;;
        esac
    done
}

# Main execution
main() {
    echo "==================================="
    echo "   Bluetooth Device Manager"
    echo "==================================="

    check_bluetooth
    parse_devices

    print_status "Found ${#devices[@]} configured devices"

    main_menu
}

# Run main function
main "$@"
