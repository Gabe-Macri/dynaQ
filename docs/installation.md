# Deployment & Builds

dynaQ provides multiple deployment methods tailored for different workflows:
- **Homebrew**: Native macOS CLI and Cask package management.
- **Docker**: Containerized DSP benchmark suite and static documentation server.
- **Disk Image (DMG)**: Standalone drag-and-drop macOS desktop application.
- **Source Compilation**: Swift Package Manager build from source.

---

## Homebrew Installation (macOS)

For users who prefer CLI installations and background service management via Homebrew:

### 1. Add the Repository Tap
```bash
brew tap Gabe-Macri/dynaq https://github.com/Gabe-Macri/dynaQ
```

### 2. Install CLI Binaries & Daemon
Install the compiled `dynaq` CLI and `dynaq-router` binaries:

```bash
brew install dynaq
```

This places `dynaq` and `dynaq-router` into your `$PATH` (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel).

### 3. Background Daemon Management (`brew services`)
Run the lightweight audio router daemon as a background service managed by `launchd`:

```bash
# Start background router daemon
brew services start dynaq

# Check daemon status
brew services list

# Stop background router daemon
brew services stop dynaq
```

### 4. Install Desktop Application via Cask
To install the graphical `.app` bundle directly into `/Applications`:

```bash
brew install --cask dynaq
```

---

## Docker Container Environment

For containerized environments, Linux hosts, and automated CI pipelines, dynaQ provides an Alpine-based Docker package (< 20 MB) containing the compiled C DSP kernel CLI and the documentation server.

### 1. Build the Docker Image
```bash
docker build -t dynaq .
```

### 2. Run DSP Diagnostics & Benchmarks
```bash
# Display CLI reference and engine parameters
docker run --rm dynaq --help

# Run real-time DSP cycle benchmarks (biquads, SPSC ring buffer, limiter)
docker run --rm dynaq --bench

# Execute mathematical verification tests
docker run --rm dynaq --verify

# Print audio engine specifications
docker run --rm dynaq --specs
```

### 3. Launch Local Documentation Server
Launch the static documentation web server on port 8080:

```bash
docker run -d -p 8080:8080 --name dynaq-docs dynaq docs
```

Navigate to `http://localhost:8080` to access the full technical reference.

### 4. Using Docker Compose
Alternatively, launch with Docker Compose:

```bash
# Start documentation server in background
docker compose up -d dynaq-docs

# Run one-off DSP benchmark
docker compose run --rm dynaq-cli --bench
```

---

## All-In-One Complete Installer (Recommended)

For users who want all dependencies, virtual audio drivers, background services, and CLI tools installed automatically in a single click:

### Included Components
- **Application Bundle**: `/Applications/dynaQ.app` (includes embedded offline documentation and helpers)
- **CLI Commands**: `/usr/local/bin/dynaq` and `/usr/local/bin/dynaq-router` (accessible globally from any terminal)
- **CoreAudio Virtual Driver**: `/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver` (universal arm64/x86_64)
- **Background Daemon Service**: `/Library/LaunchAgents/com.dynaq.router.plist`
- **Automatic Configuration**: Restarts `coreaudiod` post-install; zero terminal commands required.

### Installation Steps
1. Double-click `output/dynaQ-1.0.0-beta.1-all-in-one.dmg` (or standalone `output/dynaQ-1.0.0-beta.1-complete.pkg`).
2. Run **Install dynaQ Complete.pkg**.
3. Follow the standard macOS installer prompt and authenticate.
4. Launch `dynaQ` from `/Applications` or run `dynaq` from your terminal.

### Uninstallation
The All-In-One DMG includes an automated removal wizard:
- Double-click **Uninstall dynaQ.command** to cleanly remove all application binaries, drivers, and background services.

---

## Minimal Drag-and-Drop Disk Image (DMG)

For users who only require the standalone `.app` bundle without system-wide driver registration:

1. Double-click `output/dynaQ-1.0.0-beta.1.dmg`.
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

