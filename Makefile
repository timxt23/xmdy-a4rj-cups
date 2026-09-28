# XMDY A4RJ CUPS driver for macOS
# SPDX-License-Identifier: MIT

VERSION   = 1.1.0
PKG_ID    = io.github.timxt23.xmdy-a4rj
DAEMON    = io.github.timxt23.xmdy-btd
BUILD     = build
ROOT      = $(BUILD)/root
PKG       = $(BUILD)/XMDY-A4RJ-$(VERSION).pkg
PPD_USB   = $(BUILD)/XMDY A4RJ.ppd
PPD_BT    = $(BUILD)/XMDY A4RJ Bluetooth.ppd
DEST      = $(ROOT)/Library/Printers/XMDY-A4
PPD_DEST  = $(ROOT)/Library/Printers/PPDs/Contents/Resources

# The Command Line Tools SDK for macOS 27 is not readable by the Xcode linker
# ("unknown architecture arm64e.x1"), so the SDK is taken from Xcode when present.
DEVELOPER_DIR ?= $(shell [ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer || xcode-select -p)
CC      = DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun --sdk macosx clang
CFLAGS  = -O2 -Wall -Wextra -Wno-deprecated-declarations -mmacosx-version-min=11.0 \
          -arch arm64 -arch x86_64 -DXMDY_VERSION=\"$(VERSION)\"

APP  = $(BUILD)/XMDY Bluetooth.app
BINS = $(BUILD)/rastertoxmdy $(BUILD)/xmdy-btd $(BUILD)/xmdy-btpair

.PHONY: all app ppds test pkg install uninstall clean

all: $(BINS) app ppds

# The Bluetooth bridge runs as an app bundle so macOS can grant it Bluetooth
# access (TCC). Ad-hoc signed: the permission is asked again after an update.
app: $(BUILD)/xmdy-btd packaging/app/Info.plist
	rm -rf "$(APP)"
	install -d "$(APP)/Contents/MacOS"
	sed 's/@VERSION@/$(VERSION)/g' packaging/app/Info.plist > "$(APP)/Contents/Info.plist"
	install -m 755 $(BUILD)/xmdy-btd "$(APP)/Contents/MacOS/xmdy-btd"
	codesign --force --sign - "$(APP)"

$(BUILD)/rastertoxmdy: src/rastertoxmdy.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ $< -lcups -lz

$(BUILD)/xmdy-btd: src/xmdy-btd.m
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -o $@ $< -framework Foundation -framework IOBluetooth

$(BUILD)/xmdy-btpair: src/xmdy-btpair.m
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -o $@ $< -framework Foundation -framework IOBluetooth

# USB PPD: version stamped. Bluetooth PPD: same options, other name, no 1284 ID
# (so macOS keeps choosing the USB driver for USB), transport attribute.
ppds: ppd/xmdy-a4rj.ppd
	@mkdir -p $(BUILD)
	sed 's/@VERSION@/$(VERSION)/g' ppd/xmdy-a4rj.ppd > "$(PPD_USB)"
	sed -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/^\*PCFileName: .*/*PCFileName: "XMDYA4BT.PPD"/' \
	    -e 's/^\*ModelName: .*/*ModelName: "XMDY A4RJ Bluetooth"/' \
	    -e 's/^\*ShortNickName: .*/*ShortNickName: "XMDY A4RJ BT"/' \
	    -e 's/^\*NickName: "XMDY A4RJ Thermal,/*NickName: "XMDY A4RJ Bluetooth,/' \
	    -e '/^\*1284DeviceID:/d' ppd/xmdy-a4rj.ppd | \
	awk '{ print } /^\*cupsFilter2: / { print "*XmdyTransport: \"Bluetooth\"" }' > "$(PPD_BT)"

test: all
	tests/run.sh $(BUILD)/rastertoxmdy "$(PPD_USB)" "$(PPD_BT)"
	cupstestppd -W filters "$(PPD_USB)" "$(PPD_BT)"

$(PKG): all packaging/build-component.sh scripts/*.sh packaging/*.plist packaging/distribution.xml packaging/resources/* packaging/scripts/*
	rm -rf $(ROOT) $(BUILD)/res
	install -d $(DEST)/Filter "$(PPD_DEST)" $(ROOT)/Library/LaunchAgents
	install -m 755 $(BUILD)/rastertoxmdy $(DEST)/Filter/
	install -m 755 $(BUILD)/xmdy-btpair $(DEST)/
	ditto --norsrc --noextattr "$(APP)" "$(DEST)/XMDY Bluetooth.app"
	install -m 755 scripts/setup-queue.sh scripts/uninstall.sh $(DEST)/
	install -m 644 "$(PPD_USB)" "$(PPD_BT)" "$(PPD_DEST)/"
	install -m 644 packaging/$(DAEMON).plist $(ROOT)/Library/LaunchAgents/
	install -m 644 LICENSE $(DEST)/LICENSE
	packaging/build-component.sh $(ROOT) packaging/scripts $(PKG_ID) $(VERSION) $(BUILD)/xmdy-a4rj-core.pkg
	mkdir -p $(BUILD)/res
	sed 's/@VERSION@/$(VERSION)/g' packaging/resources/welcome.html > $(BUILD)/res/welcome.html
	cp LICENSE $(BUILD)/res/LICENSE.txt
	sed 's/@VERSION@/$(VERSION)/g' packaging/distribution.xml > $(BUILD)/distribution.xml
	productbuild --distribution $(BUILD)/distribution.xml --resources $(BUILD)/res \
	             --package-path $(BUILD) $@
	@shasum -a 256 $@

pkg: $(PKG)

install: $(PKG)
	sudo installer -pkg $(PKG) -target /

uninstall:
	sudo /Library/Printers/XMDY-A4/uninstall.sh

clean:
	rm -rf $(BUILD)
