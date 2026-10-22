#!/usr/bin/env bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_VERSION="1.0.0-beta.2"
BUNDLE_ID="com.dynaq.audio"
DIST_DIR="$REPO_ROOT/dist"
OUTPUT_DIR="$REPO_ROOT/output"
APP_BUNDLE="$DIST_DIR/dynaQ.app"
DRIVER_BUNDLE="$DIST_DIR/DynaQDriver.driver"

INSTALLER_DMG="dynaQ-Installer.dmg"
INSTALLER_PKG="dynaQ-Installer.pkg"

echo "======================================================================"
echo "  DYNAQ PRODUCTION RELEASE & ALL-IN-ONE INSTALLER BUILD"
echo "  Version: v${APP_VERSION}"
echo "======================================================================"

mkdir -p "$DIST_DIR"
mkdir -p "$OUTPUT_DIR"

# 
# 1. Compile in Release Mode
# 
echo "\n[1/8] Compiling production release binaries (SwiftPM)..."
swift build -c release

# 
# 2. Generate Native Multi-Resolution Retina AppIcon.icns
# 
echo "\n[2/8] Generating native AppIcon.icns..."
swift scripts/generate_icon.swift

# 
# 3. Build Universal CoreAudio HAL Virtual Driver Bundle
# 
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

# 
# 4. Build Standalone C DSP Benchmark & Diagnostic Utility
# 
echo "\n[4/8] Compiling native DSP benchmark CLI utility..."
clang -O3 \
    docker/cli_main.c \
    Sources/CDspKernel/CDspKernel.c \
    -I Sources/CDspKernel/include \
    -framework Accelerate \
    -o "$DIST_DIR/dynaq-cli"

chmod +x "$DIST_DIR/dynaq-cli"
codesign --force --sign - "$DIST_DIR/dynaq-cli"

# 
# 4b. Build High-Performance Rust DSP & Acoustic Optimizer
# 
echo "\n[4b/8] Compiling Rust acoustic optimization engine (dynaq-rust)..."
CARGO_CMD="$HOME/.cargo/bin/cargo"
if [ ! -x "$CARGO_CMD" ]; then
    CARGO_CMD="cargo"
fi
(cd "$REPO_ROOT/native/dynaq-rust" && "$CARGO_CMD" build --release)
cp "$REPO_ROOT/native/dynaq-rust/target/release/dynaq-opt" "$DIST_DIR/dynaq-opt"
cp "$REPO_ROOT/native/dynaq-rust/target/release/libdynaq_rust.dylib" "$DIST_DIR/libdynaq_rust.dylib"
chmod +x "$DIST_DIR/dynaq-opt"
codesign --force --sign - "$DIST_DIR/dynaq-opt"
codesign --force --sign - "$DIST_DIR/libdynaq_rust.dylib"

# 
# 5. Assemble Self-Contained dynaQ.app Bundle
# 
echo "\n[5/8] Assembling self-contained dynaQ.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources/python"
mkdir -p "$APP_BUNDLE/Contents/Resources/driver"

# Executables & Native Helpers
cp ".build/release/dynaQ" "$APP_BUNDLE/Contents/MacOS/dynaQ"
cp ".build/release/dynaQ-router" "$APP_BUNDLE/Contents/Helpers/dynaQ-router"
cp "$DIST_DIR/dynaq-cli" "$APP_BUNDLE/Contents/Helpers/dynaq-cli"
cp "$DIST_DIR/dynaq-opt" "$APP_BUNDLE/Contents/Helpers/dynaq-opt"
cp "$DIST_DIR/libdynaq_rust.dylib" "$APP_BUNDLE/Contents/Frameworks/libdynaq_rust.dylib"
cp -R "$REPO_ROOT/python/dynaq" "$APP_BUNDLE/Contents/Resources/python/"

chmod +x "$APP_BUNDLE/Contents/MacOS/dynaQ"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaQ-router"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaq-cli"
chmod +x "$APP_BUNDLE/Contents/Helpers/dynaq-opt"

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
# 6. Build Native macOS All-In-One Distribution Package (.pkg)
# ------------------------------------------------------------------------------
echo "\n[6/7] Building unified all-in-one macOS installer package..."
PKG_ROOT="$DIST_DIR/pkg_root"
PKG_SCRIPTS="$DIST_DIR/pkg_scripts"
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$DIST_DIR/dynaQ-component.pkg" "$DIST_DIR/dynaQ-Installer.pkg"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_ROOT/usr/local/lib"
mkdir -p "$PKG_ROOT/Library/Audio/Plug-Ins/HAL"
mkdir -p "$PKG_ROOT/Library/LaunchAgents"
mkdir -p "$PKG_SCRIPTS"

