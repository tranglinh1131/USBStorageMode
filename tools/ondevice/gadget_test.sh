#!/bin/sh
# Exercises usb_gadget.sh on a real device against a scratch file instead of
# the SD card, so a failure cannot touch the user's data.
#
# The USB controller is NOT bound here on purpose: rebinding it drops the USB
# connection this script arrived over. That step is the same line the app runs,
# and it is verified by hand separately.
LOG=/mnt/SDCARD/.userdata/tg5040/gadget-test.txt
mkdir -p /mnt/SDCARD/.userdata/tg5040 || exit 1
: > "$LOG"
exec >>"$LOG" 2>&1
echo "=== START $(date '+%H:%M:%S') ==="

export LD_LIBRARY_PATH=/mnt/SDCARD/.system/lib:/usr/trimui/lib
export PATH=/mnt/SDCARD/.system/bin:/usr/trimui/bin:/bin:/sbin:/usr/bin:/usr/sbin

dd if=/dev/zero of=/tmp/fake_disk bs=1024 count=2048 2>/dev/null
echo "backing file: /tmp/fake_disk ($(wc -c < /tmp/fake_disk) bytes)"

export UDC="$(ls /sys/class/udc | head -1)"
export GADGET_ROOT=/sys/kernel/config/usb_gadget
export GADGET_NAME=g1 GADGET_FUNCTION=mass_storage.usb0 GADGET_LINK=f1
export SD_DEV=/tmp/fake_disk
export SETUSBCONFIG=/bin/setusbconfig
. /mnt/SDCARD/Tools/USBStorageMode.pak/usb_gadget.sh

echo "udc=$UDC"
echo "--- gadget_supported ---"
gadget_supported && echo "supported YES" || echo "supported NO"
echo "--- before ---"
echo "UDC=[$(cat /sys/kernel/config/usb_gadget/g1/UDC)]"
echo "functions=[$(ls /sys/kernel/config/usb_gadget/g1/functions/ | tr '\n' ' ')]"

echo "--- detach_adb ---"
detach_adb
echo "ffs.adb still linked? $(test -L /sys/kernel/config/usb_gadget/g1/configs/c.1/ffs.adb && echo YES || echo NO)"

echo "--- build the LUN by hand (app logic, no UDC bind) ---"
G=/sys/kernel/config/usb_gadget/g1
mkdir -p $G/functions/$GADGET_FUNCTION/lun.0
echo "$SD_DEV" > $G/functions/$GADGET_FUNCTION/lun.0/file
echo "lun file now = [$(cat $G/functions/$GADGET_FUNCTION/lun.0/file)]"
[ "$(cat $G/functions/$GADGET_FUNCTION/lun.0/file)" = "$SD_DEV" ] && echo "LUN VERIFY OK" || echo "LUN VERIFY FAIL"
ln -sf $G/functions/$GADGET_FUNCTION $G/configs/$GADGET_CONFIG/$GADGET_LINK 2>/dev/null
echo "configs/c.1 = [$(ls $G/configs/c.1/ | tr '\n' ' ')]"

echo "--- restore_adb ---"
restore_adb
echo "ffs.adb back? $(test -L $G/configs/c.1/ffs.adb && echo YES || echo NO)"
echo "=== DONE ==="
