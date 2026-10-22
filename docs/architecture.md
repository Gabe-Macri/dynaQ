# Architecture & Design

dynaQ utilizes a decoupled, multi-tier architecture engineered to eliminate latency jitter, buffer underruns, and priority inversion in macOS audio processing.

---

## Decoupled Architecture

Coupling user interface updates, high-throughput DSP calculations, and hardware IO on the same thread creates dropouts under CPU contention. dynaQ isolates hardware IO, real-time DSP, background telemetry, and external control into dedicated subsystems:

```
+-------------------------------------------------------------------------------+
|                             CoreAudio HAL Layer                               |
+-------------------------------------------------------------------------------+
         | (AUHAL Input Callback)                        ^ (AUHAL Output Callback)
         v                                               |
+-------------------------------------------------------------------------------+
|                       DynaQAudioDriver (Router Backend)                       |
|  - Real-Time IO Callback Scheduling                                           |
|  - Hardware Device Enumeration & Format Negotiation                           |
|  - Dynamic Sample Rate Reconfiguration & Ring Buffer Flush                    |
|  - Transparent Hardware Passthrough Path (~0.0% CPU when inactive)            |
+-------------------------------------------------------------------------------+
         |                                               ^
         | Write Input Frames                            | Read Processed Frames
         v                                               |
+-------------------------------------------------------------------------------+
|                       CDspKernel Lock-Free Ring Buffers                       |
|  - Atomic SPSC Memory Barriers (memory_order_release / acquire)               |
|  - Zero Allocation during steady-state processing                             |
|  - Power-of-two circular topologies                                           |
+-------------------------------------------------------------------------------+
         |                                               ^
         | Real-Time Ingest                              | Real-Time Output
         v                                               |
+-------------------------------------------------------------------------------+
|                      DynaQDSP (Real-Time Signal Pipeline)                     |
|  - Preamp Gain Staging (-18 dB to +18 dB)                                     |
|  - Vectorized Mid/Side Encoder & Pre-Limiter Decoder                          |
|  - Cascaded Direct Form II Transposed Biquads with Linear Ramping             |
|  - Dynamic Gain Modulation & Frequency Modulation (Envelope / LFO)            |
|  - Internal +3.0 dB Soft-Knee Saturation Guard                                |
|  - True Peak Limiter (0ms Live Mode / 32-sample Mastering Mode)               |
+-------------------------------------------------------------------------------+
         |
         | Non-Blocking Frame Push (Drops on Full)
         v
+-------------------------------------------------------------------------------+
|                      Visualizer SPSC Ring Buffer                              |
|  - Isolates Real-Time Render Thread from Telemetry Computation                |
+-------------------------------------------------------------------------------+
         |
         v
+-------------------------------------------------------------------------------+
|                      Background Telemetry Thread                              |
|  - 1024-Point vDSP FFT Spectrum Analysis                                      |
|  - ITU-R BS.1770 / EBU R128 Loudness Integration                              |
+-------------------------------------------------------------------------------+
         | Atomic Downsampled Readings
         v
+-------------------------------------------------------------------------------+
|                      DynaQUI (Monospace Presentation Layer)                   |
|  - Zero-Allocation SwiftUI Canvas Rendering (60-120 FPS)                      |
|  - Discrete 64-Column RTA Spectrum Visualizer                                 |
|  - Dual 20-Segment LED VU Meters with Falloff Physics                         |
+-------------------------------------------------------------------------------+
```

---

## Threading and Memory Model

The CoreAudio IO thread runs with real-time thread priority (`THREAD_TIME_CONSTRAINT_POLICY`). Any blocking operation risks buffer underruns:
1. **Zero Dynamic Allocation**: Calls to `malloc`, `free`, `realloc`, or Swift object/string allocations are strictly prohibited inside the IO callback. All buffers are pre-allocated at startup or device reconfiguration.
2. **Lock-Free Concurrency**: Mutexes (`pthread_mutex_t`, `NSLock`, `os_unfair_lock`) are excluded from real-time paths to prevent priority inversion. Inter-thread communication uses atomic single-producer single-consumer (`c_ringbuffer_t`) queues with release/acquire memory barriers.
3. **No Syscalls or File/Socket IO**: Disk access, IPC sockets, and network descriptors are restricted to background workers.

### Concurrency Guarantees
- The audio capture callback pushes incoming frames to the primary input SPSC ring buffer.
- The DSP pipeline transforms frames and writes results to the output SPSC buffer.
- The hardware output callback reads processed frames from the output SPSC buffer.
- Filter coefficients ramp linearly across each buffer block, eliminating parameter sweep zipper noise.

---

## Visualizer Ring Buffer Decoupling

Spectral analysis (1024-point FFT) and ITU-R BS.1770 LUFS integration are offloaded from the DAC thread:
- At the end of the DSP signal chain, equalized audio frames are copied into a secondary **Visualizer SPSC Ring Buffer** using non-blocking atomic writes.
- If the visualizer queue fills (e.g., during UI render stalls), excess frames are discarded with zero backpressure on the DAC thread.
- A dedicated background worker consumes frames from the visualizer ring buffer, executes windowed vDSP FFT and loudness integration, and stores peak levels into atomics polled by the UI at the display refresh rate (60–120 Hz).

---

## Client Stream Protocol

Communication between the routing engine and client DSP instances is governed by the `AudioProcessingClient` protocol:

```swift
public protocol AudioProcessingClient: AnyObject {
    var clientID: String { get }
    var sampleRate: Double { get }
    var maxFrames: Int { get }

    func processAudio(
        leftChannel: UnsafeMutablePointer<Float>,
        rightChannel: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Bool
}
```

### Registration Lifecycle
1. The client registers via `AudioRouterBackend.shared.registerClient(self)`.
2. The router queries hardware sample rates and buffer sizes, invoking `client.configure(sampleRate:bufferSize:)`.
3. When the router's IO callback executes:
   - If a client is active, samples pass to `client.processAudio(...)`.
   - If the client returns `false` or underruns, the router forwards input frames directly to output hardware to guarantee uninterrupted audio playback.
4. On client shutdown, `unregisterClient(self)` restores direct hardware passthrough.

---

## Rust Optimization Engine & Python IPC

To support automated target curve matching and headless server automation:
- **Rust SIMD Engine (`dynaq-rust`)**: Compiled as a native dynamic library (`libdynaq_rust.dylib`) and CLI (`dynaq-opt`). Calculates optimal biquad center frequencies, Q factors, and gains to fit measured headphone/room responses against target curves (e.g. Harman, Diffuse Field) using SIMD-accelerated RMSE minimization.
- **Python IPC Bridge (`python/dynaq`)**: Headless daemon interfacing with `dynaQ` over a Unix domain socket (`/tmp/dynaq_ipc.sock`) using JSON-RPC 2.0. Enables programmatic profile switching, telemetry streaming, and automated regression testing.
