#!/bin/sh
# Build the installable archive.
#
# One package, because the two launchers that run this app agree on how an app
# is laid out. MinUI, NextUI and NX Redux all read the same thing: a directory
# under /mnt/SDCARD/Tools named <Label>.pak holding a launch.sh, with the label
# taken from the directory name. Only /mnt/SDCARD/Apps with a config.json is the
# stock layout, and that launcher is not the one this app targets.
#
# What does differ between those launchers - whether a menu tool comes with them
# - is handled inside the app, not by shipping a second build.
set -e

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/USBStorageMode.pak.zip"

rm -f "$OUT"
cd "$HERE"
# -X drops extra fields: nothing on a FAT/exFAT card carries unix permissions
# or timestamps worth keeping, and the noise only makes the listing harder.
zip -r -q -X "$OUT" "USBStorageMode.pak" -x '*.DS_Store' '.DS_Store' '*/.DS_Store'

echo "built $(basename "$OUT")"
unzip -l "$OUT" | sed 's/^/  /'

echo
echo "On the SD card this has to end up as:"
echo "  /mnt/SDCARD/Tools/USBStorageMode.pak/launch.sh"
