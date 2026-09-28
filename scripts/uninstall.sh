#!/bin/sh
# Remove the XMDY A4RJ CUPS driver, its queues and the Bluetooth bridge.
# Usage: sudo /Library/Printers/XMDY-A4/uninstall.sh
# The Bluetooth pairing is kept; remove it in System Settings > Bluetooth if needed.
# SPDX-License-Identifier: MIT
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0"; exit 1; }
LABEL=io.github.timxt23.xmdy-btd

# every queue whose PPD uses our filter
for q in $(lpstat -e 2>/dev/null); do
  if grep -qs "rastertoxmdy" "/etc/cups/ppd/$q.ppd"; then
    lpadmin -x "$q" && echo "Removed queue $q"
  fi
done

# Bluetooth bridge: agent in every user session, plus the old system daemon
for u in $(ps -axo uid= -o comm= | awk '/loginwindow/ {print $1}' | sort -u); do
  launchctl bootout "gui/$u/$LABEL" 2>/dev/null
done
launchctl bootout "system/$LABEL" 2>/dev/null
rm -f "/Library/LaunchAgents/$LABEL.plist" "/Library/LaunchDaemons/$LABEL.plist"

rm -f "/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ.ppd" \
      "/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ Bluetooth.ppd"
rm -rf /Library/Printers/XMDY-A4
pkgutil --forget io.github.timxt23.xmdy-a4rj >/dev/null 2>&1 || true
echo "XMDY A4RJ driver removed."
