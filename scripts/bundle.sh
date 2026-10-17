#!/usr/bin/env bash
# Builds RightCmd in release mode and assembles RightCmd.app in ./build.
#
# Usage:
#   scripts/bundle.sh                      # ad-hoc signed (local use only)
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/bundle.sh
#   UNIVERSAL=1 scripts/bundle.sh          # arm64 + x86_64 slice
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
codesign --verify --verbose=2 "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Install with: cp -R \"$APP_DIR\" /Applications/"
