# CoreAudio & Routing

The `DynaQAudioDriver` module interfaces directly with the macOS CoreAudio Hardware Abstraction Layer (HAL) and the AudioUnit framework (`AUHAL`).

---

## Hardware I/O Integration

CoreAudio manages audio hardware as distinct `AudioDeviceID` endpoints. dynaQ enumerates all active audio devices, interrogates their sample rate capabilities, stream formats, and buffer constraints:

```swift
let devices = CoreAudioManager.shared.fetchAllDevices()
```

Each enumerated device provides:
- **Device UID & Name**: Hardware model, manufacturer, and unique device identifier.
- **Direction**: Input, Output, or Duplex (In/Out).
- **Nominal Sample Rates**: Available clock frequencies (44.1 kHz, 48.0 kHz, 96.0 kHz, etc.).
- **Buffer Frame Size Range**: Minimum, maximum, and current buffer frame count.
- **Hardware Latencies**: Input/output driver latency plus driver safety offset values reported by CoreAudio HAL.

---

## Capture Mechanisms

dynaQ supports two primary capture pathways for acquiring system audio:

### 1. Native macOS 14.2+ Process Tap (`CATapDescription`)
On macOS Sonoma (14.2) and newer, dynaQ creates a system-wide audio tap using CoreAudio's user-space tap APIs:
- Captures audio rendered by running processes without requiring kernel extensions or virtual audio drivers.
- Automatically handles process lifecycle changes and dynamic audio re-routing.
- Requires standard macOS user-space audio entitlements.

### 2. Virtual HAL Audio Driver & Loopback
For environments requiring kernel/HAL-level isolation, dynaQ integrates with virtual HAL audio loopback drivers (such as the dynaQ HAL driver or BlackHole):
- The virtual audio device is designated as the system's default output.
- The dynaQ routing backend reads audio frames from the virtual input stream.
- Audio is equalized and forwarded directly to the physical output hardware (USB DAC, headphones, monitors).

---

## Roundtrip Latency Calculation

Accurate latency estimation is calculated directly from CoreAudio hardware parameters:

$$\text{Latency}_{\text{roundtrip}} = \frac{F_{\text{in\_buf}} + F_{\text{in\_hw}} + F_{\text{in\_safety}} + F_{\text{out\_buf}} + F_{\text{out\_hw}} + F_{\text{out\_safety}}}{f_s} \times 1000 \text{ ms}$$

Where:
- $F_{\text{in\_buf}}, F_{\text{out\_buf}}$: Software buffer frame size (e.g. 64, 128, 256 samples).
- $F_{\text{in\_hw}}, F_{\text{out\_hw}}$: Fixed hardware DAC/ADC latency reported by `kAudioDevicePropertyLatency`.
- $F_{\text{in\_safety}}, F_{\text{out\_safety}}$: Safety buffer offset reported by `kAudioDevicePropertySafetyOffset`.
- $f_s$: Active hardware sample rate in Hertz.

### Typical Latency Profile (48 kHz Sample Rate)

| Buffer Size | Software Frames | Latency at 48 kHz | Use Case |
| :--- | :--- | :--- | :--- |
| **64 samples** | 1.33 ms | ~2.8 ms roundtrip | Real-time monitoring, live tracking |
| **128 samples** | 2.67 ms | ~5.4 ms roundtrip | Studio mastering, interactive EQ |
| **256 samples** | 5.33 ms | ~10.8 ms roundtrip | Standard balanced desktop playback |
| **512 samples** | 10.67 ms | ~21.5 ms roundtrip | Low CPU overhead, background media |

---

## Acoustic Feedback Guard

When routing hardware input directly to hardware output, an acoustic feedback loop can occur if an open microphone is routed to an unattenuated loudspeaker in the same physical space.

dynaQ includes an intelligent feedback prevention check:
1. When input capture is enabled, the driver checks the transport type of both input and output endpoints.
2. If the input device is identified as `Built-in Microphone` and the output device is identified as `Built-in Speakers`, dynaQ automatically engages feedback protection:
   - The user is warned via telemetry status.
   - The capture loop is muted until headphones or an external USB audio interface is connected.
