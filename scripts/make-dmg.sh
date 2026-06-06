#!/usr/bin/env bash
# Build a distributable .dmg: the app plus an /Applications shortcut, laid out
# for the familiar drag-to-install window. Depends only on the system's
# hdiutil and (optionally) Finder via AppleScript for the icon layout.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Mac Cleanup"
VOL_NAME="Mac Cleanup"
APP_DIR="build/${APP_NAME}.app"
DMG_OUT="build/MacCleanup.dmg"
STAGE="build/dmg-staging"
TMP_DMG="build/dmg-tmp.dmg"

# 1. Build (and ad-hoc sign) the release .app.
bash scripts/bundle.sh

# 2. Stage the contents: the app + a symlink to /Applications.
rm -rf "$STAGE" "$DMG_OUT" "$TMP_DMG"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Bundle the icon as the volume icon too.
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
fi

# 3. Create a writable image sized to fit, so we can arrange the window.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))
echo "▸ Creating ${SIZE_MB}MB writable image…"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" -ov "$TMP_DMG" >/dev/null

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" \
    | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOL_NAME"
echo "▸ Mounted at $MOUNT ($DEVICE)"

# Mark the volume icon as custom (best-effort).
if [ -f "$MOUNT/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT" 2>/dev/null || true
fi

# 4. Arrange the Finder window (best-effort; DMG is still valid if this fails,
#    e.g. when automation permission isn't granted in a headless run).
echo "▸ Arranging window layout…"
osascript <<EOT 2>/dev/null || echo "  (skipped layout — Finder automation unavailable)"
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 720, 480}
        set vo to the icon view options of container window
        set arrangement of vo to not arranged
        set icon size of vo to 112
        set position of item "${APP_NAME}.app" of container window to {140, 170}
        set position of item "Applications" of container window to {380, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOT

sync
hdiutil detach "$DEVICE" >/dev/null || hdiutil detach "$DEVICE" -force >/dev/null

# 5. Convert to a compressed, read-only DMG for distribution.
echo "▸ Compressing…"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" -ov >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGE"

SIZE=$(du -h "$DMG_OUT" | cut -f1)
echo "✓ Created $DMG_OUT ($SIZE)"
echo "  Note: ad-hoc signed. Recipients open via right-click → Open the first"
echo "  time (or remove quarantine: xattr -dr com.apple.quarantine \"$DMG_OUT\")."
