#!/usr/bin/env bash
# Builds RightCmd in release mode and assembles RightCmd.app in ./build.
#
# Usage:
#   scripts/bundle.sh                      # ad-hoc signed (local use only)
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/bundle.sh
#   UNIVERSAL=1 scripts/bundle.sh          # arm64 + x86_64 slice
#
# Notarization (Developer ID only). Store credentials once with
#   xcrun notarytool store-credentials RightCmd --apple-id you@example.com \
#       --team-id TEAMID --password <app-specific password>
# then
#   CODESIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=RightCmd scripts/bundle.sh
# which submits the app, waits for the verdict, staples the ticket, verifies with Gatekeeper
# and writes build/RightCmd-<version>.zip ready to distribute.
#
# Accessibility permission is bound to the code signature. An ad-hoc signature changes on
# every build, so macOS will drop the permission after each rebuild; use a stable
# identity for anything you intend to keep running.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="RightCmd"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    echo "==> Building universal release binary"
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/$APP_NAME"
else
    echo "==> Building release binary"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

[[ -x "$BIN" ]] || { echo "error: binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
cp Packaging/Info.plist "$CONTENTS/Info.plist"
echo -n "APPL????" > "$CONTENTS/PkgInfo"

if [[ -f "Packaging/AppIcon.icns" ]]; then
    cp Packaging/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"
fi

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Signing with identity: $IDENTITY"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp \
        --entitlements Packaging/RightCmd.entitlements \
        --sign "$IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$IDENTITY" != "-" ]]; then
    # Confirm the hardened runtime and timestamp took: both are notarization prerequisites.
    codesign --display --verbose=2 "$APP_DIR" 2>&1 | grep -q "flags=.*runtime" \
        || { echo "error: hardened runtime not enabled on $APP_DIR" >&2; exit 1; }
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS/Info.plist")"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

# Always produce the versioned zip: it is what the Homebrew cask hashes, and for a
# Developer ID build it is what gets notarized. (Re-created after stapling below.)
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ "$IDENTITY" != "-" ]] || { echo "error: notarization needs a Developer ID identity, not ad-hoc" >&2; exit 1; }
    echo "==> Notarizing with keychain profile '$NOTARY_PROFILE'"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling"
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    # Re-zip so the distributed archive carries the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP"
    echo "==> Gatekeeper assessment"
    spctl --assess --type execute --verbose=2 "$APP_DIR"
    echo "==> Distributable: $ZIP"
elif [[ "$IDENTITY" == "-" ]]; then
    echo "==> Zip (ad-hoc signed, for local testing only): $ZIP"
    echo "    Gatekeeper will refuse this on other Macs; use CODESIGN_IDENTITY and NOTARY_PROFILE to distribute."
else
    echo "==> Zip (signed, not notarized): $ZIP"
fi

echo "==> Done: $APP_DIR"
echo "    Install with: cp -R \"$APP_DIR\" /Applications/"
