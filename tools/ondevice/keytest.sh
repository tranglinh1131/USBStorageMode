#!/bin/sh
# Exercises the app's real button watcher on the device, without touching USB or
# the card. Only the Buttons section of usb_mode.sh is sourced, so what runs
# here is exactly what runs during a session.
OUT=/mnt/SDCARD/.userdata/tg5040/keytest.txt
SECS="${1:-120}"
mkdir -p /mnt/SDCARD/.userdata/tg5040
: > "$OUT"
SESSION_DIR=/tmp/nxkeytest
rm -rf "$SESSION_DIR"
mkdir -p "$SESSION_DIR"
export SESSION_DIR

sed -n '/^# Buttons/,/^card_mounted() {/p' \
	/mnt/SDCARD/Tools/USBStorageMode.pak/usb_mode.sh | sed '$d' > "$SESSION_DIR/kf.sh"
echo "lay duoc $(wc -l < "$SESSION_DIR/kf.sh") dong cua phan Buttons" >> "$OUT"
. "$SESSION_DIR/kf.sh"

if hex_tool; then
	echo "hex tool: $HEX_TOOL" >> "$OUT"
else
	echo "KHONG co hex tool" >> "$OUT"
fi

if keys_start; then
	echo "keys_start OK, dang doc cac node:$_nodes" >> "$OUT"
else
	echo "keys_start FAIL" >> "$OUT"
	echo "DONE" >> "$OUT"
	exit 1
fi

_i=0
while [ "$_i" -lt "$SECS" ]; do
	if key_pressed; then
		echo "key_pressed YES after ${_i}s" >> "$OUT"
		echo "da doc $(wc -c < "$SESSION_DIR/keys.bin") byte" >> "$OUT"
		keys_stop
		echo "DONE" >> "$OUT"
		exit 0
	fi
	sleep 1
	_i=$((_i + 1))
	if [ $((_i % 5)) -eq 0 ]; then
		echo "cho ${_i}s, da doc $(wc -c < "$SESSION_DIR/keys.bin") byte" >> "$OUT"
	fi
done

keys_stop
echo "key_pressed NO trong ${SECS}s, da doc $(wc -c < "$SESSION_DIR/keys.bin") byte" >> "$OUT"
echo "DONE" >> "$OUT"