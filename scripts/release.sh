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
hdiutil create -volname "Remap360 $VERSION" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$OUT/dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "▸ Notarizing with Apple (takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Verifying"
spctl -a -t open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "✓ $DMG"
