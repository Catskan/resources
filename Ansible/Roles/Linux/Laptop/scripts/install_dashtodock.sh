#/!bin/bash

#Install the Gnome Extension DashToDock
dashtodock=$(unzip -c Downloads/dash-to-dockmicxgx.gmail.com.v75.shell-extension.zip metadata.json | grep uuid | cut -d \" -f4)
mkdir .local/share/gnome-shell/extensions/
unzip -q Downloads/dash-to-dockmicxgx.gmail.com.v75.shell-extension.zip -d .local/share/gnome-shell/extensions/$dashtodock