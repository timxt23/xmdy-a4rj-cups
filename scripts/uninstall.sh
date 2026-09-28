#!/bin/sh
# Remove the XMDY A4RJ CUPS driver and its queues.
# Usage: sudo /Library/Printers/XMDY-A4/uninstall.sh
# SPDX-License-Identifier: MIT
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0"; exit 1; }

PPD_NAME="XMDY A4RJ.ppd"
# every queue whose PPD uses our filter
for q in $(lpstat -e 2>/dev/null); do
  if grep -qs "rastertoxmdy" "/etc/cups/ppd/$q.ppd"; then
    lpadmin -x "$q" && echo "Removed queue $q"
  fi
done

rm -f  "/Library/Printers/PPDs/Contents/Resources/$PPD_NAME"
rm -rf /Library/Printers/XMDY-A4
pkgutil --forget io.github.timxt23.xmdy-a4rj >/dev/null 2>&1 || true
echo "XMDY A4RJ driver removed."
