# Router Daemon & CLI

dynaQ provides two separate executables: the full graphical application (`dynaQ`) and the standalone ultra-lightweight routing daemon (`dynaQ-router`).

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
- **Passthrough Mode**: Consumes ~0.0% CPU when routing audio directly across physical endpoints.
- **Process Signals**: Intercepts `SIGINT` (Ctrl+C) and `SIGTERM` to safely stop CoreAudio IO units, flush circular buffers, and release device locks.
- **Console Telemetry**: Prints stream status, negotiated hardware sample rates, buffer sizes, and live roundtrip latency.

### Example Terminal Output

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

## Command-Line Reference

The main `dynaQ` executable supports several diagnostic and operational flags:

```bash
dynaQ [options]
```

### Available Options

| Flag | Description |
| :--- | :--- |
| `--gui` | Launches the graphical user interface and menu bar app (default behavior). |
| `--list-devices` | Enumerates all connected CoreAudio hardware devices with sample rates, buffer sizes, and latencies. |
| `--driver-status` | Inspects system driver status, user-space tap support, and HAL driver installations. |
| `-h`, `--help` | Prints CLI usage reference and exits. |

---

## Diagnostic Examples

### Device Enumeration (`--list-devices`)

```bash
swift run dynaQ --list-devices
```

Output:

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

### Driver Status Check (`--driver-status`)

```bash
swift run dynaQ --driver-status
```

Output:

```
dynaQ Audio Routing Status:
• Native CoreAudio System Tap: Fully supported & active
• Virtual HAL Driver: Not Installed (Using Native User-Space Tap)
```
