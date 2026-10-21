#!/usr/bin/env bash
set -e

# ==============================================================================
# dynaQ Production Release & Complete All-In-One Installer Packaging Script
# Generates:
#   1. dist/dynaQ.app (Self-contained, double-clickable macOS Application)
#   2. dist/dynaQ-1.0.0-beta.1.dmg (Minimal Drag-and-Drop DMG)
#   3. dist/dynaQ-1.0.0-beta.1-complete.pkg (Native macOS All-In-One Installer)
#   4. dist/dynaQ-1.0.0-beta.1-all-in-one.dmg (Complete DMG with PKG, App & Tools)
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_VERSION="1.0.0-beta.1"
BUNDLE_ID="com.dynaq.audio"
DIST_DIR="$REPO_ROOT/dist"
OUTPUT_DIR="$REPO_ROOT/output"
APP_BUNDLE="$DIST_DIR/dynaQ.app"
DRIVER_BUNDLE="$DIST_DIR/DynaQDriver.driver"

DMG_MINIMAL="dynaQ-${APP_VERSION}.dmg"
DMG_ALL_IN_ONE="dynaQ-${APP_VERSION}-all-in-one.dmg"
PKG_COMPLETE="dynaQ-${APP_VERSION}-complete.pkg"

echo "======================================================================"
echo "  DYNAQ PRODUCTION RELEASE & ALL-IN-ONE INSTALLER BUILD"
echo "  Version: v${APP_VERSION}"
echo "======================================================================"

mkdir -p "$DIST_DIR"
mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# 1. Compile in Release Mode
# ------------------------------------------------------------------------------
echo "\n[1/8] Compiling production release binaries (SwiftPM)..."
swift build -c release

# ------------------------------------------------------------------------------
# 2. Generate Native Multi-Resolution Retina AppIcon.icns
# ------------------------------------------------------------------------------
echo "\n[2/8] Generating native AppIcon.icns..."
swift scripts/generate_icon.swift

# ------------------------------------------------------------------------------
# 3. Build Universal CoreAudio HAL Virtual Driver Bundle
# ------------------------------------------------------------------------------
echo "\n[3/8] Compiling universal CoreAudio HAL Driver (arm64 + x86_64)..."
rm -rf "$DRIVER_BUNDLE"
mkdir -p "$DRIVER_BUNDLE/Contents/MacOS"
mkdir -p "$DRIVER_BUNDLE/Contents/Resources"

clang -bundle -O3 \
    -arch arm64 -arch x86_64 \
    -framework CoreAudio \
    -framework CoreFoundation \
    Driver/AudioServerPlugin/DynaQDriver.c \
    -o "$DRIVER_BUNDLE/Contents/MacOS/DynaQDriver"

cp Driver/AudioServerPlugin/Info.plist "$DRIVER_BUNDLE/Contents/Info.plist"
echo -n "BNDL????" > "$DRIVER_BUNDLE/Contents/PkgInfo"

codesign --force --deep --sign - "$DRIVER_BUNDLE"
echo "  ✓ DynaQDriver.driver compiled and signed."

# ------------------------------------------------------------------------------
# 4. Build Standalone C DSP Benchmark & Diagnostic Utility
# ------------------------------------------------------------------------------
echo "\n[4/8] Compiling native DSP benchmark CLI utility..."
clang -O3 \
    docker/cli_main.c \
    Sources/CDspKernel/CDspKernel.c \
    -I Sources/CDspKernel/include \
    -framework Accelerate \
    -o "$DIST_DIR/dynaq-cli"

chmod +x "$DIST_DIR/dynaq-cli"
codesign --force --sign - "$DIST_DIR/dynaq-cli"

# ------------------------------------------------------------------------------
# 5. Assemble Self-Contained dynaQ.app Bundle
# ------------------------------------------------------------------------------
echo "\n[5/8] Assembling self-contained dynaQ.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"
mkdir -p "$APP_BUNDLE/Contents/Resources/driver"

# Executables
cp ".build/release/dynaQ" "$APP_BUNDLE/Contents/MacOS/dynaQ"
cp ".build/release/dynaQ-router" "$APP_BUNDLE/Contents/Helpers/dynaQ-router"
cp "$DIST_DIR/dynaq-cli" "$APP_BUNDLE/Contents/Helpers/dynaq-cli"
chmod +x "$APP_BUNDLE/Contents/MacOS/dynaQ"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaQ-router"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaq-cli"

# Icon
cp "$DIST_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Bundled HAL Driver
cp -R "$DRIVER_BUNDLE" "$APP_BUNDLE/Contents/Resources/driver/DynaQDriver.driver"

