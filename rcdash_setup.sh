#!/bin/bash

RPI_MODEL=$(tr -d '\0' </proc/device-tree/model)
SETTINGS_FILE="/home/$SUDO_USER/.config/racecapture/install_settings.cfg"
FIRST_RUN=1
FULL_INSTALL=1
REBOOT_NEEDED=0

function eval_setting() {
	if [ "$1" == "$2" ]; then
		echo "ON"
	else
		echo "OFF"
	fi
}

function yesno() {
	whiptail --title "$1" --yesno "$2" 20 70 4 3>&1 1>&2 2>&3
	exitstatus=$?
	# Invert truthines
	if [ $exitstatus = 0 ]; then
		echo 1
	else
		echo 0
	fi
}

function password_prompt() {
	PASSWORD=$(whiptail --title "$1" --passwordbox "$2" 20 70 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus != 0 ]; then
		echo "Password cahcelled, default to no password"
		PASSWORD=""
	fi
	echo $PASSWORD
}

function load_settings() {
	if [ -f "$SETTINGS_FILE" ]; then
		FIRST_RUN=0
		source $SETTINGS_FILE
	else
MODE=FB
WIFI_RECONNECT=1
USB_AUTOMOUNT=1
SHUTDOWN_BUTTON=0
WATCHDOG=1
CURSOR=1
TOUCH_KEYBOARD=1
RESOLUTION=800x480
	fi
}

function dump_settings() {
	cat > "$SETTINGS_FILE" <<-EOF
MODE=$MODE
WATCHDOG=$ENABLE_WATCHDOG
WIFI_RECONNECT=$ENABLE_WIFI_RECONNECT
SHUTDOWN_BUTTON=$ENABLE_SHUTDOWN_BUTTON
CURSOR=$ENABLE_CURSOR
TOUCH_KEYBOARD=$ENABLE_TOUCH_KEYBOARD
USB_AUTOMOUNT=$ENABLE_USB_AUTOMOUNT
RESOLUTION=$RESOLUTION
	EOF
	chown $USER:$USER "$SETTINGS_FILE"
}

function setup_rpi_image_config() {
	# Disable console blanking
	if ! grep -q "logo\.nologo" /boot/cmdline.txt; then
       		sed -i '1 s/$/ logo.nologo/' /boot/cmdline.txt
	fi
	if ! grep -q "consoleblank=0" /boot/cmdline.txt; then
       		sed -i '1 s/$/ consoleblank=0/' /boot/cmdline.txt
	fi

	# Disable splash screen
	if ! grep -q "^disable_splash" /boot/config.txt; then
       		echo "disable_splash=1" >> /boot/config.txt
	fi

	# Set appropriate gpu memory
	if ! grep -q "^gpu_mem=256" /boot/config.txt; then
		if grep -q "^gpu_mem=" /boot/config.txt; then
			sed -i '$s/^gpu_mem=.*/gpu_mem=256/' /boot/cmdline.txt
		else
			echo "gpu_mem=256" >> /boot/config.txt
		fi
		REBOOT_NEEDED=1
	fi
}

function setup_packages() {
	# Install the necessary dependencies for the RC App
	echo "Installing necessary packages"
	BASE_PACKAGES="mesa-utils libgles2 libegl1-mesa libegl-mesa0 mtdev-tools pmount pv python3-gpiozero jq"
	X11_PACKAGES="xserver-xorg xserver-xorg-legacy xinit gldriver-test"
	VNC_PACKAGES="x11vnc"

	PACKAGES_TO_INSTALL="${BASE_PACKAGES}"
	if [[ $MODE == "X11" ]]; then
		PACKAGES_TO_INSTALL+=" ${X11_PACKAGES}"
		if [[ $ENABLE_VNC == "1" ]]; then
			PACKAGES_TO_INSTALL+=" ${VNC_PACKAGES}"
		fi
	fi
	apt-get -y install $PACKAGES_TO_INSTALL
}

function add_group() {
	groupname="$1"
	if ! groups "$USER" | grep -qw "$groupname"; then
		adduser $USER $groupname
	fi
}

function setup_user() {
	# Groups needed for the dietpi user to access opengl, input (touch/mouse) and usb serial ports
	echo "Adding user to necessary groups"
	add_group "render"
	add_group "video"
	add_group "input"
	add_group "dialout"
	
	# No .config directory can cause RC App to fail
	mkdir -p /home/$USER/.config/racecapture
	chown $USER:$USER /home/$USER/.config/racecapture
}

