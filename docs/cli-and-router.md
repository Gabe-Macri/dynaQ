# Router Daemon & CLI

dynaQ provides modular command-line utilities and headless daemon services alongside the graphical desktop application.

---

## Standalone Router Daemon

`dynaQ-router` is a headless background process that connects CoreAudio hardware streams and manages real-time buffer exchange with negligible system overhead.

### Running the Daemon

```bash
swift run dynaQ-router
```

Or from the built release binary:

```bash
./.build/release/dynaQ-router
```

### Execution Characteristics
- **Transparent Passthrough**: Consumes ~0.0% CPU when routing audio directly across physical endpoints.
- **Process Signal Handling**: Intercepts `SIGINT` (Ctrl+C) and `SIGTERM` to safely stop CoreAudio IO units, flush circular buffers, and release device locks.
- **Console Telemetry**: Prints stream status, negotiated hardware sample rates, buffer sizes, and live roundtrip latency.

### Example Console Output

```
┌─────────────────────────────┐
│  DYNAQ AUDIO ROUTER BACKEND │
└─────────────────────────────┘
// [ROUTER BACKEND INITIALIZING]
   COREAUDIO CAPTURE : System Process Tap (macOS 14.2+)
   OUTPUT HARDWARE   : External USB DAC (ID: 72)
   SAMPLE RATE       : 48000 Hz
   BUFFER FRAME SIZE : 128 samples
   ROUNDTRIP LATENCY : 3.42 ms [OPTIMAL]
// [ROUTER STATUS: ONLINE // ROUTING ACTIVE // PASSTHROUGH READY]
// Running in ultra-lightweight mode (~0.0% CPU). Press Ctrl+C to terminate.
```

---

## Rust SIMD Optimization Engine (`dynaq-opt`)

`dynaq-opt` is a native Rust CLI utility utilizing SIMD vectorization for sub-millisecond AutoEQ target curve optimization and FIR filter design.

### Usage

```bash
dynaq-opt [options]
```

### Options

| Flag | Parameter | Description |
| :--- | :--- | :--- |
| `-t`, `--target` | `<string>` | Target curve profile (`harman`, `diffuse_field`, `free_field`, or path to CSV). |
| `-m`, `--measured` | `<path>` | Path to measured headphone or room frequency response CSV file. |
| `-o`, `--output` | `<path>` | Output path for calculated biquad JSON profile. |
| `-b`, `--bands` | `<int>` | Maximum number of parametric biquad bands to allocate (default: 8). |
| `-i`, `--max-iter` | `<int>` | Optimizer iteration ceiling (default: 1000). |
| `-h`, `--help` | — | Display CLI help reference and exit. |

### Example Optimization Run

```bash
./dist/dynaq-opt --target harman --measured measurement.csv --bands 10 --output calibrated_profile.json
```

```
[DYNAQ-OPT] Loading measured curve: measurement.csv (512 points)
[DYNAQ-OPT] Target curve selected: Harman In-Ear 2019
[DYNAQ-OPT] Initial RMSE: 4.82 dB
[DYNAQ-OPT] Optimizing 10 parametric biquad bands via SIMD SSE/NEON...
[DYNAQ-OPT] Optimization converged in 12.4 ms (284 iterations)
[DYNAQ-OPT] Final RMSE: 0.38 dB (-4.44 dB error reduction)
[DYNAQ-OPT] Profile exported to calibrated_profile.json
```

---

## Python Backend SDK and IPC Bridge

The Python package (`python/dynaq`) provides programmatic control over the dynaQ DSP engine via a high-performance Unix domain socket (`/tmp/dynaq_ipc.sock`) or TCP (port 9879).

### Architecture

```
+---------------------------+       Unix Domain Socket       +---------------------------+
|    Python Client / SDK    | <----------------------------> |       dynaQ Backend       |
|   (JSON-RPC 2.0 Client)   |      /tmp/dynaq_ipc.sock       |  (Real-Time Engine Daemon)|
+---------------------------+                                +---------------------------+
```

### JSON-RPC 2.0 Command Reference

| Method | Parameters | Return Value | Description |
| :--- | :--- | :--- | :--- |
| `get_profile` | None | `ProfileObject` | Retrieves all active biquad bands and gain parameters. |
| `set_band` | `id, freq, gain, q, type` | `bool` | Atomically updates a specific EQ band's parameters. |
| `set_limiter_mode` | `live: bool` | `bool` | Toggles True Peak Limiter between Live and Mastering mode. |
| `query_telemetry` | None | `TelemetryObject` | Returns instantaneous Peak, RMS, and LUFS readings. |

### Example Python Script

```python
from dynaq.client import DynaQClient

client = DynaQClient(socket_path="/tmp/dynaq_ipc.sock")
client.connect()

# Set Band 2 to 250 Hz peaking filter, -2.5 dB gain, Q=1.4
client.set_band(band_id=2, frequency=250.0, gain_db=-2.5, q=1.4, filter_type="bell")

# Query real-time loudness metrics
telemetry = client.query_telemetry()
print(f"Momentary LUFS: {telemetry.momentary_lufs:.1f} | Peak: {telemetry.peak_dbfs:.1f} dBFS")

client.close()
```

---

## Command-Line Reference

The main `dynaQ` application executable supports operational and diagnostic flags:

```bash
dynaQ [options]
```

### Available Options

| Flag | Description |
| :--- | :--- |
| `--gui` | Launches the graphical user interface and menu bar status item (default behavior). |
| `--list-devices` | Enumerates all connected CoreAudio hardware devices with sample rates, buffer sizes, and latencies. |
| `--driver-status` | Inspects system driver status, user-space tap support, and HAL driver installations. |
| `-h`, `--help` | Prints CLI usage reference and exits. |

### Device Enumeration Output (`--list-devices`)

```bash
swift run dynaQ --list-devices
```

```
Enumerating CoreAudio hardware devices...

--------------------------------------------------------------------------------
ID   | DIR    | RATE     | BUFFER   | LATENCY  | NAME
--------------------------------------------------------------------------------
42   | INPUT  | 48000 Hz |  256 spl | 5.3 ms   | MacBook Pro Microphone [DEFAULT IN]
57   | OUTPUT | 48000 Hz |  128 spl | 3.2 ms   | External Headphones [DEFAULT OUT]
81   | IN/OUT | 96000 Hz |   64 spl | 1.8 ms   | Universal Audio Apollo Twin
--------------------------------------------------------------------------------
```

### Driver Status Output (`--driver-status`)

```bash
swift run dynaQ --driver-status
```

```
dynaQ Audio Routing Status:
• Native CoreAudio System Tap: Fully supported & active (macOS 14.2+)
• Virtual HAL Driver: /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver (Active)
```
