#!/usr/bin/env bash
# Regenerates Packaging/homebrew/rightcmd.rb for a release and, optionally, installs it
# into a local tap and audits it there.
#
# Usage: scripts/update-cask.sh <github-owner/repo> [path-to-zip]
#   The zip defaults to build/RightCmd-<version>.zip, where <version> is read from
#   Packaging/Info.plist (what `make dist` produced). The SHA-256 is computed from it.
#
#   TAP=you/tap scripts/update-cask.sh you/RightCmd
#   also copies the cask into the local tap (created with `brew tap-new` if missing) and
#   runs `brew audit --cask --strict` and `brew style` on it by name. Homebrew no longer
#   audits or installs casks given as file paths; they must come from a tap.
#
# Publish the release first (tag <version>, asset RightCmd-<version>.zip): the audit
# downloads the URL to check the checksum. Tags are the bare version by default; set
# TAG_PREFIX=v if you tag as v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${1:?github owner/repo, e.g. zi/RightCmd}"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)"
ZIP="${2:-build/RightCmd-$VERSION.zip}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Packaging/Info.plist)"
TAG_PREFIX="${TAG_PREFIX:-}"
OUT="Packaging/homebrew/rightcmd.rb"

[[ -f "$ZIP" ]] || { echo "error: $ZIP not found; run 'make app' (ad-hoc, for testing) or 'make dist' (Developer ID) first" >&2; exit 1; }
if ! codesign --display --verbose=2 "build/RightCmd.app" 2>&1 | grep -q "Authority=Developer ID"; then
    echo "note: build/RightCmd.app is not Developer ID signed. The cask will work mechanically,"
    echo "      but Gatekeeper blocks unsigned downloads on other Macs unless users install"
    echo "      with 'brew install --cask --no-quarantine …'. Use 'make dist' for a real release."
fi
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat > "$OUT" << CASK
cask "rightcmd" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/${TAG_PREFIX}#{version}/RightCmd-#{version}.zip"
  name "RightCmd"
  desc "Switch apps by holding the right Command key and typing the first letters"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  # macOS 26 (Tahoe) or later; the app is built against that SDK.
  depends_on macos: ">= :tahoe"

  app "RightCmd.app"

  # The app has no built-in updater; upgrades come through this cask.
  auto_updates false

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]

  caveats <<~EOS
    RightCmd needs Accessibility access to see the right ⌘ key and bring apps forward.
    Grant it in System Settings › Privacy & Security › Accessibility on first launch.
  EOS
end
CASK

echo "wrote $OUT (version $VERSION, sha256 $SHA)"

if [[ -n "${TAP:-}" ]]; then
    # TAP is "owner/name"; Homebrew stores it at .../Taps/owner/homebrew-name.
    # Accept both spellings: "zi0r/tap" (Homebrew's tap name) and "zi0r/homebrew-tap" (the
    # repository name). Homebrew's own name drops the "homebrew-" prefix.
    OWNER="${TAP%%/*}"
    NAME="${TAP##*/}"
    NAME="${NAME#homebrew-}"
    TAP="$OWNER/$NAME"
    TAP_DIR="$(brew --repository)/Library/Taps/$OWNER/homebrew-$NAME"
    if [[ ! -d "$TAP_DIR" ]]; then
        echo "==> Creating local tap $TAP"
        brew tap-new "$TAP" --no-git >/dev/null
    fi
    mkdir -p "$TAP_DIR/Casks"
    cp "$OUT" "$TAP_DIR/Casks/rightcmd.rb"
    echo "==> Installed into $TAP_DIR/Casks/rightcmd.rb"
    echo "==> brew audit --cask --strict $TAP/rightcmd"
    brew audit --cask --strict "$TAP/rightcmd"
    echo "==> brew style $TAP"
    brew style "$TAP"
    echo "==> OK. Install locally with: brew install --cask $TAP/rightcmd"
    echo "    Then commit and push $TAP_DIR to github.com/$OWNER/homebrew-$NAME."
else
    echo "next: TAP=you/tap scripts/update-cask.sh $REPO   # copy into a local tap and audit it"
fi
