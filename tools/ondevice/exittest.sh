#!/bin/sh
# Runs the app's real phase 2 (export -> wait for host -> wait for unplug ->
# release -> exit) with two deliberate differences so nothing is at risk:
#   the LUN points at a scratch file instead of the SD card
#   EXIT_ACTION=menu, so it never reboots
OUT=/mnt/SDCARD/.userdata/tg5040/exittest.txt
T=/tmp/nxtest2
mkdir -p /mnt/SDCARD/.userdata/tg5040 "$T"
: > "$OUT"

cp /mnt/SDCARD/Tools/USBStorageMode.pak/usb_gadget.sh "$T/"
cp /mnt/SDCARD/Tools/USBStorageMode.pak/usb_mode.sh "$T/"
cp /mnt/SDCARD/.system/bin/show2.elf "$T/" 2>/dev/null
cp /mnt/SDCARD/Tools/USBStorageMode.pak/icon.png "$T/" 2>/dev/null
chmod +x "$T"/*.sh "$T"/show2.elf 2>/dev/null

export LD_LIBRARY_PATH=/mnt/SDCARD/.system/lib:/mnt/SDCARD/.system/shared/lib:/usr/trimui/lib
export PATH=/mnt/SDCARD/.system/bin:/mnt/SDCARD/.system/shared/bin:/usr/trimui/bin:/bin:/sbin:/usr/bin:/usr/sbin
export SDCARD_PATH=/mnt/SDCARD SYSTEM_PATH=/mnt/SDCARD/.system
export SESSION_DIR="$T" FIFO=/tmp/show2.fifo
export DEVICE=brickpro PLATFORM=tg5040
export EXIT_ACTION=menu HOST_WAIT=25 SESSION_MAX=200 CABLE_WAIT=30
export UDC="$(ls /sys/class/udc | head -1)"
export SD_DEV=/tmp/fake_disk

echo "0 start $(date '+%H:%M:%S')" >> "$OUT"
dd if=/dev/zero of=/tmp/fake_disk bs=1024 count=131072 2>/dev/null; mkfs.vfat /tmp/fake_disk >/dev/null 2>&1; echo "   fake disk: $(wc -c < /tmp/fake_disk) bytes, vfat"
echo "1 staging done" >> "$OUT"
sh "$T/usb_mode.sh" --cardless >>/"$OUT" 2>&1
echo "2 phase2 returned rc=$?" >> "$OUT"
rm -f /tmp/fake_disk
echo "3 END $(date '+%H:%M:%S')" >> "$OUT"
