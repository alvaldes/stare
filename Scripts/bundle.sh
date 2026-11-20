#!/bin/bash
# Builds Stare.app from the SwiftPM executable.
# Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Stare.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Stare"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stare"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for local runs. Developer ID + notarization come later.
codesign --force --sign - "$APP"

echo "Built $APP"
