- System Overview
  - [System Overview](README.md)
  - [Technical Specifications](README.md#technical-specifications)
  - [Pipeline Architecture](README.md#signal-pipeline-architecture)
  - [Quick Start](README.md#quick-start)

- Architecture & Threading
  - [Decoupled Architecture](architecture.md#decoupled-architecture)
  - [Threading & Memory Model](architecture.md#threading-and-memory-model)
  - [Visualizer Ring Buffer Decoupling](architecture.md#visualizer-ring-buffer-decoupling)
  - [Client Stream Protocol](architecture.md#client-stream-protocol)

- Core C DSP Kernel
  - [CDspKernel Overview](c-dsp-kernel.md#core-c-dsp-kernel)
  - [Atomic SPSC Ring Buffer](c-dsp-kernel.md#atomic-spsc-ring-buffer)
  - [Vectorized Biquad Engine](c-dsp-kernel.md#vectorized-biquad-engine)
  - [Mid/Side Matrix & Pre-Limiter Decode](c-dsp-kernel.md#vectorized-midside-processing)
  - [True Peak Limiter & Live Mode](c-dsp-kernel.md#true-peak-soft-knee-limiter)

- EQ & Signal Processing
  - [Parametric Equalizer](dsp-engine.md#parametric-equalizer)
  - [RBJ Biquad Filter Mathematics](dsp-engine.md#rbj-biquad-filter-mathematics)
  - [Frequency Modulation (FM EQ)](dsp-engine.md#frequency-modulation-fm-eq)
  - [Dynamic Gain Modulation](dsp-engine.md#dynamic-gain-modulation)
  - [Anti-Clip Headroom Guard](dsp-engine.md#anti-clip-headroom-guard)
  - [Spectral Analysis & Loudness](dsp-engine.md#spectral-analysis-and-loudness)

- CoreAudio & Routing
  - [Hardware I/O Integration](routing-and-io.md#hardware-io-integration)
  - [Capture Mechanisms](routing-and-io.md#capture-mechanisms)
  - [Dynamic Sample Rate Switching](routing-and-io.md#dynamic-sample-rate-switching)
  - [Auto-Routing on Startup](routing-and-io.md#auto-routing-on-startup)
  - [Roundtrip Latency Calculation](routing-and-io.md#roundtrip-latency-calculation)
  - [Acoustic Feedback Guard](routing-and-io.md#acoustic-feedback-guard)

- Rust & Python Platform
  - [Rust SIMD Engine & AutoEQ](cli-and-router.md#rust-simd-optimization-engine-dynaq-opt)
  - [Python Backend SDK & IPC](cli-and-router.md#python-backend-sdk-and-ipc-bridge)
  - [Router Daemon](cli-and-router.md#standalone-router-daemon)
  - [CLI Reference](cli-and-router.md#command-line-reference)

- Deployment & Builds
  - [All-In-One Unified Installer](installation.md#unified-all-in-one-installer-recommended)
  - [Homebrew Installation](installation.md#homebrew-installation-macos)
  - [Docker Environment](installation.md#docker-container-environment)
  - [Building from Source](installation.md#building-from-source)
  - [Automated Release Packaging](installation.md#release-packaging-pipeline)