# 1. Install app bundle to /Applications
cp -R "$APP_BUNDLE" "$PKG_ROOT/Applications/"

# 2. Install pre-compiled CLI tools to /usr/local/bin
cp ".build/release/dynaQ" "$PKG_ROOT/usr/local/bin/dynaq"
cp ".build/release/dynaQ-router" "$PKG_ROOT/usr/local/bin/dynaq-router"
cp "$DIST_DIR/dynaq-opt" "$PKG_ROOT/usr/local/bin/dynaq-opt"
cp "$DIST_DIR/libdynaq_rust.dylib" "$PKG_ROOT/usr/local/lib/libdynaq_rust.dylib"

# Python Backend Launcher Script
cat << 'BACKEND_EOF' > "$PKG_ROOT/usr/local/bin/dynaq-backend"
#!/bin/sh
export PYTHONPATH="/Applications/dynaQ.app/Contents/Resources/python:$PYTHONPATH"
export DYNAQ_RUST_LIB="/Applications/dynaQ.app/Contents/Frameworks/libdynaq_rust.dylib"
exec /usr/bin/python3 -m dynaq.cli "$@"
BACKEND_EOF

chmod +x "$PKG_ROOT/usr/local/bin/dynaq"
chmod +x "$PKG_ROOT/usr/local/bin/dynaq-router"
chmod +x "$PKG_ROOT/usr/local/bin/dynaq-opt"
chmod +x "$PKG_ROOT/usr/local/bin/dynaq-backend"

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
chmod +x /usr/local/bin/dynaq-opt 2>/dev/null || true
chmod +x /usr/local/bin/dynaq-backend 2>/dev/null || true

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

# Build Component Package
pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$PKG_SCRIPTS" \
    --identifier "com.dynaq.audio.pkg.complete" \
    --version "${APP_VERSION}" \
    --install-location "/" \
    "$DIST_DIR/dynaQ-component.pkg"

# Create synthesized Distribution XML with custom title
cat <<EOF > "$DIST_DIR/Distribution.xml"
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>dynaQ Professional Audio Suite</title>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64" rootVolumeOnly="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.dynaq.audio.pkg.complete"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.dynaq.audio.pkg.complete" visible="false">
        <pkg-ref id="com.dynaq.audio.pkg.complete"/>
    </choice>
    <pkg-ref id="com.dynaq.audio.pkg.complete" version="${APP_VERSION}" onConclusion="none">dynaQ-component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
    --distribution "$DIST_DIR/Distribution.xml" \
    --package-path "$DIST_DIR" \
    "$DIST_DIR/dynaQ-Installer.pkg"

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$DIST_DIR/dynaQ-component.pkg" "$DIST_DIR/Distribution.xml"
echo "  ✓ Unified native installer package created: $DIST_DIR/dynaQ-Installer.pkg"

# 
# 7. Build Unified All-In-One Disk Image (.dmg)
# 
echo "\n[7/7] Creating unified All-In-One installer disk image (dynaQ-Installer.dmg)..."
ALL_IN_ONE_STAGING="$DIST_DIR/all_in_one_staging"
rm -rf "$ALL_IN_ONE_STAGING" "$DIST_DIR/dynaQ-Installer.dmg"
mkdir -p "$ALL_IN_ONE_STAGING"

# 1. Native Installer Package (.pkg)
cp "$DIST_DIR/dynaQ-Installer.pkg" "$ALL_IN_ONE_STAGING/Install dynaQ.pkg"

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
   Double-click "Install dynaQ.pkg".
   This automatically installs:
     - dynaQ.app into /Applications
     - dynaq & dynaq-router CoreAudio CLI into /usr/local/bin
     - dynaq-opt Rust Acoustic Optimizer into /usr/local/bin
     - dynaq-backend Python Telemetry & SDK CLI into /usr/local/bin
     - libdynaq_rust.dylib native SIMD engine into /usr/local/lib
     - CoreAudio Virtual Audio HAL Driver into /Library/Audio/Plug-Ins/HAL
     - Restarts CoreAudio automatically (no system reboot needed)

2. DRAG-AND-DROP INSTALLATION:
   Drag "dynaQ.app" directly into the "Applications" shortcut.
   The app is self-contained with embedded driver, Rust optimizer, Python backend, docs, and routing daemon.

