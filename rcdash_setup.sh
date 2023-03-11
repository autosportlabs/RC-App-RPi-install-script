#!/bin/bash -e

. /boot/rcdash_settings.txt

RC_APP_URL=`curl -s https://podium.live/software | grep -Po '(?<=<a href=")[^"]*racecapture_linux_raspberrypi[^"]*.bz2'`
RC_APP_FILENAME=`basename $RC_APP_URL`

if [ "$EUID" -ne 0 ] 
then 
	echo "Must be run as root"
       	exit
fi

if [ -d /boot/dietpi ]
then
       	USER=dietpi
	# Make dietpi not wait on network during boot sequence
	sed -i 's/Type=oneshot/Type=simple/' /etc/systemd/system/ifup@.service.d/dietpi.conf
else
	USER=pi
	sed -i '1 s/$/ logo.nologo consoleblank=0/' /boot/cmdline.txt
	echo "disable-spash=1" >> /boot/config.txt
	echo "gpu_mem=256" >> /boot/config.txt
fi

# Install the necessary dependencies for the RC App
apt-get -y install mesa-utils libgles2 libegl1-mesa libegl-mesa0 mtdev-tools pmount python3-gpiozero ratpoison xserver-xorg xserver-xorg-legacy xinit

if [ "$ENABLE_WIFI_RECONNECT" -eq "1" ]
then
  # Setup wifi reconnect if not using dietpi which has it's own service
  if [ "$USER" == "pi" ]
  then
    cat > /etc/cron.d/wifi_reconnect.cron <<'EOF'
# Run the wifi_reconnect script every minute
* *   * * *   root    /usr/local/bin/wifi_reconnect.sh
EOF

    cat > /usr/local/bin/wifi_reconnect.sh <<'EOF'
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
  else
    systemctl enable dietpi-wifi-monitor.service
    systemctl start dietpi-wifi-monitor.service
  fi
fi

if [ "$ENABLE_SHUTDOWN_BUTTON" -eq "1" ]
then
  # Setup shutdown button support for GPIO21
  cat > /usr/local/bin/shutdown_button.py <<'EOF'
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

  cat > /etc/systemd/system/shutdown_button.service <<'EOF'
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

# Groups needed for the dietpi user to access opengl, input (touch/mouse) and usb serial ports
adduser $USER render
adduser $USER video
adduser $USER input
adduser $USER dialout

if [ "$ENABLE_USB_AUTOMOUNT" -eq "1" ]
then
  # Add automount rules
  cat > /usr/local/bin/automount <<'EOF'
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

  cat > /etc/udev/rules.d/usbstick.rules <<'EOF'
ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k"
EOF

  cat > /lib/systemd/system/usbstick-handler@.service <<'EOF'
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

# Download and install the RC App
cd /opt
echo "Installing RC App '$RC_APP_FILENAME'"
wget -q "$RC_APP_URL"
tar xvjf "$RC_APP_FILENAME"
# Remove conflicting libstdc++
mv /opt/racecapture/libstdc++.so.6 /opt/racecapture/libstdc++.so.6.bak

cat > "/home/$USER/.bashrc" <<'EOF'
echo "Starting RaceCapture, Ctrl-c to abort!"
for i in $(seq 2 -1 0)
do
  echo -n $i
  sleep 1
  echo -ne '\b'
done
#/opt/racecapture/run_racecapture.sh
if [ -z "$SSH_CLIENT" ] || [ -z "$SSH_TTY" ]; then
	xinit -- -nocursor -dpms -s 0
fi
EOF
chown $USER:$USER /home/$USER/.bashrc

cat > "/home/$USER/.xinitrc" <<'EOF'
#!/bin/sh
ratpoison&
/opt/racecapture/race_capture -a
EOF
chown $USER:$USER /home/$USER/.xinitrc

su dietpi -c "ssh-keygen -q -t rsa -N '' <<< $'\\ny' >/dev/null 2>&1"
