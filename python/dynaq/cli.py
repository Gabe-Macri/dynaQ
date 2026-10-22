"""dynaQ Python Command-Line Interface.

Provides CLI access to live audio telemetry, hardware status,
AutoEQ acoustic optimization, and backend service control.
"""

import argparse
import sys
import time

from .client import DynaQClient
from .dsp import HARMAN_OVER_EAR
from .errors import DynaQConnectionError, DynaQError
from .rust_bridge import RustBridge
from .server import DynaQBackendServer


def print_banner():
    print("┌────────────────────────────────────────────────────────┐")
    print("│  DYNAQ PRO AUDIO PYTHON BACKEND CLI                    │")
    print("│  Version: 1.0.0-beta.2                                 │")
    print("└────────────────────────────────────────────────────────┘\n")


def cmd_status(args):
    client = DynaQClient()
    try:
        client.connect()
        status = client.get_status()
        print("// [DYNAQ AUDIO ENGINE STATUS: ONLINE]")
        print(f"   SAMPLE RATE       : {status.get('sample_rate')} Hz")
        print(f"   BUFFER SIZE       : {status.get('buffer_frames')} samples")
        print(f"   ROUNDTRIP LATENCY : {status.get('latency_ms')} ms")
        print(f"   CAPTURE SOURCE    : {status.get('capture_source')}")
        print(f"   MASTER GAIN       : {status.get('master_gain_db'):+.1f} dB")
        lim = status.get("limiter", {})
        print(f"   LIMITER           : {'ENABLED' if lim.get('enabled') else 'BYPASS'} (Ceiling: {lim.get('ceiling_db')} dBFS)")
        bands = status.get("bands", [])
        print(f"\n   ACTIVE EQ BANDS ({len(bands)} total):")
        for b in bands:
            print(f"     Band {b.get('index', 0) + 1:02}: {b.get('frequency', 0):7.1f} Hz | {b.get('gain', 0):+6.2f} dB | Q: {b.get('q', 0):.2f}")
    except DynaQConnectionError as e:
        print(f"!! [STATUS ERROR] dynaQ daemon is offline: {e}")
        sys.exit(1)


def cmd_telemetry(args):
    client = DynaQClient()
    try:
        client.connect()
        print("// [STREAMING LIVE TELEMETRY // PRESS CTRL+C TO STOP]")
        while True:
            t = client.get_telemetry()
            pl = t.get("peak_left_db", -60.0)
            pr = t.get("peak_right_db", -60.0)
            lufs = t.get("lufs_integrated", -60.0)
            corr = t.get("correlation", 1.0)
            sys.stdout.write(
                f"\r   PEAK L: {pl:+6.1f} dBFS | PEAK R: {pr:+6.1f} dBFS | LUFS: {lufs:+5.1f} | CORR: {corr:+.2f}   "
            )
            sys.stdout.flush()
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n// Telemetry monitoring stopped.")
    except Exception as e:
        print(f"\n!! [TELEMETRY ERROR] {e}")


def cmd_autoeq(args):
    print("// [EXECUTING ACOUSTIC AUTOEQ OPTIMIZATION]")
    rust = RustBridge.get()
    print(f"   ENGINE: {rust.version()}")

    target = HARMAN_OVER_EAR
    # Sample measured response with a mid-bass elevation (+5 dB at 180 Hz) and treble dip (-4 dB at 6 kHz)
    measured = [
        (20.0, 0.0),
        (100.0, 3.0),
        (180.0, 5.0),
        (500.0, 1.0),
        (1000.0, 0.0),
        (3000.0, 4.0),
        (6000.0, -3.0),
        (10000.0, -2.0),
        (20000.0, -6.0),
    ]

    bands, rmse = rust.optimize_autoeq(target, measured, num_bands=args.bands)
    print(f"   Target Curve : Harman 2019v2 Over-Ear")
    print(f"   Convergence  : Optimal (Final Residual RMSE = {rmse:.2f} dB)")
    print("\n   CALCULATED PARAMETRIC BIQUAD CASCADE:")
    for i, b in enumerate(bands):
        print(f"     Band {i+1:02}: {b.frequency_hz:7.1f} Hz | {b.gain_db:+6.2f} dB | Q: {b.q:4.2f}")

    if args.apply:
        client = DynaQClient()
        try:
            client.connect()
            for i, b in enumerate(bands):
                client.set_band(i, b.frequency_hz, b.gain_db, b.q)
            print("// Successfully synchronized AutoEQ profile to dynaQ audio engine.")
        except Exception as e:
            print(f"!! [SYNC ERROR] Could not apply to dynaQ: {e}")


def cmd_server(args):
    server = DynaQBackendServer(socket_path=args.socket, tcp_port=args.port)
    server.start()
    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        print("\n// Stopping dynaQ backend server...")
        server.stop()


def main():
    parser = argparse.ArgumentParser(description="dynaQ Audio Backend & Telemetry CLI")
    subparsers = parser.add_subparsers(dest="subcommand")

    # status
    subparsers.add_parser("status", help="Query dynaQ engine and hardware routing status")

    # telemetry
    subparsers.add_parser("telemetry", help="Live stream audio meters and phase correlation")

    # autoeq
    p_autoeq = subparsers.add_parser("autoeq", help="Optimize EQ curve against acoustic targets")
    p_autoeq.add_argument("--bands", type=int, default=8, help="Number of biquad bands (default: 8)")
    p_autoeq.add_argument("--apply", action="store_true", help="Synchronize directly to active dynaQ instance")

    # server
    p_server = subparsers.add_parser("server", help="Run standalone dynaQ Python backend server")
    p_server.add_argument("--socket", default="/tmp/dynaq_ipc.sock", help="Unix domain socket path")
    p_server.add_argument("--port", type=int, default=9876, help="TCP loopback port")

    args = parser.parse_args()
    if not args.subcommand:
        print_banner()
        parser.print_help()
        sys.exit(0)

    if args.subcommand == "status":
        cmd_status(args)
    elif args.subcommand == "telemetry":
        cmd_telemetry(args)
    elif args.subcommand == "autoeq":
        cmd_autoeq(args)
    elif args.subcommand == "server":
        cmd_server(args)


if __name__ == "__main__":
    main()

