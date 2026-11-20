#!/bin/bash
# Builds Stare.app from the SwiftPM executable.
# Usage: Scripts/bundle.sh [debug|release]
#
# Signing: TCC keys a Screen Recording grant to the app's code signature. An
# ad-hoc signature changes on every rebuild, so macOS forgets the grant each time
# and re-prompts. A stable identity keeps it. Override with CODESIGN_IDENTITY.
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

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi

if [ -z "${CODESIGN_IDENTITY:-}" ] || [ "${CODESIGN_IDENTITY}" = "-" ]; then
    echo "warning: no signing identity, using ad-hoc; macOS will forget the Screen Recording grant on every rebuild"
    CODESIGN_IDENTITY="-"
fi

codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
echo "Built $APP signed by: $CODESIGN_IDENTITY"