# Bundled Offline Documentation
cp -R "$REPO_ROOT/docs" "$APP_BUNDLE/Contents/Resources/docs"

# Bundled LaunchAgent Plist
cat <<EOF > "$APP_BUNDLE/Contents/Resources/com.dynaq.router.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dynaq.router</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/dynaq-router</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/dynaq-router.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/dynaq-router.err.log</string>
</dict>
</plist>
EOF

# Info.plist
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

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Codesign .app Bundle
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "  ✓ Self-contained application bundle signed and verified."

# ------------------------------------------------------------------------------
# 6. Build Native macOS All-In-One Package (.pkg)
# ------------------------------------------------------------------------------
echo "\n[6/8] Building native macOS All-In-One Installer Package (${PKG_COMPLETE})..."
PKG_ROOT="$DIST_DIR/pkg_root"
PKG_SCRIPTS="$DIST_DIR/pkg_scripts"
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_ROOT/Library/Audio/Plug-Ins/HAL"
mkdir -p "$PKG_ROOT/Library/LaunchAgents"
mkdir -p "$PKG_SCRIPTS"

# 1. Install app bundle to /Applications
cp -R "$APP_BUNDLE" "$PKG_ROOT/Applications/"

# 2. Install pre-compiled CLI tools to /usr/local/bin
cp ".build/release/dynaQ" "$PKG_ROOT/usr/local/bin/dynaq"
cp ".build/release/dynaQ-router" "$PKG_ROOT/usr/local/bin/dynaq-router"
chmod +x "$PKG_ROOT/usr/local/bin/dynaq"
chmod +x "$PKG_ROOT/usr/local/bin/dynaq-router"

# 3. Install HAL Virtual Audio Driver to /Library/Audio/Plug-Ins/HAL
cp -R "$DRIVER_BUNDLE" "$PKG_ROOT/Library/Audio/Plug-Ins/HAL/"

# 4. Install LaunchAgent for background service
cp "$APP_BUNDLE/Contents/Resources/com.dynaq.router.plist" "$PKG_ROOT/Library/LaunchAgents/"

# 5. Create postinstall script
cat <<'POSTINSTALL_EOF' > "$PKG_SCRIPTS/postinstall"
#!/bin/bash
set -e

# Set file permissions
chmod -R 755 /Applications/dynaQ.app 2>/dev/null || true
chmod +x /usr/local/bin/dynaq 2>/dev/null || true
chmod +x /usr/local/bin/dynaq-router 2>/dev/null || true

# Configure HAL audio driver
if [ -d "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver" ]; then
    chown -R root:wheel /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver 2>/dev/null || true
    chmod -R 755 /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver 2>/dev/null || true
    # Restart CoreAudio daemon so the driver is recognized immediately
    killall coreaudiod 2>/dev/null || true
fi

exit 0
POSTINSTALL_EOF
chmod +x "$PKG_SCRIPTS/postinstall"

# Build Package
pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$PKG_SCRIPTS" \
    --identifier "com.dynaq.audio.pkg.complete" \
    --version "${APP_VERSION}" \
    --install-location "/" \
    "$DIST_DIR/$PKG_COMPLETE"

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS"
echo "  ✓ Native installer package generated: $DIST_DIR/$PKG_COMPLETE"

# ------------------------------------------------------------------------------
# 7. Build Minimal Drag-and-Drop DMG
# ------------------------------------------------------------------------------
echo "\n[7/8] Creating minimal drag-and-drop installer DMG (${DMG_MINIMAL})..."
MINIMAL_STAGING="$DIST_DIR/minimal_staging"
rm -rf "$MINIMAL_STAGING" "$DIST_DIR/$DMG_MINIMAL"
mkdir -p "$MINIMAL_STAGING"

cp -R "$APP_BUNDLE" "$MINIMAL_STAGING/"
ln -s /Applications "$MINIMAL_STAGING/Applications"

hdiutil create \
    -volname "dynaQ" \
    -srcfolder "$MINIMAL_STAGING" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_MINIMAL"

rm -rf "$MINIMAL_STAGING"
echo "  ✓ Minimal drag-and-drop DMG created: $DIST_DIR/$DMG_MINIMAL"

# ------------------------------------------------------------------------------
# 8. Build Complete All-In-One Disk Image (DMG)
# ------------------------------------------------------------------------------
echo "\n[8/8] Creating comprehensive All-In-One disk image (${DMG_ALL_IN_ONE})..."
ALL_IN_ONE_STAGING="$DIST_DIR/all_in_one_staging"
rm -rf "$ALL_IN_ONE_STAGING" "$DIST_DIR/$DMG_ALL_IN_ONE"
mkdir -p "$ALL_IN_ONE_STAGING"

