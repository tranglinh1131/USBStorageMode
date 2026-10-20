#!/bin/sh
# Why does the app reboot immediately? Checks the USB controller state right
# after the LUN is exported, which is what the app's "wait for unplug" reads.
L=/mnt/SDCARD/.userdata/tg5040/diag.txt
mkdir -p /mnt/SDCARD/.userdata/tg5040
exec >"$L" 2>&1
export LD_LIBRARY_PATH=/mnt/SDCARD/.system/lib:/usr/trimui/lib
export PATH=/mnt/SDCARD/.system/bin:/usr/trimui/bin:/bin:/sbin:/usr/bin:/usr/sbin
G=/sys/kernel/config/usb_gadget/g1
U="$(ls /sys/class/udc | head -1)"

st() { echo "  state=[$(cat /sys/class/udc/$U/state 2>/dev/null)]"; }
chg() { echo "  charger online=[$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)] batt=[$(cat /sys/class/power_supply/axp2202-battery/status 2>/dev/null)]"; }

echo "=== A. state before anything ==="; st; chg

dd if=/dev/zero of=/tmp/fake_disk bs=1024 count=2048 2>/dev/null

echo "=== B. export the way the app does it (ADB still bound) ==="
export UDC="$U" GADGET_ROOT=/sys/kernel/config/usb_gadget GADGET_NAME=g1 \
	GADGET_FUNCTION=mass_storage.usb0 GADGET_LINK=f1 \
	SD_DEV=/tmp/fake_disk SETUSBCONFIG=/bin/setusbconfig
. /mnt/SDCARD/Tools/USBStorageMode.pak/usb_gadget.sh
usb_gadget_export any; echo "  export_rc=$?"
st
echo "  udc field=[$(cat $G/UDC)]"
echo "  configs=[$(ls $G/configs/c.1/ | tr '\n' ' ')]"
echo "  lun=[$(cat $G/functions/mass_storage.usb0/lun.0/file 2>/dev/null)]"
sleep 3
echo "  after 3s:"; st

echo "=== C. now detach ADB properly, then export again ==="
usb_gadget_release
st
echo "" > $G/UDC; sleep 1
rm -f $G/configs/c.1/ffs.adb $G/configs/c.1/f1
sleep 1
echo "  after unbind:"; st
setusbconfig mass_storage; echo "  setusbconfig_rc=$?"
echo "$SD_DEV" > $G/functions/mass_storage.usb0/lun.0/file
st; chg
sleep 3
echo "  after 3s:"; st

echo "=== D. cleanup ==="
usb_gadget_release
rmdir $G/functions/mass_storage.usb0/lun.0 2>/dev/null
rmdir $G/functions/mass_storage.usb0 2>/dev/null
setusbconfig adb
rm -f /tmp/fake_disk
echo "  final functions=[$(ls $G/functions/ | tr '\n' ' ')]"
st
echo "=== END ==="
