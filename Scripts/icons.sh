#!/bin/bash
# Regenerates the binary icon assets from the SVG artwork in Resources/.
# Usage: Scripts/icons.sh
#
# The logo lives in version control as SVG, so a change to the artwork is a
# change you can review in a diff, and the .icns and .pdf are build products
# regenerated from it instead of hand-drawn blobs nobody can edit later.
# Requires rsvg-convert (brew install librsvg) and iconutil (macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
    echo "error: rsvg-convert not found (brew install librsvg)" >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# The sizes iconutil expects. Missing one of them makes iconutil refuse the set.
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" Resources/app-icon.svg \
        -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" Resources/app-icon.svg \
        -o "$ICONSET/icon_${size}x${size}@2x.png"
done

# Only the app icon comes from the artwork: the menu bar glyph is a path in
# StatusBarController, because librsvg's PDF export drops the mask that carves
# the nib's hole and slit, and AppKit then draws nothing.
iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"

echo "Generated Resources/AppIcon.icns"