function install_rc_app() {
	# Download and install the RC App
	RC_APP_URL=`curl -s 'https://podium.live/api/v1/applications/1/latest.json?expand=1&platform=rpi' | jq -r .release.url`
	RC_APP_FILENAME=`basename "$RC_APP_URL" | sed 's/\?.*//'`
	echo "Installing RC App '$RC_APP_FILENAME'"
	cd /opt
	if [ -f "$RC_APP_FILENAME" ]; then
	       	echo "RC App '$RC_APP_FILENAME' already downloaded"
	else
	       	echo "Downloading..."
	       	wget -q --progress=bar --show-progress "$RC_APP_URL" -O "$RC_APP_FILENAME"
	fi

	if [ -d "racecapture" ]; then
	       	if (whiptail --title "Overwrite Installation" --yesno "Overwrite the existing racecapture installation." 20 70 4); then
		       	echo "Removing old installation"
		       	rm -rf racecapture
		       	echo "Extracting '$RC_APP_FILENAME'"
		       	pv "$RC_APP_FILENAME" | tar xj
	       	else
		       	echo "Skipping"
	       	fi
	else
	       	echo "Extracting '$RC_APP_FILENAME'"
	       	pv "$RC_APP_FILENAME" | tar xj
	fi
}


if [ -z "$SUDO_USER" ]
then
	echo "Must be run via sudo"
	exit
fi

USER=$SUDO_USER

load_settings

if [ "$FIRST_RUN" = "0" ]; then
	if (whiptail --title "Update Only?" --yesno "Would you like to perform a full reinstall or only upgrade the RC App?" --yes-button "Upgrade Only" --no-button "Reinstall/Reconfig" 20 70 4); then
		FULL_INSTALL=0
	fi
fi

