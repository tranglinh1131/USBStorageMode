#!/bin/sh
# Logs the USB signals once a second so we can see which node actually reports
# an unplug on this device. Written to the card so it survives a reboot.
OUT=/mnt/SDCARD/.userdata/tg5040/usbwatch.txt
U="$(ls /sys/class/udc | head -1)"
: > "$OUT"
i=0
while [ "$i" -lt 180 ]; do
	echo "$i $(cat /sys/class/udc/$U/state 2>/dev/null) online=$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null) batt=$(cat /sys/class/power_supply/axp2202-battery/status 2>/dev/null)" >> "$OUT"
	i=$((i + 1))
	sleep 1
done
echo "DONE" >> "$OUT"
