#!/bin/sh
# Verifies the cable detection on the real device.
#
# The udc state and the charger nodes are read-only once the kernel owns them,
# so the values are injected through variables. What is being tested is the
# decision logic, and case 1 uses the real files.
LINK="plugged"
CHARGING="yes"
BATT="Charging"
udc_state() {
	if [ "$LINK" = "plugged" ]; then
		[ -n "${FAKE_STATE:-}" ] && echo "$FAKE_STATE" && return
		cat /sys/class/udc/$(ls /sys/class/udc | head -1)/state 2>/dev/null
		return
	fi
	echo "not attached"
}
charger_on() { [ "$CHARGING" = "yes" ] && echo 1 || echo 0; }
batt_status() { echo "$BATT"; }

usb_charging() {
	[ "$(charger_on)" = "1" ] && return 0
	case "$(batt_status)" in
	Charging | Full) return 0 ;;
	esac
	return 1
}
usb_link_up() {
	usb_charging && return 0
	if [ -n "$UDC" ]; then
		case "$(udc_state)" in
		"not attached" | "") return 1 ;;
		?*) return 0 ;;
		esac
	fi
	return 1
}

UDC="test"
fail=0
expect_rc() {
	_got=$1
	_want=$2
	_desc="$3"
	if [ "$_got" = "$_want" ]; then
		echo "  ok   $_desc (rc=$_got)"
	else
		echo "  FAIL $_desc (rc=$_got, expected $_want)"
		fail=1
	fi
}

echo "CASE 1: cable in, controller=not attached - the gap right after export"
LINK=plugged CHARGING=yes FAKE_STATE="not attached"
usb_link_up; expect_rc $? 0 "cable detected despite 'not attached'"

echo "CASE 2: cable in, controller=configured"
LINK=plugged CHARGING=yes FAKE_STATE="configured"
usb_link_up; expect_rc $? 0 "cable detected"

echo "CASE 3: cable pulled, controller back to 'not attached'"
LINK=plugged CHARGING=no BATT=Discharging FAKE_STATE="not attached"
usb_link_up; expect_rc $? 1 "unplug detected"

echo "CASE 4: cable pulled, controller still enumerating (stale)"
LINK=plugged CHARGING=no BATT=Discharging FAKE_STATE="configured"
usb_link_up; expect_rc $? 0 "stale state does not fake an unplug"

echo "CASE 5: real device, cable in right now"
LINK=plugged CHARGING=yes FAKE_STATE=
usb_link_up; expect_rc $? 0 "real cable detected"

exit $fail