if [ "$FULL_INSTALL" = "1" ]; then
	setup_rpi_image_config


	IS_AUTOLOGIN=$(/usr/bin/raspi-config nonint get_autologin)
	if [[ $IS_AUTOLOGIN == "1" ]]; then
		ENABLE_AUTOLOGIN=$(yesno "Auto Login" "Enable automatic login on startup?")
		if [[ $ENABLE_AUTOLOGIN == "1" ]]; then
			/usr/bin/raspi-config nonint do_boot_behaviour B2
		fi
	fi

	if [[ $RPI_MODEL == "Raspberry Pi 3"* ]]; then
		if grep -q '^dtoverlay=vc4-kms-v3d\s*$' /boot/config.txt; then
			if (whiptail --title "RPi3 Official Display" --yesno "Enable RPi Official touchscreen support?\n\nNote: only select yes if using an LCD display connected directly to your RPI!" 20 70 4); then
				sed -i 's/^dtoverlay=vc4-kms-v3d\s*$/dtoverlay=vc4-fkms-v3d/' /boot/config.txt
				REBOOT_NEEDED=1
			fi
		fi
	fi

	if [[ $RPI_MODEL == "Raspberry Pi 5"* ]]; then
		MODE="X11"
		whiptail --title "Mode" --msgbox "Due to driver bugs only X11 is supported on the RPi5 at this time" 20 70
		exitstatus=$?
	else
		MODE=$(whiptail --title "Mode" --notags --radiolist \
			"How do you want to run Race Capture?" 20 70 4 \
			FB "Direct Framebuffer" $(eval_setting $MODE "FB") \
			X11 "Using X11 (allows VNC)" $(eval_setting $MODE "X11" ) 3>&1 1>&2 2>&3)
		exitstatus=$?
	fi
	if [ $exitstatus != 0 ]; then
        	echo "Cancelling installation"
		exit 1
	fi

	if [[ $MODE == "X11" ]]; then
		CUSTOM_SELECTION="ON"
		res_values=("800x480" "1280x720" "1920x1080")
		for value in "${res_values[@]}"; do
			if [[ $RESOLUTION == $value ]]; then
				CUSTOM_SELECTION="OFF"
				break
			fi
		done

		RESOLUTION=$(whiptail --nocancel --title "Resolution" --radiolist \
			"Select or enter you screen resolution." 20 70 4 \
		 	"800x480" "Official Rpi Display" $(eval_setting $RESOLUTION "800x480") \
			"1280x720" "720p Display" $(eval_setting $RESOLUTION "1280x720") \
		        "1920x1080" "1080p Display" $(eval_setting $RESOLUTION "1920x1080") \
		        "Custom" "Custom display resolution" $CUSTOM_SELECTION 3>&1 1>&2 2>&3)	
		exitstatus=$?
		while ! [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]];
		do
			RESOLUTION=$(whiptail --title "Custom Resolution" --inputbox "Enter Custom input in the form <width>x<height>." 20 70 3>&1 1>&2 2>&3)
			exitstatus=$?
			if [ $exitstatus != 0 ]; then
			       	echo "Cancelling installation"
			       	exit 1
		       	fi
		done

			
		ENABLE_VNC=$(yesno "VNC" "Enable VNC?")
	fi

	if [[ $ENABLE_VNC == "1" ]]; then
		VNC_PASSWORD=$(password_prompt "VNC Password" "Please enter vnc password, leave blank for no password.")
	fi

	APP_SELECTIONS=$(whiptail --title "App Features" --notags --separate-output --checklist \
		"Choose app features to enable" 20 78 4 \
		WATCHDOG "Enable auto-restart watchdog" $(eval_setting $WATCHDOG 1) \
		CURSOR "Enable mouse pointer" $(eval_setting $CURSOR 1) \
		KEYBOARD "Enable touchscreen keyboard" $(eval_setting $TOUCH_KEYBOARD 1) 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus == 0 ]; then
		for i in $APP_SELECTIONS
		do
			case $i in
				WATCHDOG)
					ENABLE_WATCHDOG=1
					;;
				CURSOR)
					ENABLE_CURSOR=1
					;;
				KEYBOARD)
					ENABLE_TOUCH_KEYBOARD=1
					;;
				*)
					echo "Unknown selection!!!"
					exit 1
					;;
			esac
		done
	else
        	echo "Cancelling installation"
		exit 1
	fi


	SELECTIONS=$(whiptail --title "Extra Features" --notags --separate-output --checklist \
		"Choose features to enable" 20 78 4 \
		WIFI_AUTO_RECONNECT "Automatically reconnect wifi" $(eval_setting $WIFI_RECONNECT 1) \
		USB_AUTO_MOUNT "Mount usb drives under /media/usb#" $(eval_setting $USB_AUTOMOUNT 1) \
		GPIO_SHUTDOWN "Enable GPIO Pin21 shutdown/reboot" $(eval_setting $SHUTDOWN_BUTTON 1) 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus == 0 ]; then
		for i in $SELECTIONS
		do
			case $i in
				WIFI_AUTO_RECONNECT)
					ENABLE_WIFI_RECONNECT=1
					;;
				USB_AUTO_MOUNT)
					ENABLE_USB_AUTOMOUNT=1
					;;
				GPIO_SHUTDOWN)
					ENABLE_SHUTDOWN_BUTTON=1
					;;
				*)
					echo "Uknown option"
					exit 1
					;;
			esac
		done
	else
		echo "Cancelling installation"
		exit 1
	fi

	setup_packages
	setup_user

	# Now that x11vnc is installed we can setup the vnc password, if necessary
	if [[ $ENABLE_VNC == "1" ]]; then
		VNC_CMD="x11vnc -display :0 -many -noxdamage"
		if [[ $VNC_PASSWORD != "" ]]; then
			mkdir -p /home/$USER/.vnc
			x11vnc -storepasswd "${VNC_PASSWORD}" /home/$USER/.vnc/passwd
			chown -R $USER:$USER /home/$USER/.vnc
			VNC_CMD+=" -usepw &"
	       	else
		       	VNC_CMD+=" -nopw &"
	       	fi
	else
	       	VNC_CMD=""
	fi


	if [[ $ENABLE_WIFI_RECONNECT == "1" ]]; then
	       	echo "Enabling Wifi auto-reconnect"
	       	# Setup wifi reconnect if not using dietpi which has it's own service
		cat > /etc/cron.d/wifi_reconnect.cron <<-'EOF'
# Run the wifi_reconnect script every minute
* *   * * *   root    /usr/local/bin/wifi_reconnect.sh
		EOF

		cat > /usr/local/bin/wifi_reconnect.sh <<-'EOF'
#!/bin/bash 
 
SSID=$(/sbin/iwgetid --raw) 

if [ -z "$SSID" ] 
then 
    echo "`date -Is` WiFi interface is down, trying to reconnect" >> /home/pi/wifi-log.txt
    sudo ifconfig wlan0 down
    sleep 30
    sudo ifconfig wlan0 up 
fi 

echo "WiFi check finished"
		EOF

		chmod +x /usr/local/bin/wifi_reconnect.sh
       	fi

	if [[ $ENABLE_SHUTDOWN_BUTTON == "1" ]]; then
       		echo "Enabling GPIO shutdown button"
       		# Setup shutdown button support for GPIO21
	       	cat > /usr/local/bin/shutdown_button.py <<-'EOF'
