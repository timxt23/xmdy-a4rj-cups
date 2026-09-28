#!/bin/sh
# Create or update CUPS queues for XMDY A4RJ printers.
#   sudo setup-queue.sh              USB queue XMDY_A4 (printer must be connected)
#   sudo setup-queue.sh --bluetooth  Bluetooth queue XMDY_A4_BT (printer must be paired:
#                                    run /Library/Printers/XMDY-A4/xmdy-btpair first)
# An optional last argument sets the queue name.
# SPDX-License-Identifier: MIT
set -e
PPDS="/Library/Printers/PPDs/Contents/Resources"
LABEL=io.github.timxt23.xmdy-btd
AGENT="/Library/LaunchAgents/$LABEL.plist"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0 $*"; exit 1; }

if [ "$1" = "--bluetooth" ]; then
  QUEUE="${2:-XMDY_A4_BT}"
  PPD="$PPDS/XMDY A4RJ Bluetooth.ppd"
  [ -f "$PPD" ] || { echo "Driver not installed: $PPD not found"; exit 1; }

  # paired printer: name A4RJ*, its address is saved for the bridge
  ADDR=$(system_profiler SPBluetoothDataType 2>/dev/null |
         awk '/^ +A4RJ[^:]*:$/ {f=1; next} f && /Address:/ {print $2; exit}')
  if [ -z "$ADDR" ]; then
    echo "The printer is not paired with this Mac. Turn it on, then run as your user (no sudo):"
    echo "  /Library/Printers/XMDY-A4/xmdy-btpair"
    exit 2
  fi
  echo "$ADDR" | tr ':' '-' > /Library/Printers/XMDY-A4/bt-address

  # 1.1.0 development builds used a system daemon, which cannot get Bluetooth access
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "/Library/LaunchDaemons/$LABEL.plist"

  # the bridge runs in the logged-in user's session
  CONSOLE_UID=$(stat -f %u /dev/console)
  if [ "$CONSOLE_UID" != 0 ]; then
    launchctl bootout "gui/$CONSOLE_UID/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$CONSOLE_UID" "$AGENT"
  fi
  URI="socket://127.0.0.1:9101"
  LOCATION="Bluetooth $ADDR"
else
  QUEUE="${1:-XMDY_A4}"
  PPD="$PPDS/XMDY A4RJ.ppd"
  [ -f "$PPD" ] || { echo "Driver not installed: $PPD not found"; exit 1; }
  URI=$(lpinfo --include-schemes usb -v 2>/dev/null | awk '/usb:\/\/XMDY\//{print $2; exit}')
  if [ -z "$URI" ]; then
    echo "No XMDY printer found on USB. Connect and power on the printer, then run:"
    echo "  sudo $0 $QUEUE"
    exit 2
  fi
  LOCATION="USB"
fi

# hide only the generic "Printer drivers are deprecated" notice, keep real errors
lpadmin -p "$QUEUE" -E -v "$URI" -P "$PPD" -D "XMDY A4RJ" -L "$LOCATION" \
        -o printer-is-shared=false -o printer-error-policy=retry-job 2>&1 | grep -v "deprecated" >&2 || true
[ "$(lpstat -v "$QUEUE" 2>/dev/null)" ] || { echo "Failed to create queue $QUEUE"; exit 1; }
cupsenable "$QUEUE"
cupsaccept "$QUEUE"
echo "Queue $QUEUE -> $URI"

if [ "$1" = "--bluetooth" ] && [ "$CONSOLE_UID" != 0 ]; then
  # empty connection: the bridge only touches Bluetooth, so macOS asks for permission now
  nc -z 127.0.0.1 9101 >/dev/null 2>&1 || true
  echo "If macOS asks \"XMDY Bluetooth\" to use Bluetooth, click Allow."
fi
