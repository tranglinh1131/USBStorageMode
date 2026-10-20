#!/bin/sh
# Dumps raw evdev records from every input node so the button layout on this
# hardware can be read off the wire instead of guessed. One record per dd call,
# so nothing is left sitting in a stdio buffer when the reader exits.
OUT=/mnt/SDCARD/.userdata/tg5040/keyprobe.txt
SECS="${1:-45}"
mkdir -p /mnt/SDCARD/.userdata/tg5040
: > "$OUT"
echo "seconds=$SECS  by-path: $(ls /dev/input/by-path/ 2>/dev/null | tr '\n' ' ')" >> "$OUT"

probe() {
	_tag="$1"
	_n="$2"
	_f="/tmp/kp.$_tag.txt"
	: > "$_f"
	_i=0
	while [ "$_i" -lt "$SECS" ]; do
		dd if="$_n" bs=24 count=1 2>/dev/null > /tmp/kp.rec.$_tag || break
		[ -s /tmp/kp.rec.$_tag ] || break
		_hex="$(xxd -p /tmp/kp.rec.$_tag 2>/dev/null | tr -d ' \n')"
		_ty="0x$(printf '%s' "$_hex" | cut -c33-36)"
		_cd="0x$(printf '%s' "$_hex" | cut -c37-40)"
		_vl="0x$(printf '%s' "$_hex" | cut -c41-48)"
		echo "$_i ty=$_ty code=$_cd val=$_vl hex=$_hex" >> "$_f"
		_i=$((_i + 1))
	done
	echo "END node=$_n records=$_i" >> "$_f"
	rm -f /tmp/kp.rec.$_tag
}
probe e0 /dev/input/event0 &
probe e1 /dev/input/event1 &
probe e2 /dev/input/event2 &
probe e3 /dev/input/event3 &
wait
for t in e0 e1 e2 e3; do
	echo "--- $t ---" >> "$OUT"
	cat "/tmp/kp.$t.txt" >> "$OUT" 2>/dev/null
	rm -f "/tmp/kp.$t.txt"
done
echo "DONE" >> "$OUT"
