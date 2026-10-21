# dynaQ System Documentation

dynaQ is a high-performance, system-wide parametric and dynamic audio equalizer and routing suite for macOS. It processes system audio across CoreAudio hardware inputs and outputs with low latency and deterministic execution.

The architecture decouples the low-overhead audio routing daemon from the high-throughput signal processing pipeline, ensuring that real-time audio threads remain lock-free, allocation-free, and resilient against buffer underruns.

---

## Technical Specifications

| Parameter | Specification |
| :--- | :--- |
| **Operating System** | macOS 14.0+ (Sonoma, Sequoia) |
| **Architecture** | Apple Silicon (arm64) and Intel (x86_64) |
| **Audio Subsystem** | CoreAudio HAL + AudioOutputUnit (AUHAL) |
| **Supported Sample Rates** | 44.1 kHz, 48.0 kHz, 88.2 kHz, 96.0 kHz, 192.0 kHz |
| **Hardware Buffer Sizes** | 64, 128, 256, 512, 1024 samples |
| **DSP Precision** | 32-bit floating point (single precision) SIMD |
| **Vector Extensions** | Apple Accelerate Framework (vDSP) |
| **EQ Topologies** | Parametric Peaking, Shelving, Bandpass, High/Low Cut, Notch |
| **Dynamic Processing** | Envelope detector with peak/RMS tracking and dynamic ratio |
| **Metering** | True Peak, RMS, ITU-R BS.1770 / EBU R128 LUFS |
| **Inter-Process Model** | Lock-free atomic single-producer single-consumer (SPSC) ring buffer |

---

## System Architecture Overview

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
                                                   |  CDspKernel SPSC    |
                                                   |  Atomic Ring Buffer |
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
                                                   | Dynamic EQ Detector |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Vector Biquad Array |
                                                   | (Direct Form II-T)  |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Mid/Side Matrix Dec |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | Phase & Monitor Mux |
                                                   +---------------------+
                                                              |
                                                              v
                                                   +---------------------+
                                                   | True Peak Limiter   |
                                                   +---------------------+
                                                              |
                                          +-------------------+-------------------+
                                          |                                       |
                                          v                                       v
                               +---------------------+                 +---------------------+
                               | vDSP FFT Visualizer |                 | CoreAudio Output IO |
                               | & BS.1770 Loudness  |                 | Physical DAC/Monitors|
                               +---------------------+                 +---------------------+
```

---

## Core Subsystems

### 1. Dedicated Routing Backend (`DynaQAudioDriver`)
The routing backend manages device discovery, stream configuration, buffer synchronization, and audio tap callbacks. When running without active DSP processing, the router executes in passthrough mode with negligible CPU utilization.

### 2. High-Performance C DSP Kernel (`CDspKernel`)
Time-critical signal math is implemented in C99 using Apple `Accelerate` (vDSP) vectorization and `stdatomic.h` memory primitives:
- Lock-free SPSC ring buffer for inter-thread audio frame exchange.
- Cascaded Direct Form II Transposed biquad filter processing.
- Vectorized Mid/Side encoding and decoding.
- Soft-knee true peak brickwall limiter.

### 3. Client DSP Pipeline (`ClientDSPPipeline`)
The client pipeline registers with the audio driver via the `AudioProcessingClient` protocol. It pulls frames from the ring buffer, runs parameter interpolation, recalculates dynamic filter gains, and pushes processed frames back to the output stream.

### 4. Graphic Equalizer & Telemetry UI (`DynaQUI` / `DynaQApp`)
The user interface renders frequency curves, dynamic gain shifts, a 1024-point FFT spectrum visualizer, 24-segment LED VU meters, and device selection menus in a terminal-inspired dark monochrome display.

---

## Quick Start

### Build and Test
Compile the complete workspace and execute the unit test suites:

```bash
swift build
swift test --parallel
```

### Enumerate Audio Devices and Latencies
Inspect system audio devices, sample rates, buffer sizes, and calculated hardware roundtrip latencies:

```bash
swift run dynaQ --list-devices
```

### Run Standalone Routing Daemon
Run the headless routing backend:

```bash
swift run dynaQ-router
```

### Launch Studio Application
Launch the graphical equalizer application:

```bash
swift run dynaQ
```

