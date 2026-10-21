# Deployment & Builds

dynaQ can be installed as a pre-packaged disk image installer (`.dmg`) or compiled directly from source using the Swift Package Manager.

---

## Installation via Disk Image (DMG)

Pre-built production images are located in the `output/` release folder:

1. Double-click `dynaQ-1.0.0-beta.1.dmg` to mount the disk image.
2. Drag `dynaQ.app` into `/Applications`.
3. Open `dynaQ.app` from `/Applications` or launch via Spotlight.

---

## Building from Source

### System Prerequisites
- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Build Tools**: Xcode 15.0+ or Xcode Command Line Tools (`xcode-select --install`).
- **Toolchain**: Swift 5.9+.

### Quick Build

Compile release binaries directly from the repository root:

```bash
# Debug build with unit test execution
swift build
swift test --parallel

# Optimized production release build
swift build -c release
```

Binaries will be placed in `.build/release/`:
- `.build/release/dynaQ` (Main application binary)
- `.build/release/dynaQ-router` (Standalone routing daemon)

---

## Release Packaging Pipeline

To generate the complete production app bundle and compressed installer disk image, execute the automated release script:

```bash
./scripts/build_release.sh
```

### Build Pipeline Steps

1. **Production Compilation**:
   Executes `swift build -c release` with optimizations (`-O`) and dead-code stripping.

2. **Retina Icon Generation**:
   Executes `swift scripts/generate_icon.swift`, rendering multi-resolution raster assets (16x16 through 1024x1024) and packaging them into a native macOS `AppIcon.icns`.

3. **Application Bundle Assembly**:
   Constructs the macOS application directory layout:
   ```
   dist/dynaQ.app/
   └── Contents/
       ├── Info.plist
       ├── MacOS/
       │   └── dynaQ
       ├── Helpers/
       │   └── dynaQ-router
       └── Resources/
           └── AppIcon.icns
   ```

4. **Code Signing**:
   Signs all binaries and bundles with ad-hoc signature (`codesign --force --deep --sign -`).

5. **DMG Disk Image Creation**:
   Creates a read-only compressed UDZO disk image (`hdiutil create -ov -format UDZO`) with an `/Applications` symlink for drag-and-drop installation.

---

## macOS Audio Permissions

System audio interception requires macOS user permission:
1. On the first launch, macOS will present a system prompt requesting permission to capture audio.
2. Grant permission under **System Settings > Privacy & Security > Microphone**.
3. If using loopback devices, ensure the virtual driver has permission to capture system output.
