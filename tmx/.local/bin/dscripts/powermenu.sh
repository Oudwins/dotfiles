#!/bin/sh

# Power menu script using tofi

CHOSEN=$(printf "Lock\nSuspend\nReboot\nPoweroff\nLog Out" | rofi -dmenu -i -p "select an option")

case "$CHOSEN" in
	"Lock") lockscreen ;;
	"Suspend") systemctl suspend-then-hibernate ;;
	"Reboot") reboot ;;
	"Poweroff") poweroff ;;
	"Log Out") hyprctl dispatch exit ;;
	*) exit 1 ;;
esac
