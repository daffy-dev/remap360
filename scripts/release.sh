#!/usr/bin/env bash
# Builds a signed, notarized, universal Remap360 DMG in build/release/.
# Usage: scripts/release.sh
# Env:   DEVELOPER_ID    signing identity (default: first "Developer ID Application" in the keychain)
#        NOTARY_PROFILE  notarytool keychain profile (default: pixnip-notary, shared by the team)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
DEVELOPER_ID=${DEVELOPER_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}
NOTARY_PROFILE=${NOTARY_PROFILE:-pixnip-notary}
[ -n "$DEVELOPER_ID" ] || { echo "No Developer ID Application certificate found" >&2; exit 1; }

VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' scripts/bundle.sh)
OUT="$ROOT/build/release"
APP="$ROOT/build/Remap360.app"
DMG="$OUT/Remap360-$VERSION.dmg"

echo "▸ Building universal app signed by $DEVELOPER_ID"
SIGN_IDENTITY="$DEVELOPER_ID" UNIVERSAL=1 scripts/bundle.sh
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/Remap360"

echo "▸ Creating DMG"
rm -rf "$OUT" && mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
mkdir "$OUT/dmg/.background"
tiffutil -cathidpicheck "$ROOT/build/brand/dmg-background.png" "$ROOT/build/brand/dmg-background@2x.png" \
    -out "$OUT/dmg/.background/background.tiff" >/dev/null
cp "$ROOT/build/AppIcon.icns" "$OUT/dmg/.VolumeIcon.icns"

# Lay out the window with Finder on a writable image, then compress it.
VOL="Remap360"
[ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -force -quiet || true
hdiutil create -srcfolder "$OUT/dmg" -volname "$VOL" -fs HFS+ -format UDRW -ov "$OUT/rw.dmg" >/dev/null
hdiutil attach "$OUT/rw.dmg" -readwrite -noverify -noautoopen -quiet
xcrun SetFile -a C "/Volumes/$VOL"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set bounds of container window to {200, 120, 860, 548}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 120
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Remap360.app" of container window to {170, 205}
        set position of item "Applications" of container window to {490, 205}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
sync
hdiutil detach "/Volumes/$VOL" -quiet
hdiutil convert "$OUT/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$OUT/dmg" "$OUT/rw.dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "▸ Notarizing with Apple (takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Verifying"
spctl -a -t open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "✓ $DMG"