# 1. Native Installer Package (.pkg)
cp "$DIST_DIR/$PKG_COMPLETE" "$ALL_IN_ONE_STAGING/Install dynaQ Complete.pkg"

# 2. Standalone Application Bundle
cp -R "$APP_BUNDLE" "$ALL_IN_ONE_STAGING/dynaQ.app"

# 3. Applications Symlink
ln -s /Applications "$ALL_IN_ONE_STAGING/Applications"

# 4. Uninstaller Command Script
cat <<'UNINSTALL_EOF' > "$ALL_IN_ONE_STAGING/Uninstall dynaQ.command"
#!/bin/bash
clear
echo "=================================================="
echo "  DYNAQ UNINSTALLATION WIZARD"
echo "=================================================="
echo "This script will remove:"
echo "  • /Applications/dynaQ.app"
echo "  • /usr/local/bin/dynaq"
echo "  • /usr/local/bin/dynaq-router"
echo "  • /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver"
echo "  • /Library/LaunchAgents/com.dynaq.router.plist"
echo "=================================================="
read -p "Are you sure you want to uninstall dynaQ? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "\nRemoving application and CLI binaries (requires sudo)..."
    sudo rm -rf /Applications/dynaQ.app
    sudo rm -f /usr/local/bin/dynaq
    sudo rm -f /usr/local/bin/dynaq-router
    sudo rm -rf /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver
    sudo rm -f /Library/LaunchAgents/com.dynaq.router.plist
    echo "Restarting coreaudiod daemon..."
    sudo killall coreaudiod 2>/dev/null || true
    echo "\n// [SUCCESS] dynaQ has been completely removed from this system."
else
    echo "\nUninstallation aborted."
fi
exit 0
UNINSTALL_EOF
chmod +x "$ALL_IN_ONE_STAGING/Uninstall dynaQ.command"

# 5. Monospace Instructions
cat <<EOF > "$ALL_IN_ONE_STAGING/README.txt"
================================================================================
  DYNAQ PROFESSIONAL AUDIO MANAGEMENT SUITE — v${APP_VERSION}
================================================================================

INSTALLATION OPTIONS:

1. ALL-IN-ONE AUTOMATED INSTALLER (RECOMMENDED):
   Double-click "Install dynaQ Complete.pkg".
   This automatically installs:
     - dynaQ.app into /Applications
     - dynaq & dynaq-router CLI commands into /usr/local/bin
     - CoreAudio Virtual Audio HAL Driver into /Library/Audio/Plug-Ins/HAL
     - Restarts CoreAudio automatically (no system reboot needed)

2. DRAG-AND-DROP INSTALLATION:
   Drag "dynaQ.app" directly into the "Applications" shortcut.

3. UNINSTALLATION:
   Double-click "Uninstall dynaQ.command" to cleanly remove all components.

DOCUMENTATION:
   Built-in offline documentation is located inside dynaQ.app:
   /Applications/dynaQ.app/Contents/Resources/docs/index.html
================================================================================
EOF

hdiutil create \
    -volname "dynaQ Complete Setup" \
    -srcfolder "$ALL_IN_ONE_STAGING" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_ALL_IN_ONE"

rm -rf "$ALL_IN_ONE_STAGING"
echo "  ✓ All-In-One disk image created: $DIST_DIR/$DMG_ALL_IN_ONE"

# ------------------------------------------------------------------------------
# Copy All Final Artifacts to Untracked output/ Folder
# ------------------------------------------------------------------------------
echo "\nPopulating output/ distribution folder..."
cp "$DIST_DIR/$DMG_MINIMAL" "$OUTPUT_DIR/"
cp "$DIST_DIR/$DMG_ALL_IN_ONE" "$OUTPUT_DIR/"
cp "$DIST_DIR/$PKG_COMPLETE" "$OUTPUT_DIR/"
cp "$DIST_DIR/AppIcon.icns" "$OUTPUT_DIR/"
cp -R "$APP_BUNDLE" "$OUTPUT_DIR/"
cp -R "$DRIVER_BUNDLE" "$OUTPUT_DIR/"
cp ".build/release/dynaQ-router" "$OUTPUT_DIR/"

# Compute and update SHA256SUMS
cd "$OUTPUT_DIR"
shasum -a 256 "$DMG_MINIMAL" "$DMG_ALL_IN_ONE" "$PKG_COMPLETE" "dynaQ-router" > SHA256SUMS.txt
cd "$REPO_ROOT"

echo "\n======================================================================"
echo "  ✓ ALL PACKAGES CREATED SUCCESSFULLY IN output/"
echo "======================================================================"
ls -lh "$OUTPUT_DIR"
echo "======================================================================"
