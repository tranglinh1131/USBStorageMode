#!/bin/sh
# Integration test for the USB Storage Mode app.
#
# There is no way to test a mass-storage gadget on a desktop, so this builds a
# fake device instead: a sandbox with its own /proc/mounts, /proc/<pid>,
# /sys/class/udc, /sys/class/power_supply and /sys/kernel/config/usb_gadget
# (a plain directory tree), stub mount/umount/kill/reboot binaries, and a fake
# card. The app sources are copied in with their absolute system paths rewritten
# to the sandbox, so the real control flow runs: preflight, menu, cable wait,
# killing the card users, unmount, gadget export, cable-unplug detection, gadget
# release and the exit.
#
#   sh tools/test_flow.sh
#
# What it cannot prove: that the hardware/kernel accepts the gadget, and that
# show2.elf draws anything. Those need the device.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PAK="$HERE/../USBStorageMode.pak"
SB="$(mktemp -d /tmp/nxusb-test.XXXXXX)"
S="$SB"
PASS=0
FAIL=0

say() { printf '%s\n' "$*"; }
ok() {
	PASS=$((PASS + 1))
	printf '  ok   %s\n' "$1"
}
no() {
	FAIL=$((FAIL + 1))
	printf '  FAIL %s\n' "$1"
}
check() { # <description> <command...>
	_desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then ok "$_desc"; else no "$_desc"; fi
}
check_log() { # <description> <pattern>
	if grep -q "$2" "$CARD_LOG" "$SESSION_LOG" 2>/dev/null; then ok "$1"; else no "$1"; fi
}
check_nolog() {
	if grep -q "$2" "$CARD_LOG" "$SESSION_LOG" 2>/dev/null; then no "$1"; else ok "$1"; fi
}

