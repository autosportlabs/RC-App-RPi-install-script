#!/bin/bash -e

replace() {
	sed -i -e "/$1/ {
	r $2
	d }" rcdash_setup.sh
}

cp rcdash_setup_template rcdash_setup.sh

# Wifi reconnect
replace "__WIFI_RECONNECT_CRON__" "wifi_reconnect.cron"
replace "__WIFI_RECONNECT__" "wifi_reconnect.sh"

# Shutdown button
replace "__SHUTDOWN_BUTTON_SERVICE__" "shutdown_button.service"
replace "__SHUTDOWN_BUTTON_SCRIPT__" "shutdown_button.py"

# Automount replacements
replace "__AUTOMOUNT__" "automount"
replace "__USBSTICK_RULES__" "usbstick.rules"
replace "__USBSTICK_SERVICE__" "usbstick-handler@.service" 

# Bashrc replacements
replace "__BASH_RC__" "bashrc"
