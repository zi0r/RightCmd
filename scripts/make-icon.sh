#!/usr/bin/env bash
# Builds a .icns from a single 1024x1024 PNG using the system tools.
# Usage: scripts/make-icon.sh input-1024.png output.icns
set -euo pipefail
IN="${1:?input png}"
OUT="${2:?output icns}"
TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$TMP"
for size in 16 32 128 256 512; do
    sips -z $size $size "$IN" --out "$TMP/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$IN" --out "$TMP/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$TMP" -o "$OUT"
echo "wrote $OUT"
