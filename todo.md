# dynaQ Architectural Overhaul & Pro-DSP Native Packages

## Overview
Ditch the "lightweight" compromised approach in favor of an uncompromising, production-grade pro-audio architecture. Audio processing is decoupled into dedicated native packages optimized with C11, Apple Accelerate framework (`vDSP`, `vForce`), and SIMD vectorization. Every subsystem includes comprehensive error handling, recovery paths, and zero-allocation real-time execution.

---

## 1. Native Packages Architecture

- [x] **Package 1: `CDspKernel` / `DynaQKernel` (C11 + Apple Accelerate Framework)**
  - [x] SIMD-vectorized cascaded biquad filters (`vDSP_deq22` / unrolled vector arithmetic).
  - [x] Mathematical stability validation: filter pole checking (`|poles| < 1.0`), frequency clamping below Nyquist (`fs / 2`).
  - [x] Lookahead True-Peak Limiter with fractional circular delay line and smooth rational soft-knee compression.
  - [x] Real-time zero-lock SPSC ring buffer with 64-bit monotonic counters and zero-fill underrun protection.
  - [x] High-resolution FFT spectral analysis with power-of-two windowing (`vDSP_hann_window`, `vDSP_fft_zrip`).
  - [x] Anti-denormal flushing (`< 1e-15f`) and NaN/Infinity state recovery guards.
  - [x] Typed status codes and error reporting (`c_dsp_status_t`).

- [x] **Package 2: `DynaQDynamics` (Dedicated Dynamics & Limiting Engine)**
  - [x] Dedicated `TruePeakLimiter` with selectable lookahead (0.5ms - 2.0ms), stereo-linked peak tracking, and variable ceiling.
  - [x] Multi-knee dynamic EQ compressor/expander module.
  - [x] Typed error handling: `DynamicsError` (invalid ceiling, delay buffer overflow, sample rate invalid).

- [x] **Package 3: `DynaQAnalysis` (Dedicated Real-Time Metering & FFT Telemetry)**
  - [x] Fast zero-lock `SpectrumAnalyzer` with logarithmic frequency pooling (64/128/256 visualizer bins) and smooth decay ballistics.
  - [x] ITU-R BS.1770-4 / EBU R128 `LoudnessMeter` (integrated LUFS, momentary LUFS, short-term LUFS, true peak dBFS).
  - [x] Phase correlation meter and stereo balance detection.
  - [x] Lock-free triple buffer telemetry interface delivering 60/120fps UI updates without stalling audio threads.
  - [x] Typed error handling: `AnalysisError` (unsupported FFT size, null buffer, zero sample rate).

- [x] **Package 4: `DynaQDSP` (High-Performance Parametric & Dynamic Equalization)**
  - [x] Cascaded multi-band parametric EQ (up to 16 bands).
  - [x] Filter topologies: Bell/Peaking, Low Shelf, High Shelf, Low Pass, High Pass, Notch, Band Pass, Tilt.
  - [x] Mid/Side matrixing (independent Mid and Side processing channels).
  - [x] Dynamic EQ gain modulation engine.
  - [x] Typed error handling: `DSPError` (unstable filter poles, frequency out of bounds, invalid sample rate, channel count mismatch).

- [x] **Package 5: `DynaQAudioDriver` (Direct CoreAudio HAL & System Tap Engine)**
  - [x] Direct CoreAudio HAL IOProc with zero heap allocations on high-priority audio threads.
  - [x] macOS 14.2+ native System Audio Tapping (`CATapDescription`).
  - [x] Underrun detection and recovery with buffer trailing zero-fill.
  - [x] Clock and buffer frame synchronization between tap aggregate device and physical DAC.
  - [x] Hardware disconnection detection and automatic fallback to default audio output.
  - [x] Typed error handling: `AudioRouterError` (device not found, tap failed, sample rate mismatch, permission denied, buffer underrun).

---

## 2. Seamless Integration & Responsive UI (`DynaQUI` & `DynaQApp`)

- [x] Strict brutalist studio terminal aesthetic (monospace typography, sharp 1px borders, CRT phosphor accents).
- [x] 60fps/120fps responsive spectrum analyzer and segmented VU/LUFS meters without UI lag.
- [x] Comprehensive Pro-Audio Settings Menu (`SettingsView`):
  - [x] Audio I/O & Routing (System Tap vs Hardware Mic, buffer size 64-1024, latency telemetry).
  - [x] DSP & Limiting (master bypass, limiter ceiling, stereo link).
  - [x] Safety & Protection (acoustic feedback guard, denormal flushing, NaN/Inf protection).
  - [x] Real-time Diagnostics (underrun counter, engine health, live log stream).
  - [x] System Info (CoreAudio HAL driver status, single-click install/update trigger).
- [x] Actionable Error Alert Banners with instant reset/recovery controls.

---

## 3. Package Manifest & Dependency Graph (`Package.swift`)

- [x] Update `Package.swift` to register `DynaQDynamics` and `DynaQAnalysis` as independent native targets and products.
- [x] Wire dependencies cleanly:
  - `CDspKernel` -> standalone C engine.
  - `DynaQCore` -> foundational models.
  - `DynaQAudioDriver` -> depends on `DynaQCore`, `CDspKernel`.
  - `DynaQDSP` -> depends on `DynaQCore`, `CDspKernel`, `DynaQAudioDriver`.
  - `DynaQDynamics` -> depends on `DynaQCore`, `CDspKernel`.
  - `DynaQAnalysis` -> depends on `DynaQCore`, `CDspKernel`.
  - `DynaQUI` -> depends on `DynaQCore`, `DynaQDSP`, `DynaQDynamics`, `DynaQAnalysis`, `DynaQAudioDriver`.
  - `DynaQApp` -> depends on all targets.

---

## 4. Verification & Testing

- [x] Unit tests for `DynaQDSP` (frequency response, stability, pole checking, NaN guards).
- [x] Unit tests for `DynaQDynamics` (limiter ceiling clamping, lookahead delay, stereo linking, compressor knee).
- [x] Unit tests for `DynaQAnalysis` (FFT spectrum bins, loudness measurement, phase correlation).
- [x] Unit tests for `CDspKernel` (ring buffer monotonic counters, underrun zero-filling, SIMD execution).
- [x] Compile and verify release packaging pipeline (`./scripts/build_release.sh`).
- [x] Verify test suite passes (`swift test`).

---

## 5. Pull Request Creation

- [ ] Commit all changes with clean, atomic commit messages.
- [ ] Push branch to remote `origin/feature/native-audio-packages-pro-dsp`.
- [ ] Create Pull Request against `main`.

