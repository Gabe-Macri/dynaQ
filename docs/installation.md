# Deployment & Builds

dynaQ provides multiple deployment methods tailored for studio workstations, headless daemons, CI pipelines, and package managers:
- **Unified Installer (DMG/PKG)**: All-in-one signed package with drivers, CLI utilities, and background daemon.
- **Homebrew**: Native macOS CLI and Cask package management.
- **Docker**: Containerized DSP benchmark suite and static documentation server (< 20 MB).
- **Source Compilation**: Swift Package Manager and Cargo build pipelines.

---

## Unified All-In-One Installer (Recommended)

The complete release package (`v1.0.0-beta.2`) bundles the desktop application, HAL driver, Rust optimizer, Python SDK, and command-line tools into a single authenticated installer:

### Included Components
- **Application Bundle**: `/Applications/dynaQ.app` (includes embedded offline documentation and Python SDK)
- **CLI Commands**: `/usr/local/bin/dynaq`, `/usr/local/bin/dynaq-router`, `/usr/local/bin/dynaq-opt`, `/usr/local/bin/dynaq-cli`
- **Dynamic Libraries**: `/usr/local/lib/libdynaq_rust.dylib`
- **CoreAudio HAL Driver**: `/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver` (universal `arm64` / `x86_64`)
- **Background Daemon Service**: `/Library/LaunchAgents/com.dynaq.router.plist`
- **Automatic Setup**: Restarts `coreaudiod` immediately post-install; zero terminal commands required.

### Installation Steps
1. Double-click `output/dynaQ-Installer.dmg` (or standalone `output/dynaQ-Installer.pkg`).
2. Run **Install dynaQ Complete.pkg**.
3. Follow the standard macOS installer wizard and authenticate.
4. Launch `dynaQ` from `/Applications` or run `dynaq` from any terminal session.

### Clean Uninstallation
The installer disk image includes an automated zero-trace removal utility:
- Double-click **Uninstall dynaQ.command** to cleanly purge all binaries, HAL drivers, and LaunchAgent services.

---

## Homebrew Installation (macOS)

For users managing command-line packages and services via Homebrew:

### 1. Tap Repository
```bash
brew tap Gabe-Macri/dynaq https://github.com/Gabe-Macri/dynaQ
```

### 2. Install CLI Binaries & Daemon
```bash
brew install dynaq
```
Installs `dynaq`, `dynaq-router`, and `dynaq-opt` into `$PATH` (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel).

### 3. Background Daemon Management (`launchd`)
```bash
# Start background router daemon
brew services start dynaq

# Check daemon health
brew services list

# Stop background router daemon
brew services stop dynaq
```

### 4. Install Desktop Application via Cask
```bash
brew install --cask dynaq
```

---

## Docker Container Environment

For CI pipelines, Linux hosts, and DSP benchmarking, dynaQ provides an Alpine-based container package (< 20 MB):

### 1. Build Image
```bash
docker build -t dynaq .
```

### 2. Run DSP Benchmarks & Diagnostics
```bash
# Run real-time DSP cycle benchmarks (biquads, SPSC ring buffer, limiter)
docker run --rm dynaq --bench

# Execute mathematical verification tests
docker run --rm dynaq --verify

# Print audio engine specifications
docker run --rm dynaq --specs
```

### 3. Serve Local Offline Documentation
```bash
docker run -d -p 8080:8080 --name dynaq-docs dynaq docs
```
Navigate to `http://localhost:8080` for the complete technical reference.

---

## Building from Source

### System Prerequisites
- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Build Tools**: Xcode 15.0+ or Command Line Tools (`xcode-select --install`).
- **Toolchains**: Swift 5.9+, Rust 1.75+ (optional, for `dynaq-rust`), Python 3.10+.

### Compilation Steps

```bash
# 1. Compile Swift application and router binaries
swift build -c release

# 2. Compile native Rust SIMD library and optimizer CLI
cargo build --release --manifest-path native/dynaq-rust/Cargo.toml

# 3. Execute unit test suites
swift test --parallel
cargo test --manifest-path native/dynaq-rust/Cargo.toml
python3 -m unittest discover -s python/tests
```

Compiled binaries are located in:
- `.build/release/dynaQ` (Main application binary)
- `.build/release/dynaQ-router` (Standalone routing daemon)
- `native/dynaq-rust/target/release/dynaq-opt` (Rust AutoEQ optimizer)
- `native/dynaq-rust/target/release/libdynaq_rust.dylib` (Shared C dynamic library)

---

## Release Packaging Pipeline

To generate the complete production app bundle, codesigned installers, and compressed DMGs:

```bash
./scripts/build_release.sh
```

### Automated Pipeline Workflow
1. **Production Compilation**: Executes `swift build -c release` with dead-code stripping and SIMD optimizations.
2. **Rust & Native Asset Assembly**: Builds `dynaq-opt` and `libdynaq_rust.dylib`, placing them into helper and library search paths.
3. **Retina Icon Generation**: Runs `swift scripts/generate_icon.swift`, rendering multi-resolution assets (16x16 to 1024x1024) into `AppIcon.icns`.
4. **Application Bundle Assembly**: Constructs `dist/dynaQ.app` with embedded documentation, Python IPC bridge, and LaunchAgent templates.
5. **Code Signing**: Applies ad-hoc codesigning signatures (`codesign --force --deep --sign -`).
6. **Installer Package (PKG) Creation**: Bundles payload into `/usr/local/bin`, `/Library/Audio/Plug-Ins/HAL/`, and `/Library/LaunchAgents/` with pre/postinstall hooks.
7. **DMG Disk Image Creation**: Generates compressed read-only UDZO disk image `output/dynaQ-Installer.dmg`.

---

## macOS Audio Permissions

System audio interception requires macOS user authorization:
1. On initial launch, macOS will request microphone/audio capture access.
2. Grant permission under **System Settings > Privacy & Security > Microphone**.
3. If utilizing the virtual driver, ensure the HAL extension is permitted under **Privacy & Security**.
