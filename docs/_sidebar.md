- System Overview
  - [System Overview](README.md)
  - [Technical Specifications](README.md#technical-specifications)
  - [Quick Start](README.md#quick-start)

- Architecture & Design
  - [Decoupled Architecture](architecture.md)
  - [Threading & Memory Model](architecture.md#threading-and-memory-model)
  - [Client Stream Protocol](architecture.md#client-stream-protocol)

- Core C DSP Kernel
  - [CDspKernel Overview](c-dsp-kernel.md)
  - [Atomic SPSC Ring Buffer](c-dsp-kernel.md#atomic-spsc-ring-buffer)
  - [Vectorized Biquad Engine](c-dsp-kernel.md#vectorized-biquad-engine)
  - [Mid/Side Matrixing](c-dsp-kernel.md#vectorized-midside-processing)
  - [True Peak Soft-Knee Limiter](c-dsp-kernel.md#true-peak-soft-knee-limiter)

- EQ & Signal Processing
  - [Parametric Equalizer](dsp-engine.md)
  - [RBJ Biquad Mathematics](dsp-engine.md#rbj-biquad-filter-mathematics)
  - [Dynamic EQ Envelope Detector](dsp-engine.md#dynamic-eq-envelope-tracking)
  - [vDSP FFT & Loudness Telemetry](dsp-engine.md#spectral-analysis-and-loudness)

- CoreAudio & Routing
  - [Hardware I/O Integration](routing-and-io.md)
  - [Capture Mechanisms](routing-and-io.md#capture-mechanisms)
  - [Roundtrip Latency Calculation](routing-and-io.md#roundtrip-latency-calculation)
  - [Acoustic Feedback Guard](routing-and-io.md#acoustic-feedback-guard)

- Router Daemon & CLI
  - [Standalone Router Daemon](cli-and-router.md)
  - [CLI Reference](cli-and-router.md#command-line-reference)

- Deployment & Builds
  - [Disk Image Installation](installation.md)
  - [Building from Source](installation.md#building-from-source)
  - [Release Packaging Pipeline](installation.md#release-packaging-pipeline)
