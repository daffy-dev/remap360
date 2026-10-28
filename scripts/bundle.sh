#!/usr/bin/env bash
# Builds Remap360 in release mode and wraps it into build/Remap360.app.
# Usage: scripts/bundle.sh [--install]   (--install copies the app to /Applications)
# Env:   SIGN_IDENTITY="Developer ID Application: …"  sign for distribution (hardened runtime)
#        UNIVERSAL=1                                  build for Apple Silicon and Intel
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
VERSION="${VERSION:-1.0.1}"
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP="$ROOT/build/Remap360.app"

ARCHS=()
if [ "${UNIVERSAL:-0}" = 1 ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN=$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Remap360

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Remap360"

# Icon + logo assets are rendered from Sources/Remap360/Views/Brand.swift.
swiftc -parse-as-library -O -o "$ROOT/build/make-icon" "$ROOT/scripts/make-icon.swift" "$ROOT/Sources/Remap360/Views/Brand.swift"
"$ROOT/build/make-icon" "$ROOT/build/brand"
iconutil -c icns "$ROOT/build/brand/AppIcon.iconset" -o "$ROOT/build/AppIcon.icns"
mkdir -p "$ROOT/assets"
cp "$ROOT/build/brand/"{app-icon,logo-mark,wordmark-dark,wordmark-light}.png "$ROOT/assets/"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Remap360</string>
    <key>CFBundleDisplayName</key><string>Remap360</string>
    <key>CFBundleIdentifier</key><string>dev.daffy.remap360</string>
    <key>CFBundleExecutable</key><string>Remap360</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 daffy-dev · MIT License</string>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/Remap360.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Remap360.app"
fi
