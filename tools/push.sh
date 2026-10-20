#!/bin/sh
# Copy a local file to the TrimUI device.
#
# The device's base64 -d refuses very long lines ("truncated base64 input") and a
# single huge ssh command line is unreliable too, so the payload goes over in
# chunks that are appended one at a time, then decoded in place.
#
#   sh tools/push.sh <local-file> <remote-path>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$1"
DST="$2"
HOST="${NX_HOST:-192.168.1.8}"
PASS="${NX_PASS:-tina}"
TMP="/tmp/nxpush.$$"

[ -n "$SRC" ] && [ -n "$DST" ] || { echo "usage: sh tools/push.sh <file> <remote>" >&2; exit 1; }
[ -f "$SRC" ] || { echo "push: no such file: $SRC" >&2; exit 1; }

rsh() { expect "$HERE/ssh-helper.exp" "$HOST" "$PASS" "$1"; }

B64=$(base64 < "$SRC" | tr -d '\n')
B64SIZE=${#B64}
rsh "rm -f $DST $TMP"

echo "push: $SRC -> $DST ($B64SIZE b64 bytes)"
CHUNK="${NX_CHUNK:-300}"
OFF=0
N=0
while [ "$OFF" -lt "$B64SIZE" ]; do
	PART=$(printf '%s' "$B64" | cut -c$((OFF + 1))-$((OFF + CHUNK)))
	rsh "printf '%s' '$PART' >> $TMP"
	OFF=$((OFF + CHUNK))
	N=$((N + 1))
	printf '\r  %d/%d bytes sent' "$OFF" "$B64SIZE"
done
printf '\n'
rsh "base64 -d $TMP > $DST; rm -f $TMP; chmod +x $DST 2>/dev/null; wc -c < $DST"
echo "push: done"
