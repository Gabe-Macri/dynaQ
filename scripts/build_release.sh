#!/usr/bin/env bash
set -e

# ==============================================================================
# dynaQ Production Release & Installer Packaging Script
# Generates:
#   1. dist/dynaQ.app (Self-contained, double-clickable macOS Application)
#   2. dist/dynaQ-1.0.0-beta.1.dmg (Drag-and-Drop /Applications Installer)
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_VERSION="1.0.0-beta.1"
BUNDLE_ID="com.dynaq.audio"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/dynaQ.app"
DMG_NAME="dynaQ-${APP_VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg_staging"

echo "======================================================================"
echo "  DYNAQ PRODUCTION RELEASE BUILD — v${APP_VERSION}"
echo "======================================================================"

mkdir -p "$DIST_DIR"

# 1. Compile in Release Mode
echo "\n[1/5] Compiling production release binaries..."
swift build -c release

# 2. Generate Native Multi-Resolution Retina AppIcon.icns
echo "\n[2/5] Generating native AppIcon.icns..."
swift scripts/generate_icon.swift

# 3. Assemble .app Bundle
echo "\n[3/5] Assembling dynaQ.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

# Copy main executable and standalone router
cp ".build/release/dynaQ" "$APP_BUNDLE/Contents/MacOS/dynaQ"
cp ".build/release/dynaQ-router" "$APP_BUNDLE/Contents/Helpers/dynaQ-router"
chmod +x "$APP_BUNDLE/Contents/MacOS/dynaQ"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaQ-router"

# Copy Icon
cp "$DIST_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Write Info.plist
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>dynaQ</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>dynaQ</string>
    <key>CFBundleDisplayName</key>
    <string>dynaQ</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>dynaQ requires audio access to monitor and equalize system and hardware audio streams.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
</dict>
</plist>
EOF

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 4. Ad-hoc Codesign .app
echo "\n[4/5] Code signing application bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "  ✓ Code signature verified."

# 5. Create Drag-and-Drop Installer DMG
echo "\n[5/5] Creating drag-and-drop installer disk image (${DMG_NAME})..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

# Copy .app and create /Applications symlink
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Build compressed DMG
hdiutil create \
    -volname "dynaQ Installer" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "\n======================================================================"
echo "  ✓ PRODUCTION BUILD & INSTALLER COMPLETE!"
echo "======================================================================"
echo "  Application Bundle : $APP_BUNDLE"
echo "  Disk Image (DMG)   : $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo "======================================================================"

