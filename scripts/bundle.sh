#!/usr/bin/env bash
# Build MacCleanup in release mode and wrap the SPM executable into a proper
# .app bundle so it launches from Finder and can be granted Full Disk Access.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Mac Cleanup"
BUNDLE_ID="local.maccleanup"
EXECUTABLE="MacCleanup"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "▸ Building release…"
swift build -c release --product "$EXECUTABLE"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
sed -e "s/__EXECUTABLE__/$EXECUTABLE/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    scripts/Info.plist.template > "$APP_DIR/Contents/Info.plist"

# App icon (generate with: swift scripts/make-icon.swift && iconutil -c icns …)
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS lets the app keep its Full Disk Access grant across
# rebuilds. (No paid Developer ID needed for personal use.)
echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Built $APP_DIR"
echo "  Open with:  open \"$APP_DIR\""
echo "  Then grant Full Disk Access in System Settings → Privacy & Security."
