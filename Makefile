# XMDY A4RJ CUPS driver for macOS
# SPDX-License-Identifier: MIT

VERSION   = 1.0.0
PKG_ID    = io.github.timxt23.xmdy-a4rj
BUILD     = build
ROOT      = $(BUILD)/root
PKG       = $(BUILD)/XMDY-A4RJ-$(VERSION).pkg

# The Command Line Tools SDK for macOS 27 is not readable by the Xcode linker
# ("unknown architecture arm64e.x1"), so the SDK is taken from Xcode when present.
DEVELOPER_DIR ?= $(shell [ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer || xcode-select -p)
CC      = DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun --sdk macosx clang
CFLAGS  = -O2 -Wall -Wextra -Wno-deprecated-declarations -mmacosx-version-min=11.0 \
          -arch arm64 -arch x86_64 -DXMDY_VERSION=\"$(VERSION)\"
LDLIBS  = -lcups

.PHONY: all test pkg install uninstall clean

all: $(BUILD)/rastertoxmdy

$(BUILD)/rastertoxmdy: src/rastertoxmdy.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ $< $(LDLIBS)

test: $(BUILD)/rastertoxmdy
	tests/run.sh $(BUILD)/rastertoxmdy
	cupstestppd -W filters ppd/xmdy-a4rj.ppd

$(PKG): packaging/build-component.sh $(BUILD)/rastertoxmdy ppd/xmdy-a4rj.ppd scripts/*.sh packaging/distribution.xml packaging/resources/* packaging/scripts/*
	rm -rf $(ROOT) $(BUILD)/res
	install -d $(ROOT)/Library/Printers/XMDY-A4/Filter "$(ROOT)/Library/Printers/PPDs/Contents/Resources"
	install -m 755 $(BUILD)/rastertoxmdy $(ROOT)/Library/Printers/XMDY-A4/Filter/
	install -m 755 scripts/setup-queue.sh scripts/uninstall.sh $(ROOT)/Library/Printers/XMDY-A4/
	install -m 644 ppd/xmdy-a4rj.ppd "$(ROOT)/Library/Printers/PPDs/Contents/Resources/XMDY A4RJ.ppd"
	install -m 644 LICENSE $(ROOT)/Library/Printers/XMDY-A4/LICENSE
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
