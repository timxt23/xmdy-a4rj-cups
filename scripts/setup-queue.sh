#!/bin/sh
# Create or update the CUPS queue for a connected XMDY A4RJ printer.
# Usage: sudo setup-queue.sh [queue-name]      (default: XMDY_A4)
# SPDX-License-Identifier: MIT
set -e
QUEUE="${1:-XMDY_A4}"
PPD="/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ.ppd"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0 $*"; exit 1; }
[ -f "$PPD" ] || { echo "Driver not installed: $PPD not found"; exit 1; }

URI=$(lpinfo --include-schemes usb -v 2>/dev/null | awk '/usb:\/\/XMDY\//{print $2; exit}')
if [ -z "$URI" ]; then
  echo "No XMDY printer found on USB. Connect and power on the printer, then run:"
  echo "  sudo $0 $QUEUE"
  exit 2
fi

lpadmin -p "$QUEUE" -E -v "$URI" -P "$PPD" -D "XMDY A4RJ" -L "USB" \
        -o printer-is-shared=false -o printer-error-policy=retry-job 2>/dev/null
cupsenable "$QUEUE"
cupsaccept "$QUEUE"
echo "Queue $QUEUE -> $URI"
