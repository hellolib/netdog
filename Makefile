APP_NAME  := NetDog
BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
BIN       := $(APP)/Contents/MacOS/$(APP_NAME)
SOURCES   := $(shell find Sources -name '*.swift' | sort)
ARCH      ?= $(shell uname -m)
TARGET    ?= $(ARCH)-apple-macos13.0
VERSION   := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
ZIP       := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip

SWIFTC     := xcrun swiftc
SWIFTFLAGS := -swift-version 5 -O -target $(TARGET)
CODESIGN   := codesign --force --sign - --identifier com.liusaisai.netdog

.PHONY: all app run check dist install clean

all: app

app: $(BIN)

$(BIN): $(SOURCES) Info.plist Makefile
	@mkdir -p $(APP)/Contents/MacOS
	@cp Info.plist $(APP)/Contents/Info.plist
	$(SWIFTC) $(SWIFTFLAGS) -o $(BIN) $(SOURCES)
	$(CODESIGN) $(APP)
	@echo "==> $(APP)"

run: app
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	@open $(APP)

check: app
	@bash scripts/selfcheck.sh

dist: app
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "==> $(ZIP)"

install: app
	@test -w /Applications || { echo "/Applications is not writable"; exit 1; }
	@rm -rf /Applications/$(APP_NAME).app
	ditto $(APP) /Applications/$(APP_NAME).app
	@echo "==> /Applications/$(APP_NAME).app (ad-hoc signed, re-run after rebuild)"

clean:
	rm -rf $(BUILD_DIR) .build
