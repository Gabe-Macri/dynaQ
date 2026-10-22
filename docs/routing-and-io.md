# CoreAudio & Routing

The `DynaQAudioDriver` module interfaces directly with the macOS CoreAudio Hardware Abstraction Layer (HAL) and the AudioUnit framework (`AUHAL`).

---

## Hardware I/O Integration

CoreAudio manages audio hardware as distinct `AudioDeviceID` endpoints. dynaQ enumerates all active audio devices, interrogating their sample rate capabilities, stream formats, and buffer constraints:

```swift
let devices = CoreAudioManager.shared.fetchAllDevices()
```

Each enumerated device provides:
- **Device UID & Name**: Model, manufacturer, and unique device identifier.
- **Direction**: Input, Output, or Duplex.
- **Nominal Sample Rates**: Available clock frequencies (44.1 kHz, 48.0 kHz, 96.0 kHz, etc.).
- **Buffer Frame Size Range**: Minimum, maximum, and default buffer frame counts.
- **Hardware Latencies**: Input/output driver latency plus driver safety offset values reported by CoreAudio HAL.

---

## Capture Mechanisms

dynaQ supports two primary capture pathways:

### 1. Native macOS 14.2+ Process Tap (`CATapDescription`)
On macOS Sonoma (14.2) and newer, dynaQ creates a system-wide audio tap using CoreAudio's user-space tap APIs:
- Captures audio rendered by running processes without kernel extensions.
- Dynamically adapts to process lifecycle events.
- Requires standard macOS user-space audio entitlements.

### 2. Virtual HAL Audio Driver & Loopback (`DynaQDriver.driver`)
For environments requiring HAL-level isolation or older macOS compatibility:
- The virtual audio device is designated as the system's default output.
- The dynaQ routing backend reads audio frames from the virtual input stream.
- Audio is equalized and forwarded directly to physical output hardware (USB DAC, headphones, monitors).

---

## Dynamic Sample Rate Switching

When output hardware changes its clock frequency (e.g. AirPods switching between 96 kHz for media playback and 48 kHz for voice calls):
1. CoreAudio triggers a `kAudioDevicePropertyNominalSampleRate` property listener.
2. The router backend halts active render cycles and reads the new hardware sample rate $f_s$.
3. All internal biquad filter coefficients and envelope ballistics are recalculated for the new $f_s$.
4. Input and output SPSC ring buffers are purged to eliminate stale audio frames, preventing audible pitch-warping or buffer misalignment.
5. Real-time audio streaming resumes seamlessly within $< 5\text{ ms}$.

---

## Auto-Routing on Startup

To eliminate manual routing setup on launch:
1. `CoreAudioManager` attaches a property listener to `kAudioHardwarePropertyProcessObjectList`.
2. Hardware changes and process taps are initialized asynchronously on a background dispatch queue to keep the user interface responsive.
3. If a valid default output device is identified, the routing backend automatically engages capture and passthrough/equalization.

---

## Roundtrip Latency Calculation

Accurate roundtrip latency is calculated directly from CoreAudio hardware parameters:

$$\text{Latency}_{\text{roundtrip}} = \frac{F_{\text{in\_buf}} + F_{\text{in\_hw}} + F_{\text{in\_safety}} + F_{\text{out\_buf}} + F_{\text{out\_hw}} + F_{\text{out\_safety}}}{f_s} \times 1000 \text{ ms}$$

### Latency Profiles at 48 kHz

| Buffer Size | Software Time | Hardware Roundtrip | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **64 samples** | 1.33 ms | $\sim 2.8\text{ ms}$ | Real-time monitoring, live tracking |
| **128 samples** | 2.67 ms | $\sim 5.4\text{ ms}$ | Studio mastering, interactive EQ |
| **256 samples** | 5.33 ms | $\sim 10.8\text{ ms}$ | Standard desktop playback |
| **512 samples** | 10.67 ms | $\sim 21.5\text{ ms}$ | Low-power background media |

---

## Acoustic Feedback Guard

When routing hardware input directly to hardware output, open microphones can cause acoustic feedback loops.

dynaQ includes an automated feedback prevention check:
1. When input capture is engaged, the driver inspects device transport types.
2. If input is identified as `Built-in Microphone` and output is `Built-in Speakers`, dynaQ automatically activates protection:
   - Capture loop is muted.
   - Status telemetry warns the user.
   - Protection releases automatically once headphones or an external USB audio interface is connected.
