# dynaQ System Documentation

dynaQ is a high-performance, system-wide parametric and dynamic audio equalizer and routing suite for macOS. Engineered in C, Rust, and Swift, dynaQ processes system audio across CoreAudio hardware inputs and outputs with deterministic real-time latency and zero thread contention.

The architecture decouples the low-overhead audio routing daemon from the high-throughput signal processing pipeline, ensuring real-time audio threads remain lock-free, allocation-free, and protected against buffer underruns.

---

## Technical Specifications

| Subsystem | Specification |
| :--- | :--- |
| **Operating System** | macOS 14.0+ (Sonoma, Sequoia) |
| **Host Architectures** | Apple Silicon (`arm64`), Intel 64-bit (`x86_64`) |
| **Audio Subsystem** | CoreAudio HAL + AudioOutputUnit (`AUHAL`) + Process Tap (`CATapDescription`) |
| **Sample Rates** | 44.1 kHz, 48.0 kHz, 88.2 kHz, 96.0 kHz, 192.0 kHz (dynamic clock switching) |
| **Hardware Buffer Sizes** | 64, 128, 256, 512, 1024 samples |
| **Roundtrip Latency** | $\sim 2.8\text{ ms}$ (at 64 samples / 48 kHz) |
| **DSP Precision** | 32-bit floating point SIMD (Apple Accelerate vDSP + Rust SIMD + C99) |
| **Equalizer Topologies** | Parametric Peaking (Bell), Low/High Shelf, Bandpass, High/Low Cut, Notch |
| **Modulation Modes** | Static EQ, Dynamic Gain Modulation, Frequency Modulation (Envelope & LFO) |
| **Telemetry & Limits** | True Peak Limiter (0ms Live / 32spl Mastering), RMS, ITU-R BS.1770 LUFS |
| **Inter-Process IPC** | JSON-RPC over Unix domain socket (`/tmp/dynaq_ipc.sock`) and TCP (9879) |
| **Concurrency Model** | Lock-free atomic Single-Producer Single-Consumer (SPSC) ring buffers |

---

## Signal Pipeline Architecture

```
                      +---------------------------------------+
                      |       macOS Audio Output Stream       |
                      |   (Apple Music, Spotify, DAW, System)  |
                      +---------------------------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |         Audio Capture Layer           |
                      |   CoreAudio Process Tap / Loopback    |
                      +---------------------------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |         DynaQAudioDriver Engine       |
                      |       (AudioRouterBackend Daemon)     |
                      +---------------------------------------+
                                          |
                      +-------------------+-------------------+
                      |                                       |
                      | [Passthrough Mode]                    | [Active Client Pipeline]
                      v                                       v
               To Physical Out                     +---------------------+
                                                   | SPSC In Ring Buffer |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Preamp Gain Staging |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Mid/Side Matrix Enc |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | FM EQ & Biquad DF2T |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Dynamic EQ Detector |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Mid/Side Matrix Dec |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | +3dB Anti-Clip Guard|
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | True Peak Limiter   |
                                                   | (Live vs Mastering) |
                                                   +---------------------+
                                                              |
                                          +-------------------+-------------------+
                                          |                                       |
                                          v                                       v
                               +---------------------+                 +---------------------+
                               | Visualizer SPSC Ring|                 | CoreAudio Output IO |
                               +---------------------+                 | Physical DAC/Phones |
                                          |                            +---------------------+
                                          v
                               +---------------------+
                               | vDSP FFT & BS.1770  |
                               | (Background Thread) |
                               +---------------------+
```

---

## Core Subsystems

### 1. Dedicated Routing Backend (`DynaQAudioDriver`)
Manages device discovery, format negotiation, buffer synchronization, and audio tap callbacks. When running without active DSP processing, the router executes in transparent hardware passthrough mode (~0.0% CPU).

### 2. High-Performance C DSP Kernel (`CDspKernel`)
Time-critical signal math written in C99 with Apple Accelerate (`vDSP`) and `stdatomic.h`:
- Lock-free atomic SPSC ring buffers for inter-thread audio frame exchange.
- Cascaded Direct Form II Transposed biquad filter processing with parameter smoothing.
- Vectorized Mid/Side encoding and pre-limiter matrix decoding.
- Lookahead soft-knee true peak brickwall limiter with Zero-Latency Live Mode (0 lookahead samples).

### 3. Rust SIMD AutoEQ Engine (`dynaq-rust`)
Sub-millisecond parametric EQ curve optimization (SLSQP replacement reducing target curve RMSE) and 4x oversampled true-peak detection, exposed via `libdynaq_rust.dylib` and the `dynaq-opt` CLI tool.

### 4. Python Backend SDK & IPC Bridge (`python/dynaq`)
Headless service daemon and Python client communicating over `/tmp/dynaq_ipc.sock`. Provides programmatic EQ profile loading, telemetry polling, and automated testing integration.

### 5. Monospace Canvas User Interface (`DynaQUI` / `DynaQApp`)
Zero-allocation SwiftUI `Canvas` rendering 64-bin FFT spectrum visualizers, 20-segment LED VU meters, and dynamic EQ frequency response curves at 60–120 FPS.

---

## Quick Start

### Build and Test
```bash
# Compile Swift workspace and execute tests
swift build
swift test --parallel

# Execute Rust SIMD test suite
cargo test --manifest-path native/dynaq-rust/Cargo.toml

# Execute Python IPC test suite
python3 -m unittest discover -s python/tests
```

### Hardware Device Inspection
```bash
swift run dynaQ --list-devices
```

### Standalone Routing Daemon
```bash
swift run dynaQ-router
```

### Studio Application
```bash
swift run dynaQ
```