cleanup() {
	if [ "${KEEP_SANDBOX:-0}" = 1 ]; then
		say "sandbox kept at $SB"
	else
		rm -rf "$SB"
	fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. sandbox device
# ---------------------------------------------------------------------------
mkdir -p "$S/proc/100/cwd" "$S/proc/101" "$S/proc/102" "$S/sys/class/udc/musb-hdrc" \
	"$S/sys/class/power_supply/axp2202-usb" \
	"$S/sys/class/power_supply/axp2202-battery" \
	"$S/sys/kernel/config/usb_gadget/g1/strings/0x409" \
	"$S/sys/kernel/config/usb_gadget/g1/configs/c.1/strings/0x409" \
	"$S/sys/kernel/config/usb_gadget/g1/functions/ffs.adb" \
	"$S/sys/kernel/config/usb_gadget/g1/functions/mass_storage.usb0/lun.0" \
	"$S/sys/class/gadget" \
	"$S/bin" "$S/tmp" \
	"$S/mnt/SDCARD/.system/bin" "$S/mnt/SDCARD/.system/paks/MinUI.pak" \
	"$S/mnt/SDCARD/Tools/USBStorageMode.pak" "$S/mnt/SDCARD/Roms" \
	"$S/mnt/SDCARD/.userdata/tg5040" \
	"$S/logs"

# The firmware owns gadget g1 with ADB bound to it, exactly as on the device.
ln -sf "$S/sys/kernel/config/usb_gadget/g1/functions/ffs.adb" \
	"$S/sys/kernel/config/usb_gadget/g1/configs/c.1/ffs.adb"
echo "0x18d1" > "$S/sys/kernel/config/usb_gadget/g1/idVendor"
echo "0xd002" > "$S/sys/kernel/config/usb_gadget/g1/idProduct"
echo "TRIMUI" > "$S/sys/kernel/config/usb_gadget/g1/strings/0x409/manufacturer"
echo "TRIMUI ADB" > "$S/sys/kernel/config/usb_gadget/g1/strings/0x409/product"
echo musb-hdrc > "$S/sys/kernel/config/usb_gadget/g1/UDC"

# The card "partition". A real one is a block device; here it is a regular file,
# which is why the app copy is patched to test -e instead of -b.
: > "$S/mmcblk1p1"

cat > "$S/proc/mounts" <<EOF
/dev/root / squashfs ro,relatime 0 0
proc /proc proc rw,relatime 0 0
$S/mmcblk1p1 $S/mnt/SDCARD exfat rw,relatime 0 0
EOF

# PID 100 is a launcher daemon holding the card (cwd inside .system/bin), PID
# 101 is innocent. PID 102 is the NX Redux launcher itself - it also holds the
# card, and the exit path has to notice that.
rm -rf "$S/proc/100/cwd"
ln -s "$S/mnt/SDCARD/.system/bin" "$S/proc/100/cwd"
ln -s /bin/sh "$S/proc/101/exe" 2>/dev/null || true
rm -rf "$S/proc/102/cwd"
ln -s "$S/mnt/SDCARD/.system/paks/MinUI.pak" "$S/proc/102/cwd"
echo keymon > "$S/proc/100/comm"
echo sleep > "$S/proc/101/comm"
echo sh > "$S/proc/102/comm"
: > "$S/proc/101/maps"
: > "$S/proc/102/maps"
printf '/bin/sh\0%s/.system/paks/MinUI.pak/launch.sh\0' "$S/mnt/SDCARD" > "$S/proc/102/cmdline"
printf '/mnt/SDCARD\0' > "$S/proc/102/environ"

echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
echo 0 > "$S/sys/class/power_supply/axp2202-usb/online"
echo Discharging > "$S/sys/class/power_supply/axp2202-battery/status"

# fake card content
cp "$PAK"/* "$S/mnt/SDCARD/Tools/USBStorageMode.pak/"

# stand-ins for the two NX Redux binaries
cat > "$S/mnt/SDCARD/.system/bin/options.elf" <<EOF
#!/bin/sh
# prints the entry the "user" picks; MENU_PICK picks which one
for a in "\$@"; do
	case "\$prev" in --entry) echo "\$a" >> "$S/menu.log" ;; esac
	prev="\$a"
done
echo "$S/tmp/nxusb/act_start.sh"
EOF
cat > "$S/mnt/SDCARD/.system/bin/show2.elf" <<EOF
#!/bin/sh
# stand-in for the NX Redux status screen: creates the FIFO, records the text
# lines it is sent, and stays alive until killed.
# One process on purpose. A reader in a background subshell outlives "kill -9",
# so every run would leak another one - which is exactly the leftover daemon
# that ui_show's stray process sweep exists to clean up.
echo "show2 \$@" >> "$S/show2.log"
rm -f "$S/tmp/show2.fifo"
mkfifo "$S/tmp/show2.fifo" 2>/dev/null
while :; do
	while IFS= read -r -t 1 _line; do
		echo "\$_line" >> "$S/show2.log"
	done < "$S/tmp/show2.fifo"
done
EOF
cat > "$S/mnt/SDCARD/.system/paks/MinUI.pak/launch.sh" <<'EOF'
#!/bin/sh
echo "launcher restarted" >> "$LAUNCHER_RESTARTED"
EOF
chmod +x "$S/mnt/SDCARD/.system/bin/"* "$S/mnt/SDCARD/.system/paks/MinUI.pak/launch.sh"

# ---------------------------------------------------------------------------
# 2. stub system binaries
# ---------------------------------------------------------------------------
# mount [-t FSTYPE] [-o OPTS] SPEC MOUNTPOINT - keeps $S/proc/mounts honest,
# including remounts (which rewrite the options of an existing entry).
cat > "$S/bin/mount" <<EOF
#!/bin/sh
echo "mount \$@" >> "$S/mount.log"
_type=""; _opts=""; _spec=""; _mp=""; _n=0
while [ \$# -gt 0 ]; do
	case "\$1" in
	-t) _type="\$2"; shift 2 ;;
	-o) _opts="\$2"; shift 2 ;;
	-o?*) _opts="\${1#-o}"; shift ;;
	-*) shift ;;
	*)
		if [ "\$_n" = 0 ]; then _spec="\$1"; else _mp="\$1"; fi
		_n=\$((_n + 1))
		shift
		;;
	esac
done
case ",\$_opts," in
*,remount,*) _remount=1 ;;
*) _remount=0 ;;
esac
if [ "\$_remount" = 1 ]; then
	awk -v m="\$_mp" -v o="\$_opts" -v t="\${_type:-exfat}" \\
		'\$2 == m { print \$1, \$2, (t == "" ? \$3 : t), o, "0", "0"; next } { print }' \\
		"$S/proc/mounts" > "$S/proc/mounts.new"
else
	[ -n "\$_mp" ] || exit 1
	printf '%s %s %s %s 0 0\n' "\$_spec" "\$_mp" "\${_type:-exfat}" "\${_opts:-rw,relatime}" \\
		>> "$S/proc/mounts"
	: > "$S/proc/mounts.new"
fi
if [ -s "$S/proc/mounts.new" ]; then
	mv -f "$S/proc/mounts.new" "$S/proc/mounts"
fi
exit 0
EOF
# configfs in miniature: the attribute files (idVendor, UDC, manufacturer, ...)
# cannot be unlinked, the kernel drops them when their directory is removed.
cat > "$S/bin/rmdir" <<EOF
#!/bin/sh
echo "rmdir \$@" >> "$S/mount.log"
for _d in "\$@"; do
	[ -d "\$_d" ] || continue
	rm -f "\$_d"/* 2>/dev/null
done
exec /bin/rmdir "\$@"
EOF
# mkdir in miniature: under usb_gadget only a real function directory can be
# created. The kernel rejects anything else with ENOMEM, which the app must not
# read as an out-of-memory problem. Everything outside usb_gadget is a normal
# directory, so the app's own /tmp staging keeps working.
cat > "$S/bin/mkdir" <<EOF
#!/bin/sh
echo "mkdir \$@" >> "$S/mkdir.log"
case "\$*" in
*"sys/kernel/config/usb_gadget"*)
	for _d in "\$@"; do
		case "\$_d" in
		*/sys/kernel/config/usb_gadget/*)
			case "\$_d" in
			*"/functions/"*)
				/bin/mkdir -p "\$_d" 2>/dev/null || exit 1
				;;
			*)
				echo "mkdir: cannot create directory '\$_d': Cannot allocate memory" >&2
				exit 1
				;;
			esac
			;;
		esac
	done
	/bin/mkdir "\$@" 2>/dev/null || exit 1
	exit 0
	;;
esac
exec /bin/mkdir "\$@"
EOF
cat > "$S/bin/umount" <<EOF
#!/bin/sh
echo "umount \$@" >> "$S/mount.log"
case "\$1" in -l | -f) shift ;; esac
awk -v m="\$1" '\$2 != m' "$S/proc/mounts" > "$S/proc/mounts.new"
mv -f "$S/proc/mounts.new" "$S/proc/mounts"
exit 0
EOF
for stub in sync swapoff modprobe lsmod dmesg; do
	printf '#!/bin/sh\necho "%s \$@" >> "%s/stub.log"\nexit 0\n' "$stub" "$S" > "$S/bin/$stub"
done
cat > "$S/bin/kill" <<EOF
#!/bin/sh
echo "kill \$@" >> "$S/kill.log"
exit 0
EOF
# reboot/busybox reboot: on the device these never return - the machine goes
# down. Here they mark the sandbox and take the app down with them, so the
# app's own exit code is a signal death rather than its own return value.
cat > "$S/bin/reboot" <<EOF
#!/bin/sh
echo "reboot \$@" >> "$S/reboot.log"
touch "$S/rebooted"
kill -TERM "\$PPID" 2>/dev/null
sleep 5
exit 0
EOF
cat > "$S/bin/busybox" <<EOF
#!/bin/sh
echo "busybox \$@" >> "$S/reboot.log"
touch "$S/rebooted"
kill -TERM "\$PPID" 2>/dev/null
sleep 5
exit 0
EOF
chmod +x "$S/bin"/*

# /bin/setusbconfig stand-in, modelled on the real one: the firmware tool owns
# gadget g1, and its mass_storage branch points the LUN at the whole disk, which
# is why the app has to rewrite the LUN file afterwards.
cat > "$S/bin/setusbconfig" <<EOF
#!/bin/sh
G=$S/sys/kernel/config/usb_gadget/g1
echo "setusbconfig \$@" >> "$S/setusb.log"
if [ \$# -eq 0 ]; then
	echo "          adb,    support adb function"
	echo "  adb,mass_storage support adb and mass_storage function"
	exit 1
fi
case "\$1" in
adb)
	mkdir -p \$G/functions/ffs.adb 2>/dev/null
	echo "TRIMUI ADB" > \$G/strings/0x409/product
	ln -sf \$G/functions/ffs.adb \$G/configs/c.1/ffs.adb
	mkdir -p "\$S/dev/usb-ffs/adb"
	;;
mass_storage | mass_storage,adb | adb,mass_storage)
	# configfs builds the lun.0 subtree itself; the stub lets /bin/mkdir do it
	# because the directory already exists in the sandbox
	/bin/mkdir -p \$G/functions/mass_storage.usb0/lun.0 2>/dev/null || exit 1
	echo TRIMUI > \$G/functions/mass_storage.usb0/lun.0/inquiry_string
	echo "$S/whole_disk" > \$G/functions/mass_storage.usb0/lun.0/file || exit 1
	ln -sf \$G/functions/mass_storage.usb0 \$G/configs/c.1/f1
	[ "\$1" = "mass_storage,adb" ] && {
		mkdir -p \$G/functions/ffs.adb 2>/dev/null
		ln -sf \$G/functions/ffs.adb \$G/configs/c.1/ffs.adb
	}
	;;
# an argument the firmware does not implement: exits 0 without creating a LUN,
# exactly like the real binary, so the app must not trust the exit status alone
unimplemented_thing)
	echo "ignored"
	;;
none) ;;
*) echo "Invalid arg:\$1"; exit 1 ;;
esac
echo musb-hdrc > \$G/UDC
exit 0
EOF
chmod +x "$S/bin/setusbconfig"

# ---------------------------------------------------------------------------
# 3. the app, with absolute system paths pointed at the sandbox
# ---------------------------------------------------------------------------
mkdir -p "$S/app"
cp "$PAK/icon.png" "$PAK/settings.conf" "$S/app/"
for f in usb_mode.sh usb_gadget.sh launch.sh; do
	sed -e "s#/proc/#@@SB@@/proc/#g" \
		-e "s#/sys/#@@SB@@/sys/#g" \
		-e "s#/tmp/stay_awake#$S/tmp/stay_awake#g" \
		-e "s#/tmp/show2.fifo#$S/tmp/show2.fifo#g" \
		-e "s#/dev/input/event\*#$S/dev/input/event*#g" \
		-e "s#^PATH=\"\$SESSION_DIR:#PATH=\"$S/bin:\$SESSION_DIR:#" \
		-e "s#if \[ -z \"\\\$SD_DEV\" \] || \[ ! -b \"\\\$SD_DEV\" \]#if [ -z \"\\\$SD_DEV\" ] || [ ! -e \"\\\$SD_DEV\" ]#" \
		"$PAK/$f" > "$S/app/$f"
	sed -i '' -e "s#@@SB@@#$S#g" "$S/app/$f"
done
cp "$PAK/settings.conf" "$S/app/settings.conf"
chmod +x "$S/app"/*.sh

CARD_LOG="$S/logs/usb-storage-mode.txt"
SESSION_LOG="$S/tmp/nxusb/session.log"
export LAUNCHER_RESTARTED="$S/launcher.restarted"

say "== sandbox: $S"
say "== run 1: full session (card present, menu start, cable plugged, then unplugged)"

# plug the cable in shortly after the app starts, unplug it a few seconds later
# The cable is plugged in as soon as the app asks for it (the UDC state file
# stands in for what a real controller reports) and pulled again after a while.
plug() {
	echo 1 > "$S/sys/class/power_supply/axp2202-usb/online"
	echo Charging > "$S/sys/class/power_supply/axp2202-battery/status"
	# On the device the controller only reaches "configured" a few seconds after
	# the LUN is exported and sits at "not attached" until then. Reproduce that:
	# the app must not read that gap as an unplugged cable.
	echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
	(
		sleep 3
		echo configured > "$S/sys/class/udc/musb-hdrc/state"
	) &
}
unplug() {
	echo 0 > "$S/sys/class/power_supply/axp2202-usb/online"
	echo Discharging > "$S/sys/class/power_supply/axp2202-battery/status"
	echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
}

(
	while [ ! -f "$S/want_cable_in" ]; do sleep 0.2; done
	plug
	while [ ! -f "$S/want_cable_out" ]; do sleep 0.2; done
	unplug
) &
CABLE_PID=$!
: > "$S/want_cable_in"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh" &
APP_PID=$!

# pull the cable once the session is up, so the unplug path is exercised
(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do
		kill -0 "$APP_PID" 2>/dev/null || exit 0
		sleep 0.2
	done
	sleep 3
	: > "$S/want_cable_out"
) &
UNPLUG_PID=$!

wait "$APP_PID"
RC=$?
kill "$CABLE_PID" "$UNPLUG_PID" 2>/dev/null

say "  (exit code $RC)"
say "-- results"

# RC is the shell's report of the app dying with the (simulated) reboot, so it
# is a signal here - what matters is that the app did not exit on its own.
check "app reached the reboot instead of returning" test "$RC" != 0
check_log "preflight passed" "device: card=$S/mmcblk1p1"
check_log "menu picked the start entry" "menu returned"
check_log "the card-holder daemon was stopped" "stopping keymon"
check_log "the card was unmounted" "card released: mode=free"
check_log "the gadget was exported" "USB mode active"
# the regression this run guards: the controller reads "not attached" for the
# first seconds, and the app used to take that for an unplug and reboot at once
check_log "the computer was waited for" "the computer picked the drive up"
check_nolog "no premature exit while enumerating" "did not pick the drive up"
check_log "the unplug ended the session" "cable disconnected"
check_log "the missing input node was reported" "no input device"
check_log "the gadget was released" "releasing the gadget"
check_log "the device was restarted" "restarting the device"
check_nolog "no PREFLIGHT failure" "PREFLIGHT"
check_nolog "no unmount failure" "trying a lazy unmount"

check "the card is unmounted at the end" \
	sh -c "! awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "the mass-storage link was removed" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"
check "the mass-storage function was removed" \
	sh -c "! test -d '$S/sys/kernel/config/usb_gadget/g1/functions/mass_storage.usb0'"
check "only ADB is left in the gadget" \
	sh -c '[ "$(ls "$1" | tr "\n" " ")" = "ffs.adb " ]' _ \
	"$S/sys/kernel/config/usb_gadget/g1/functions"
check_log "the gadget was unbound before removal" "releasing the gadget"
check_log "the LUN pointed at the card partition" "lun=$S/mmcblk1p1"
check_log "the firmware's own tool was used" "backend=firmware"
check "no second usb_gadget was created" \
	test "$(ls "$S/sys/kernel/config/usb_gadget" | wc -l | tr -d ' ')" = 1
check "ADB was restored afterwards" \
	sh -c "test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/ffs.adb'"
check "the device was told to reboot" test -f "$S/rebooted"
check "the status screen ran" test -s "$S/show2.log"
check "the app stayed out of the way of the card" \
	sh -c "! grep -q '$S/mnt/SDCARD/Tools' '$SESSION_LOG'"

say ""
say "-- session log"
cat "$SESSION_LOG" 2>/dev/null | sed 's/^/  | /'

# ---------------------------------------------------------------------------
# 4. a second run: cancel at the menu, nothing must change
#
# The card is put back first: run 1 ended in a simulated reboot, which on the
# device means the bootloader mounts it again. Mounting it back is also exactly
# what the app does when a reboot call does not take the machine down.
# ---------------------------------------------------------------------------
say ""
say "== run 2: cancel at the menu (the card must stay exactly as it was)"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log"
: > "$S/kill.log"
: > "$S/mount.log"

# the "user" presses Cancel: options.elf prints nothing
cat > "$S/mnt/SDCARD/.system/bin/options.elf" <<EOF
#!/bin/sh
echo ""
EOF
chmod +x "$S/mnt/SDCARD/.system/bin/options.elf"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	/bin/sh "$S/app/launch.sh"
RC2=$?

check "app exited cleanly" test "$RC2" = 0
check_log "the cancel was honoured" "cancelled by the user"
check "the card was not unmounted" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "nothing was killed" sh -c "! test -s '$S/kill.log'"
check "nothing was mounted or unmounted" \
	sh -c "! grep -qE '^(mount|umount) ' '$S/mount.log'"
check "no gadget was created" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"

# ---------------------------------------------------------------------------
# 5. a third run: unsupported device (no UDC at all)
# ---------------------------------------------------------------------------
say ""
say "== run 3: no USB controller - must refuse instead of guessing"
rm -f "$S/sys/class/udc/musb-hdrc/state"
rmdir "$S/sys/class/udc/musb-hdrc"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	/bin/sh "$S/app/launch.sh"
RC3=$?

check "app exited non-zero" test "$RC3" != 0
check_log "the missing controller was reported" "no USB device controller"
# the reason goes to the screen, not the log
check "the user was told why" \
	sh -c "grep -q 'cannot be put into USB storage mode' '$S/show2.log'"
check "the card was not unmounted" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "nothing was killed" sh -c "! test -s '$S/kill.log'"
check "no gadget was created" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"

# ---------------------------------------------------------------------------
# 6. a fourth run: EXIT_ACTION=menu must put the card back and return to the
#    launcher instead of rebooting
# ---------------------------------------------------------------------------
say ""
say "== run 4: EXIT_ACTION=menu (card mounted again, launcher restarted)"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
mkdir -p "$S/sys/class/udc/musb-hdrc"
echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
: > "$S/want_cable_out"
cp "$PAK/settings.conf" "$S/app/settings.conf"
printf 'EXIT_ACTION=menu\nCABLE_WAIT=5\n' >> "$S/app/settings.conf"
cat > "$S/mnt/SDCARD/.system/bin/options.elf" <<EOF
#!/bin/sh
echo "$S/tmp/nxusb/act_start.sh"
EOF
chmod +x "$S/mnt/SDCARD/.system/bin/options.elf"

(
	while [ ! -f "$S/want_cable_in4" ]; do sleep 0.2; done
	plug
	while [ ! -f "$S/want_cable_out4" ]; do sleep 0.2; done
	unplug
) &
CABLE4_PID=$!

(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do sleep 0.2; done
	sleep 2
	: > "$S/want_cable_out4"
) &
UNPLUG4_PID=$!
: > "$S/want_cable_in4"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh" &
APP4_PID=$!
wait "$APP4_PID"
RC4=$?
kill "$CABLE4_PID" "$UNPLUG4_PID" 2>/dev/null

check "app returned to the launcher" test "$RC4" = 0
check_log "settings.conf was honoured" "the pak launcher is among them"
check "the card was put back before returning" \
	sh -c "grep -q 'mounting $S/mmcblk1p1 back on' '$SESSION_LOG'"
check "the card is mounted again" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "the launcher was restarted" test -s "$S/launcher.restarted"
check "the device did not reboot" sh -c "! test -f '$S/rebooted'"
check "the gadget was still released" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"

# ---------------------------------------------------------------------------
# 7. run 5: pressing a button ends the session
#
# This is the escape hatch for a user whose cable is stuck or who simply does
# not want to restart. The evdev node is a FIFO here: the app reads records
# from it exactly as it does on the device, and the test writes one key press
# into it once the session is up.
# ---------------------------------------------------------------------------
say ""
say "== run 5: pressing a button ends the session"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
mkdir -p "$S/dev/input"
rm -f "$S/dev/input/event0"
mkfifo "$S/dev/input/event0"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
: > "$S/want_cable_out"
cp "$PAK/settings.conf" "$S/app/settings.conf"
printf 'EXIT_ACTION=menu\nCABLE_WAIT=5\nSAFE_EXIT_WAIT=2\nSESSION_MAX=15\n' >> "$S/app/settings.conf"

(
	while [ ! -f "$S/want_cable_in5" ]; do sleep 0.2; done
	plug
) &
PLUG5_PID=$!
: > "$S/want_cable_in5"

(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do sleep 0.2; done
	sleep 2
	# BTN_SOUTH (0x130) pressed and released: type 1, code 0x0130, value 1
	# inside a 24 byte input_event, little endian
	printf '\001\000\060\001\001\000\000\000\000\000\000\000\000\000\000\000\001\000\060\001\001\000\000\000' > "$S/dev/input/event0"
	printf '\001\000\060\001\000\000\000\000\000\000\000\000\000\000\000\000\001\000\060\001\000\000\000\000' > "$S/dev/input/event0"
) &
KEY5_PID=$!

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh" &
APP5_PID=$!
# the run has to fail rather than hang if a step goes wrong
(
	_n=0
	while [ "$_n" -lt 90 ]; do
		kill -0 "$APP5_PID" 2>/dev/null || exit 0
		sleep 1
		_n=$((_n + 1))
	done
	echo "watchdog: the run did not finish, killing it" >> "$SESSION_LOG"
	kill -9 "$APP5_PID" 2>/dev/null
) &
WATCH5_PID=$!
wait "$APP5_PID"
RC5=$?
kill "$WATCH5_PID" 2>/dev/null
kill "$PLUG5_PID" "$KEY5_PID" 2>/dev/null

check "the button ended the session" test "$RC5" = 0
check_log "the button press was noticed" "button pressed after"
check_log "the drive was held before letting go" "holding the drive for 2s"
# the countdown goes on the screen, not into the log
check "the countdown was put on screen" \
	sh -c "grep -q 'do not unplug yet' '$S/show2.log'"
check_log "the gadget was released" "releasing the gadget"
check_nolog "the unplug was not what ended it" "cable disconnected"
check "the card was put back" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "the launcher was restarted" test -s "$S/launcher.restarted"

# ---------------------------------------------------------------------------
# 8. run 6: the reboot call is rejected
#
# This is the failure that left the device unusable: the session stops the
# launcher along with everything else that was holding the card, so if the
# reboot is refused and the app just exits, the user is left with no menu and
# no card - a black screen that only a power cycle gets out of.
# ---------------------------------------------------------------------------
say ""
say "== run 6: a reboot call that is refused must not strand the device"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
cp "$PAK/settings.conf" "$S/app/settings.conf"
for f in reboot busybox; do
	cat > "$S/bin/$f" <<EOF
#!/bin/sh
echo "$f \$@" >> "$S/reboot.log"
exit 1
EOF
done
chmod +x "$S/bin/reboot" "$S/bin/busybox"

: > "$S/want_cable_in6"
(
	while [ ! -f "$S/want_cable_out6" ]; do sleep 0.2; done
	unplug
) &
CABLE6_PID=$!
(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do sleep 0.2; done
	sleep 2
	: > "$S/want_cable_out6"
) &
UNPLUG6_PID=$!

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh"
RC6=$?
kill "$CABLE6_PID" "$UNPLUG6_PID" 2>/dev/null

check_log "the refused reboot was noticed" "did not restart"
check_log "the recovery was logged" "putting the card and the launcher back"
check "the card is mounted again" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "the launcher came back" test -s "$S/launcher.restarted"
check "the gadget was released first" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"

# ---------------------------------------------------------------------------
# 9. run 7: the main script wedges
#
# This is the failure that was reported from the device: a session that sat at
# "waiting for the computer" with nothing left in the log, and the only way out
# was holding the power button. The app cannot tell it is stuck, so the watchdog
# is the thing under test here - the app's own wait is replaced by a loop that
# never finishes and the device has to restart itself anyway.
# ---------------------------------------------------------------------------
say ""
say "== run 7: a wedged script must not hold the device"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
mkdir -p "$S/sys/class/udc/musb-hdrc"
echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
: > "$S/want_cable_out"
cp "$PAK/settings.conf" "$S/app/settings.conf"
printf 'WATCHDOG_STALL=10\nCABLE_WAIT=5\n' >> "$S/app/settings.conf"

# run 6 left a reboot stub that always fails; this run needs the real behaviour,
# because the whole point is that the watchdog manages to restart the machine.
cat > "$S/bin/reboot" <<EOF
#!/bin/sh
echo "reboot \$@" >> "$S/reboot.log"
touch "$S/rebooted"
kill -TERM "\$PPID" 2>/dev/null
sleep 5
exit 0
EOF
cat > "$S/bin/busybox" <<EOF
#!/bin/sh
echo "busybox \$@" >> "$S/reboot.log"
touch "$S/rebooted"
kill -TERM "\$PPID" 2>/dev/null
sleep 5
exit 0
EOF
chmod +x "$S/bin/reboot" "$S/bin/busybox"
rm -f "$S/rebooted"

# Reading the controller state is what wedged the app on the device, so that is
# what gets wedged here. The block is long enough for the watchdog to notice and
# restart the machine, short enough that the run still finishes.
cat > "$S/bin/cat" <<EOF
#!/bin/sh
for _a in "\$@"; do
	case "\$_a" in
	*/sys/class/udc/*)
		[ -f "$S/stuck" ] && exec sleep 45
		;;
	esac
done
exec /bin/cat "\$@"
EOF
chmod +x "$S/bin/cat"
: > "$S/stuck"

: > "$S/want_cable_in7"
(
	while [ ! -f "$S/want_cable_out7" ]; do sleep 0.2; done
	unplug
) &
CABLE7_PID=$!
(
	while [ ! -f "$S/want_cable_in7" ]; do sleep 0.2; done
	plug
) &
PLUG7_PID=$!
: > "$S/want_cable_in7"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh" &
APP7_PID=$!
(
	_n=0
	while [ "$_n" -lt 120 ]; do
		kill -0 "$APP7_PID" 2>/dev/null || exit 0
		sleep 1
		_n=$((_n + 1))
	done
	kill -9 "$APP7_PID" 2>/dev/null
) &
WATCH7_PID=$!
wait "$APP7_PID"
RC7=$?
kill "$WATCH7_PID" "$CABLE7_PID" "$PLUG7_PID" 2>/dev/null

check_log "the stall was noticed" "WATCHDOG: no progress"
check_log "the stuck state was recorded" "WATCHDOG: parent="
check "the device was restarted anyway" test -f "$S/rebooted"
check "the app did not just sit there" test "$RC7" != 0

# run 8 needs a controller that answers at once
rm -f "$S/stuck" "$S/bin/cat"

# ---------------------------------------------------------------------------
# 10. run 8: a launcher that is not a pak, and brings no menu tool
#
# The launchers that read Tools/*.pak all agree on the layout, so one package
# covers MinUI, NextUI and NX Redux. They do not agree on everything else: one of
# them can also be a menu binary out of the rootfs rather than a pak on the card,
# and not all of them carry a menu tool. Both are exercised here, because the app
# has to fall back to using the cable as the confirmation and has to recognise a
# second kind of launcher to bring back.
# ---------------------------------------------------------------------------
say ""
say "== run 8: a launcher with no menu tool (the cable confirms instead)"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
mkdir -p "$S/sys/class/udc/musb-hdrc"
echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
: > "$S/want_cable_out"
cp "$PAK/settings.conf" "$S/app/settings.conf"
printf 'EXIT_ACTION=menu\nCABLE_WAIT=20\nSAFE_EXIT_WAIT=2\n' >> "$S/app/settings.conf"

# no launcher pak is in play here: neither on the card nor running
mv "$S/mnt/SDCARD/.system/paks/MinUI.pak/launch.sh" "$S/minui.saved"
rm -rf "$S/proc/102"
# NextUI has no options.elf, so there is no menu to pick from
mv "$S/mnt/SDCARD/.system/bin/options.elf" "$S/options.saved"
# a launcher that is not a pak at all: the firmware's own menu binary. This is
# the shape detect_launcher has to cope with as well, and the process is faked
# here rather than a pak so the other branch is actually covered
mkdir -p "$S/proc/200"
rm -rf "$S/proc/200/cwd"
ln -s "$S/mnt/SDCARD/.system/bin" "$S/proc/200/cwd"
echo MainUI > "$S/proc/200/comm"
: > "$S/proc/200/maps"
printf '/usr/trimui/bin/MainUI\0' > "$S/proc/200/cmdline"
printf '/mnt/SDCARD\0' > "$S/proc/200/environ"
# and it has to be startable again
cat > "$S/stock_mainui.sh" <<EOF
#!/bin/sh
echo "menu launcher restarted" >> "\$LAUNCHER_RESTARTED"
EOF
chmod +x "$S/stock_mainui.sh"

: > "$S/want_cable_in8"
(
	while [ ! -f "$S/want_cable_out8" ]; do sleep 0.2; done
	unplug
) &
CABLE8_PID=$!
(
	while [ ! -f "$S/want_cable_in8" ]; do sleep 0.2; done
	plug
) &
PLUG8_PID=$!
: > "$S/want_cable_in8"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	STOCK_LAUNCHER="$S/stock_mainui.sh" \
	EXIT_ACTION=menu \
	/bin/sh "$S/app/launch.sh" &
APP8_PID=$!
(
	_n=0
	while [ "$_n" -lt 120 ]; do
		kill -0 "$APP8_PID" 2>/dev/null || exit 0
		sleep 1
		_n=$((_n + 1))
	done
	kill -9 "$APP8_PID" 2>/dev/null
) &
WATCH8_PID=$!
(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do sleep 0.2; done
	sleep 2
	: > "$S/want_cable_out8"
) &
UNPLUG8_PID=$!
wait "$APP8_PID"
RC8=$?
kill "$WATCH8_PID" "$CABLE8_PID" "$PLUG8_PID" "$UNPLUG8_PID" 2>/dev/null

check_log "a non-pak launcher was recognised" "launcher: binary"
check_log "no menu tool, so the cable confirms" "no menu tool, using the cable"
check_log "the launcher was taken down with the card" "binary launcher is among them"
check "the launcher was brought back" \
	sh -c "grep -q 'menu launcher restarted' '$S/launcher.restarted'"
check "the card was put back" \
	sh -c "awk -v m='$S/mnt/SDCARD' '\$2 == m { found = 1 } END { exit found ? 0 : 1 }' '$S/proc/mounts'"
check "the gadget was still released" \
	sh -c "! test -L '$S/sys/kernel/config/usb_gadget/g1/configs/c.1/f1'"

mv "$S/minui.saved" "$S/mnt/SDCARD/.system/paks/MinUI.pak/launch.sh"
mv "$S/options.saved" "$S/mnt/SDCARD/.system/bin/options.elf"

# ---------------------------------------------------------------------------
# 11. run 9: a different panel
#
# The status screen is the only part of this app that can care what machine it
# is on: show2.elf takes the font size and the logo height in pixels, and 128px of
# logo is a sixth of a 768px panel and half of a 272px one. The screen is asked
# instead of guessed, and this run is a 480x272 panel to prove it.
# ---------------------------------------------------------------------------
say ""
say "== run 9: the status screen scales to the panel"

/bin/sh "$S/bin/mount" -t exfat -o rw,relatime "$S/mmcblk1p1" "$S/mnt/SDCARD"
mkdir -p "$S/sys/class/udc/musb-hdrc"
echo "not attached" > "$S/sys/class/udc/musb-hdrc/state"
: > "$S/logs/usb-storage-mode.txt"
rm -f "$S/tmp/nxusb/session.log" "$S/rebooted" "$S/launcher.restarted"
: > "$S/want_cable_out"
cp "$PAK/settings.conf" "$S/app/settings.conf"
printf 'EXIT_ACTION=menu\nCABLE_WAIT=5\nSAFE_EXIT_WAIT=1\n' >> "$S/app/settings.conf"

# a 480x272 panel, which is what a Smart Pro class screen reports
cat > "$S/bin/fbset" <<EOF
#!/bin/sh
echo 'mode "480x272-60"'
echo "	geometry 480 272 480 1088 32"
echo "endmode"
EOF
chmod +x "$S/bin/fbset"

: > "$S/want_cable_in9"
(
	while [ ! -f "$S/want_cable_out9" ]; do sleep 0.2; done
	unplug
) &
CABLE9_PID=$!
(
	while [ ! -f "$S/want_cable_in9" ]; do sleep 0.2; done
	plug
) &
PLUG9_PID=$!
: > "$S/want_cable_in9"

env -i \
	PATH="$S/bin:/bin:/usr/bin:/bin" \
	HOME="$S" \
	SDCARD_PATH="$S/mnt/SDCARD" \
	SYSTEM_PATH="$S/mnt/SDCARD/.system" \
	SESSION_DIR="$S/tmp/nxusb" \
	FIFO="$S/tmp/show2.fifo" \
	LOGS_PATH="$S/logs" \
	DEVICE=brickpro \
	PLATFORM=tg5040 \
	SETUSBCONFIG="$S/bin/setusbconfig" \
	LAUNCHER_RESTARTED="$S/launcher.restarted" \
	/bin/sh "$S/app/launch.sh" &
APP9_PID=$!
(
	_n=0
	while [ "$_n" -lt 120 ]; do
		kill -0 "$APP9_PID" 2>/dev/null || exit 0
		sleep 1
		_n=$((_n + 1))
	done
	kill -9 "$APP9_PID" 2>/dev/null
) &
WATCH9_PID=$!
(
	while ! grep -q "USB mode active" "$S/tmp/nxusb/session.log" 2>/dev/null; do sleep 0.2; done
	sleep 2
	: > "$S/want_cable_out9"
) &
UNPLUG9_PID=$!
wait "$APP9_PID"
RC9=$?
kill "$WATCH9_PID" "$CABLE9_PID" "$PLUG9_PID" "$UNPLUG9_PID" 2>/dev/null

# 28 * 272 / 768 = 9, held at the 12px floor; 128 * 272 / 768 = 45
check_log "the panel size was read" "screen 480x272"
check_log "the sizes were scaled down for it" "fontsize=12 logoheight=45"
check "show2 was started with the scaled sizes" \
	sh -c "grep -q -- '--logoheight=45 --fontsize=12' '$S/show2.log'"
check "the session still worked on that panel" test "$RC9" = 0
check_log "the drive was handed over anyway" "USB mode active"

say ""
say "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]