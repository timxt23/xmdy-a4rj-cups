#!/bin/sh
# Build a flat component package without AppleDouble (._*) entries.
# pkgbuild turns extended attributes such as com.apple.provenance (which
# cannot be removed) into ._ files; ditto --noextattr does not.
# Usage: build-component.sh <root> <scripts> <identifier> <version> <out.pkg>
# SPDX-License-Identifier: MIT
set -e
ROOT="$1"; SCRIPTS="$2"; ID="$3"; VERSION="$4"; OUT="$5"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"; mkdir -p "$PKG"

(cd "$ROOT" && find . | LC_ALL=C sort | cpio -o --quiet --format odc -R 0:0) | gzip -9 > "$PKG/Payload"
# pkgutil --flatten archives the Scripts directory itself
mkdir "$PKG/Scripts" && cp "$SCRIPTS"/* "$PKG/Scripts/"
# BOM with root:wheel ownership (mkbom has no owner flags: rewrite the file list)
mkbom "$ROOT" "$WORK/tmp.bom"
lsbom "$WORK/tmp.bom" | awk 'BEGIN{FS=OFS="\t"} {$3="0/0"; print}' > "$WORK/files.txt"
mkbom -i "$WORK/files.txt" "$PKG/Bom"

FILES=$(find "$ROOT" | wc -l | tr -d ' ')
KB=$(du -sk "$ROOT" | cut -f1)
cat > "$PKG/PackageInfo" <<XML
<?xml version="1.0" encoding="utf-8"?>
<pkg-info format-version="2" identifier="$ID" version="$VERSION" install-location="/" auth="root" relocatable="false" overwrite-permissions="true">
    <payload numberOfFiles="$FILES" installKBytes="$KB"/>
    <scripts>
        <postinstall file="./postinstall"/>
    </scripts>
</pkg-info>
XML
rm -f "$OUT"
pkgutil --flatten "$PKG" "$OUT"
