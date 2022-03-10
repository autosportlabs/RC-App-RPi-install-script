# RC App automated installation scripts for RPi

The rcdash_setup.sh attempts to perform the following:
* Setup udev rules and service for automounting usb memory sticks to /media/usb#
* Enables a wifi autoreconnect cronjob
* Adds shutdown/reboot button support on GPIO pin 21
* Installs the necessary apt packages for the RC App
* Downloads the RC App tar file and installs it in /opt
* Modifies the pi users .bashrc to autostart the RC App upon login

In the case of Dietpi, there is rcdash_setup.sh can be combined with DietPi's auto
installation features.  The dietpi_image_prep.sh script will mount a DietPi image's
/boot partition and inject the rcdash_setup.sh and associated dietpi.txt file to enable
a mostly hands free installation.