3. UNINSTALLATION:
   Double-click "Uninstall dynaQ.command" to cleanly remove all components.

DOCUMENTATION:
   Built-in offline documentation is located inside dynaQ.app:
   /Applications/dynaQ.app/Contents/Resources/docs/index.html
================================================================================
EOF

hdiutil create \
    -volname "dynaQ Installer" \
    -srcfolder "$ALL_IN_ONE_STAGING" \
    -ov \
    -format UDZO \
    "$DIST_DIR/dynaQ-Installer.dmg"

rm -rf "$ALL_IN_ONE_STAGING"
echo "  ✓ Unified All-In-One disk image created: $DIST_DIR/dynaQ-Installer.dmg"

# 
# Populate output/ distribution folder with Unified Installer only
# 
echo "\nPopulating output/ distribution folder with unified installer..."
rm -rf "$OUTPUT_DIR"/*

cp "$DIST_DIR/dynaQ-Installer.dmg" "$OUTPUT_DIR/"
cp "$DIST_DIR/dynaQ-Installer.pkg" "$OUTPUT_DIR/"

cd "$OUTPUT_DIR"
ln -sf "dynaQ-Installer.dmg" "dynaQ-${APP_VERSION}-Installer.dmg"
ln -sf "dynaQ-Installer.pkg" "dynaQ-${APP_VERSION}-Installer.pkg"

cat <<EOF > "$OUTPUT_DIR/RELEASE_NOTES.txt"
======================================================================
  DYNAQ v${APP_VERSION} — UNIFIED ALL-IN-ONE INSTALLER
======================================================================

PACKAGE CONTENTS:
  • dynaQ-Installer.dmg    : Complete Unified Disk Image Installer
  • dynaQ-Installer.pkg    : Native macOS Automated Installer Package
  • SHA256SUMS.txt         : Cryptographic verification checksums

WHATS NEW IN v${APP_VERSION}:
  • Rust High-Throughput DSP Helper (dynaq-opt):
      - Microsecond AutoEQ curve fitting using coordinate descent optimization
      - Windowed sinc FIR filter generator (Blackman / Hann / Hamming)
      - 4x oversampled true peak calculation (ITU-R BS.1770-4 Appendix 2)
      - libdynaq_rust.dylib native C-ABI dynamic library
  • Python Backend SDK & CLI (dynaq package & dynaq-backend):
      - IPC bridge client connecting via /tmp/dynaq_ipc.sock and 127.0.0.1:9876
      - Live telemetry streaming (peaks, LUFS, correlation, 64-bin FFT)
      - Headless audio daemon server mode (python3 -m dynaq.server)
      - Direct ctypes bridge to native Rust optimizer
  • CoreAudio HAL & Driver Overhaul:
      - Integrated non-blocking IPC server in dynaQ router
      - Jury/Schur-Cohn IIR pole stability validation

INSTALLATION:
  Method A: Double-click "dynaQ-Installer.pkg" (or open "dynaQ-Installer.dmg" and run "Install dynaQ.pkg")
            This automatically installs:
              - /Applications/dynaQ.app
              - /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver (CoreAudio HAL Driver)
              - /usr/local/bin/dynaq & dynaq-router (CoreAudio CLI tools)
              - /usr/local/bin/dynaq-opt (Rust Acoustic Optimizer CLI)
              - /usr/local/bin/dynaq-backend (Python SDK & Telemetry CLI)
              - /usr/local/lib/libdynaq_rust.dylib (Native Rust DSP engine)
              - Configures permissions and reloads CoreAudio daemon
            Plug-and-play: zero external dependencies, no brew or terminal setup required.

  Method B: Open "dynaQ-Installer.dmg" and drag "dynaQ.app" into Applications.
            dynaQ is fully self-contained with embedded driver, Rust optimizer, Python SDK, docs, and routing daemon.

MINIMUM REQUIREMENTS:
  • macOS 14.0 (Sonoma) or later
  • Apple Silicon or Intel 64-bit architecture
======================================================================
EOF

shasum -a 256 "dynaQ-Installer.dmg" "dynaQ-Installer.pkg" > SHA256SUMS.txt
cd "$REPO_ROOT"

echo "\n======================================================================"
echo "  ✓ UNIFIED INSTALLER CREATED SUCCESSFULLY IN output/"
echo "======================================================================"
ls -lh "$OUTPUT_DIR"
echo "======================================================================"
