# Architecture & Design

dynaQ is structured around a decoupled architecture designed to eliminate latency jitter and priority inversion in macOS audio processing.

---

## Decoupled Architecture

In standard real-time audio systems, coupling user interface events, complex DSP calculations, and hardware IO within the same thread or process leads to dropped frames (audio dropouts) when the host CPU experiences thread contention.

dynaQ separates audio routing from DSP execution:

```
+-------------------------------------------------------------------------------+
|                             CoreAudio HAL Layer                               |
+-------------------------------------------------------------------------------+
         | (AUHAL Input Callback)                        ^ (AUHAL Output Callback)
         v                                               |
+-------------------------------------------------------------------------------+
|                       DynaQAudioDriver (Router Backend)                       |
|                                                                               |
|  - Real-Time IO Callback Management                                           |
|  - Hardware Device Enumeration & Format Negotiation                           |
|  - Transparent Passthrough Path (~0.0% CPU when idle)                         |
+-------------------------------------------------------------------------------+
         |                                               ^
         | Write Capture Frames                          | Read Processed Frames
         v                                               |
+-------------------------------------------------------------------------------+
|                       CDspKernel Lock-Free Ring Buffer                        |
|                                                                               |
|  - Atomic SPSC Memory Barriers (memory_order_release / acquire)               |
|  - Zero Allocation during steady-state processing                             |
|  - Fixed Circular Topology                                                    |
+-------------------------------------------------------------------------------+
         |                                               ^
         | Consumer Read                                 | Producer Write
         v                                               |
+-------------------------------------------------------------------------------+
|                      DynaQDSP (Client Processing Pipeline)                    |
|                                                                               |
|  - Cascaded Direct Form II Transposed Biquad Filters                          |
|  - Mid / Side Matrix Encoder & Decoder                                        |
|  - Dynamic EQ Envelope Detection & Gain Modulation                            |
|  - True Peak Limiting & vDSP Vectorized Metering                              |
+-------------------------------------------------------------------------------+
         |
         v Telemetry Updates (Lock-Free Atomics / Downsampled)
+-------------------------------------------------------------------------------+
|                      DynaQUI (Monospace Presentation Layer)                   |
|                                                                               |
|  - 60 fps Vector EQ Curve Renderer                                            |
|  - 64-Bin FFT RTA Spectrum Visualizer                                         |
|  - Discrete 24-Segment VU Meters with True Peak Falloff                       |
+-------------------------------------------------------------------------------+
```

---

## Threading and Memory Model

Real-time audio callbacks run inside CoreAudio's high-priority IO thread. This thread imposes strict execution requirements:
1. **No Memory Allocation**: Calls to `malloc`, `free`, `realloc`, or Swift object/string allocations are strictly prohibited inside the IO callback.
2. **No Mutex Locks**: Mutexes (`pthread_mutex_t`, `NSLock`, Swift `os_unfair_lock`) can cause priority inversion if a lower-priority thread holds the lock when the IO thread preempts.
3. **No Blocking Operations**: File descriptors, network sockets, dispatch queues, and semaphore waits cannot be accessed on the audio thread.

### Concurrency Guarantees
- The audio capture callback writes incoming frames directly into an atomic SPSC ring buffer.
- The audio output callback reads processed frames from the output side of the ring buffer.
- Parameter updates (filter frequencies, gains, Q factors) are staged in atomic coefficient buffers with linear ramping per buffer block, preventing audible zipper noise.

---

## Client Stream Protocol

Communication between the routing backend and client processing instances is governed by the `AudioProcessingClient` protocol defined in `DynaQAudioDriver`:

```swift
public protocol AudioProcessingClient: AnyObject {
    /// Identifier for the client pipeline instance
    var clientID: String { get }
    
    /// Target sample rate negotiated by the hardware router
    var sampleRate: Double { get }
    
    /// Maximum buffer frame count per audio block
    var maxFrames: Int { get }
    
    /// Process an incoming block of interleaved or deinterleaved stereo samples.
    /// Returns false if the client could not process the block, signaling
    /// the driver to fallback to transparent hardware passthrough.
    func processAudio(
        leftChannel: UnsafeMutablePointer<Float>,
        rightChannel: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Bool
}
```

### Registration Lifecycle
1. The client pipeline registers with `AudioRouterBackend.shared.registerClient(self)`.
2. The router queries the active CoreAudio hardware sample rate and buffer frame size, then invokes `client.configure(sampleRate:bufferSize:)`.
3. When the router's IO callback fires:
   - If a client is registered and active, audio samples are passed to `client.processAudio(...)`.
   - If the client returns `false` or drops frames, the router transparently forwards input audio to output hardware to maintain continuous system playback.
4. On client termination, `unregisterClient(self)` restores direct hardware passthrough.