#!/usr/bin/python3
# -*- coding: utf-8 -*-
# example gpiozero code that could be used to have a reboot
#  and a shutdown function on one GPIO button
# scruss - 2017-10

use_button=21                       # lowest button on PiTFT+

from gpiozero import Button
from signal import pause
from subprocess import check_call

held_for=0.0

def rls():
    global held_for
    if (held_for > 1.0):
        check_call(['/sbin/reboot'])
    else:
        held_for = 0.0

def hld():
    # callback for when button is held
    #  is called every hold_time seconds
    global held_for
    # need to use max() as held_time resets to zero on last callback
    held_for = max(held_for, button.held_time + button.hold_time)
    if (held_for > 4.0):
        check_call(['/sbin/poweroff'])

button=Button(use_button, hold_time=1.0, hold_repeat=True)
button.when_held = hld
button.when_released = rls

pause() # wait forever
		EOF

		chmod +x /usr/local/bin/shutdown_button.py

		cat > /etc/systemd/system/shutdown_button.service <<-'EOF'
[Unit]
Description=GPIO shutdown button
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/shutdown_button.py

[Install]
WantedBy=multi-user.target
		EOF

		systemctl enable shutdown_button.service
	       	systemctl start shutdown_button.service
	fi


	if [[ $ENABLE_USB_AUTOMOUNT == "1" ]]; then
	       	echo "Enabling USB Automount"
	       	# Add automount rules
	       	cat > /usr/local/bin/automount <<-'EOF'
#!/bin/bash
 
PART=$1

mount_points=(usb1 usb2 usb3 usb4 usb5)
for i in "${mount_points[@]}"
do
	if ! mountpoint -q /media/$1
	then
		/usr/bin/pmount --umask 000 --noatime -w --sync /dev/${PART} /media/$i
		exit 0
	fi
done
		EOF
  
		chmod +x /usr/local/bin/automount

		cat > /etc/udev/rules.d/usbstick.rules <<-'EOF'
ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k"
		EOF

		cat > /lib/systemd/system/usbstick-handler@.service <<-'EOF'
[Unit]
Description=Mount USB sticks
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/automount %I
ExecStop=/usr/bin/pumount /dev/%I
		EOF
	fi

	install_rc_app

	RC_SCRIPT_ARGS="-- -c graphics:show_cursor:0"
	if [[ $MODE == "X11" ]]; then
		RC_SCRIPT_ARGS+=" --size=$RESOLUTION"
	else
		RC_SCRIPT_ARGS+=" -a"
	fi

	if [[ $ENABLE_WATCHDOG == "1" ]]; then
	       	RC_SCRIPT_ARGS="-w 1 ${RC_SCRIPT_ARGS}"
	fi
	
	# Enable cusor module if requested
	if [[ $ENABLE_CURSOR == "1" ]]; then
	       	RC_SCRIPT_ARGS+=" -m cursor"
	fi
	
	# Enable virtual keyboard if requeted
	if [[ $ENABLE_TOUCH_KEYBOARD == "1" ]]; then
	       	RC_SCRIPT_ARGS+=" -c kivy:keyboard_mode:systemandmulti"
	else
	       	RC_SCRIPT_ARGS+=" -c kivy:keyboard_mode:system"
	fi
	
	RC_LAUNCH_COMMAND="/opt/racecapture/run_racecapture_rpi.sh $RC_SCRIPT_ARGS"
	
	if [[ $MODE == "X11" ]]; then
	       	BASH_LAUNCH_CMD="xinit -- -nocursor -dpms -s 0"
	else
	       	BASH_LAUNCH_CMD="$RC_LAUNCH_COMMAND"
	fi
	
	cat > "/home/$USER/.bashrc" <<-EOF
if shopt -q login_shell; then
  if [ -z "\$SSH_CLIENT" ] || [ -z "\$SSH_TTY" ]; then
    echo "Starting RaceCapture!"
    $BASH_LAUNCH_CMD
  fi
fi
	EOF
	chown $USER:$USER /home/$USER/.bashrc
	
	if [[ $MODE == "X11" ]]; then
		cat > "/home/$USER/.xinitrc" <<-EOF
#!/bin/sh
$VNC_CMD
$RC_LAUNCH_COMMAND
		EOF
		chown $USER:$USER /home/$USER/.xinitrc
	fi

	dump_settings
else
	install_rc_app
fi

echo "Installation complete!!"
if [[ $REBOOT_NEEDED == "1" ]]; then
	echo "A reboot is required for full changes to take effect, please reboot now!"
else
	echo "Upon next login the RaceCapture app should auto start, please logout and login!"
fi
