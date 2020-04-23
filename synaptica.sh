#!/bin/bash
# xinput --list-props "SynPS/2 Synaptics TouchPad"
# to find the things that can be modified.
[ "$(dpkg-query -l xserver-xorg-input-synaptics)" ] || sudo apt install xserver-xorg-input-synaptics
# above line queries whether synaptics driver is installed and installs it if not.

xinput --set-prop "SynPS/2 Synaptics TouchPad" "libinput Accel Speed" -1.0
xinput --set-prop "SynPS/2 Synaptics TouchPad" "libinput Accel Speed Default" -1.0

xinput --set-prop "pointer:Logitech K400" "libinput Accel Speed" 1.0
