APP      := RightCmd
BUILD    := build
APP_PATH := $(BUILD)/$(APP).app

.PHONY: all build test test-verbose run app install uninstall clean xcodeproj

all: app

## Debug build of the bare executable
build:
	swift build

## Run the unit tests for the core logic
test:
	swift test

test-verbose:
	swift test --verbose

## Run from the command line (no bundle; launch-at-login unavailable)
run:
	swift run $(APP)

## Build the release .app bundle into ./build (set CODESIGN_IDENTITY to sign properly)
app:
	scripts/bundle.sh

## Copy the bundle into /Applications
install: app
	-pkill -x $(APP) 2>/dev/null || true
	rm -rf "/Applications/$(APP).app"
	cp -R "$(APP_PATH)" /Applications/
	@echo "Installed /Applications/$(APP).app — launch it from Finder or: open /Applications/$(APP).app"

uninstall:
	rm -rf "/Applications/$(APP).app"

## Generate RightCmd.xcodeproj with XcodeGen (brew install xcodegen)
xcodeproj:
	xcodegen generate

clean:
	rm -rf .build $(BUILD) $(APP).xcodeproj
