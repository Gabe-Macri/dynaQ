# dynaQ Virtual Audio Driver Architecture

dynaQ supports two mechanisms for system-wide audio capture and routing on macOS:

## 1. Virtual Audio Device (AudioServerPlugin)
The industry standard technique used by tools like eqMac, BlackHole, and Soundflower.
- Located in `/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver`.
- When active, macOS sends system-wide output audio to this virtual device.
- `dynaQ` reads the unrendered system PCM stream via low-latency ring buffer.
- The DSP engine applies parametric/dynamic EQ filters, soft limiting, and FFT analysis.
- The processed stream is rendered directly to your selected physical output (AirPods, Studio Monitors, USB DAC).
- **Latency**: < 2.5ms (depending on CoreAudio buffer size, e.g. 128 samples @ 48kHz).

## 2. Process-Level Audio Tapping (`CATapDescription`)
Available natively in macOS 14.2+ (Sonoma, Sequoia, and later).
- Uses `AudioHardwareCreateProcessTap` and `CATapDescription` to directly capture audio output streams from specific process IDs (PIDs) or bundle IDs (e.g. Spotify, Logic Pro, Chrome).
- Does not require third-party kernel extensions or driver installations.

## Driver Installation
Run:
```bash
./scripts/install_driver.sh
```
This builds the driver bundle, installs it into `/Library/Audio/Plug-Ins/HAL/`, and refreshes `coreaudiod`.
