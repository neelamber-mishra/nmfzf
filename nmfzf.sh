#!/bin/bash

if ! command -v nmcli &> /dev/null; then
    echo "Error: nmcli not found. Install NetworkManager first."
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf not found. Install it first (https://github.com/junegunn/fzf)."
    exit 1
fi

wifi_status() {
    nmcli radio wifi | grep -q "enabled"
}

toggle_wifi() {
    if wifi_status; then
        echo "WiFi is currently enabled. Disabling..."
        nmcli radio wifi off
    else
        echo "WiFi is currently disabled. Enabling..."
        nmcli radio wifi on
        sleep 2
    fi
}

connect_wifi() {
    if ! wifi_status; then
        echo "WiFi is currently disabled."
        read -p "Would you like to enable WiFi? [Y/n] " yn
        case $yn in
            [Nn]* ) exit 0;;
            * ) toggle_wifi;;
        esac
    fi

    echo "Scanning for WiFi networks..."
    nmcli device wifi rescan
    
    local selected_network
    selected_network=$(nmcli -t -f SSID,SECURITY,SIGNAL,BARS device wifi list | \
        awk -F':' '{print $1 "\t" $2 "\t" $3 "\t" $4}' | \
        fzf --height 40% --reverse --header="SSID SECURITY SIGNAL BARS" \
            --prompt="Select WiFi network > " \
            --bind 'ctrl-t:toggle-preview' \
            --preview 'echo "Press CTRL-T to toggle WiFi\nCurrent status: $(nmcli radio wifi)"')

    if [ -z "$selected_network" ]; then
        echo "No network selected. Exiting."
        exit 0
    fi

    local ssid
    ssid=$(echo "$selected_network" | awk -F'\t' '{print $1}')

    echo "Selected exact SSID: '$ssid'"

    if nmcli -t -f active,ssid dev wifi | grep -q "yes:.*$ssid"; then
        echo "Already connected to '$ssid'"
        exit 0
    fi

    if nmcli -t -f name connection show | grep -q "^${ssid// /\\ }$"; then
        echo "Connecting to existing profile: '$ssid'"
        nmcli connection up "$(nmcli -t -f name,uuid connection show | grep "$ssid" | head -1 | cut -d: -f1)"
        exit $?
    fi

    if [[ "$selected_network" == *"WPA"* ]] || [[ "$selected_network" == *"WEP"* ]]; then
        echo "Selected network: '$ssid' (requires password)"
        local password
        
        if command -v zenity &> /dev/null; then
            password=$(zenity --entry --title="WiFi Password" --text="Enter password for '$ssid':" --hide-text 2>/dev/null)
        else
            read -sp "Enter password for '$ssid': " password
            echo
        fi
        
        if [ -z "$password" ]; then
            echo "No password provided. Exiting."
            exit 1
        fi
        
        echo "Connecting to '$ssid'..."
        nmcli device wifi connect "$ssid" password "$password"
    else
        echo "Selected network: '$ssid' (open network)"
        nmcli device wifi connect "$ssid"
    fi
}

main() {
    # echo "WiFi Manager"
    # echo "1. Connect to WiFi network"
    # echo "2. Toggle WiFi On/Off"
    # echo "3. Exit"
    # read -p "Select an option [1-3]: " choice

    case 1 in
        1) connect_wifi;;
        2) toggle_wifi;;
        3) exit 0;;
        *) echo "Invalid option";;
    esac
}

# Start the script
main