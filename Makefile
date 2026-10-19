APP      := RightCmd
BUILD    := build
APP_PATH := $(BUILD)/$(APP).app

.PHONY: all build test test-verbose run app dist cask formula install uninstall clean xcodeproj icon

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

## Developer ID build, notarized and stapled, as build/RightCmd-<version>.zip
## Requires CODESIGN_IDENTITY and NOTARY_PROFILE in the environment (see scripts/bundle.sh)
dist:
	@[ -n "$$CODESIGN_IDENTITY" ] || { echo "CODESIGN_IDENTITY is not set"; exit 1; }
	@[ -n "$$NOTARY_PROFILE" ] || { echo "NOTARY_PROFILE is not set"; exit 1; }
	UNIVERSAL=1 scripts/bundle.sh

## Regenerate the Homebrew cask from the zip `make dist` produced (REPO=owner/repo).
## With TAP=you/tap it is also copied into that local tap and audited there.
cask:
	@[ -n "$$REPO" ] || { echo "REPO is not set (e.g. make cask REPO=you/RightCmd TAP=you/tap)"; exit 1; }
	scripts/update-cask.sh "$$REPO"

## Regenerate the Homebrew formula (build-from-source) for the tagged release (REPO=owner/repo).
## With TAP=you/tap it is also copied into that local tap and audited there.
formula:
	@[ -n "$$REPO" ] || { echo "REPO is not set (e.g. make formula REPO=you/RightCmd TAP=you/tap)"; exit 1; }
	scripts/update-formula.sh "$$REPO"

## Rebuild Packaging/AppIcon.icns from Packaging/AppIcon-1024.png (macOS only)
icon:
	scripts/make-icon.sh Packaging/AppIcon-1024.png Packaging/AppIcon.icns

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
