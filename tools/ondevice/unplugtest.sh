#!/bin/sh
# Reproduces phase 2's exit detection on the real device, with the gadget bound
# and the drive in front of a computer, and logs what the app would see every
# second. The LUN points at a scratch file, not at the SD card.
OUT=/mnt/SDCARD/.userdata/tg5040/unplugtest.txt
U="$(ls /sys/class/udc | head -1)"
G=/sys/kernel/config/usb_gadget/g1
mkdir -p /mnt/SDCARD/.userdata/tg5040
: > "$OUT"

# the two functions, copied verbatim from usb_mode.sh
usb_charging() {
	[ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" = "1" ] && return 0
	case "$(cat /sys/class/power_supply/axp2202-battery/status 2>/dev/null)" in
	Charging | Full) return 0 ;;
	esac
	return 1
}
usb_link_up() {
	usb_charging && return 0
	if [ -n "$UDC" ]; then
		case "$(cat "/sys/class/udc/$UDC/state" 2>/dev/null)" in
		"not attached" | "") return 1 ;;
		?*) return 0 ;;
		esac
	fi
	return 1
}

echo "0 SETUP udc=$U" >> "$OUT"
dd if=/dev/zero of=/tmp/fake_disk bs=1024 count=2048 2>/dev/null
echo "" > $G/UDC; sleep 1
rm -f $G/configs/c.1/ffs.adb $G/configs/c.1/f1
setusbconfig mass_storage >/dev/null 2>&1
echo "/tmp/fake_disk" > $G/functions/mass_storage.usb0/lun.0/file
echo "$U" > $G/UDC
echo "1 EXPORTED lun=[$(cat $G/functions/mass_storage.usb0/lun.0/file)]" >> "$OUT"

# wait_for_host, as the app does it
i=0
while [ "$i" -lt 20 ]; do
	case "$(cat /sys/class/udc/$U/state 2>/dev/null)" in
	configured|addressed|default|powered|attached) break ;;
	esac
	sleep 1; i=$((i + 1))
done
echo "2 HOST_SEEN after=${i}s" >> "$OUT"

# wait_for_unplug, as the app does it
i=0
while [ "$i" -lt 150 ]; do
	if ! usb_link_up; then
		echo "3 UNPLUG_DETECTED after=${i}s" >> "$OUT"
		break
	fi
	echo "$i up state=$(cat /sys/class/udc/$U/state 2>/dev/null) online=$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null) batt=$(cat /sys/class/power_supply/axp2202-battery/status 2>/dev/null)" >> "$OUT"
	sleep 1
	i=$((i + 1))
done
[ "$i" -ge 150 ] && echo "3 TIMEOUT never saw the unplug" >> "$OUT"

echo "4 CLEANUP" >> "$OUT"
echo "" > $G/UDC; sleep 1
rmdir $G/functions/mass_storage.usb0/lun.0 2>/dev/null
rmdir $G/functions/mass_storage.usb0 2>/dev/null
setusbconfig adb >/dev/null 2>&1
rm -f /tmp/fake_disk
echo "5 DONE" >> "$OUT"
