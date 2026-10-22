"""dynaQ Python Backend Server.

Operates as a lightweight IPC bridge and background daemon for acoustic automation,
Python scripted control, and headless telemetry streaming.
"""

import json
import os
import signal
import socket
import sys
import threading
import time
from typing import Any, Dict

from .dsp import HARMAN_OVER_EAR, interpolate_curve
from .rust_bridge import RustBridge


class DynaQBackendServer:
    """IPC Server for dynaQ Python Backend."""

    def __init__(self, socket_path: str = "/tmp/dynaq_ipc.sock", tcp_port: int = 9876):
        self.socket_path = socket_path
        self.tcp_port = tcp_port
        self.running = False
        self._server_sock: socket.socket = None
        self._threads = []

        # Virtual DSP State (when operating standalone)
        self.sample_rate = 48000.0
        self.buffer_size = 256
        self.latency_ms = 5.33
        self.master_gain_db = 0.0
        self.limiter_ceiling_db = -0.5
        self.limiter_enabled = True
        self.bands = [
            {"index": i, "frequency": f, "gain": 0.0, "q": 1.414, "type": "Bell", "enabled": True}
            for i, f in enumerate([60.0, 150.0, 400.0, 1000.0, 2500.0, 6000.0, 12000.0, 16000.0])
        ]

    def start(self) -> None:
        """Starts socket server on Unix Domain Socket and TCP loopback."""
        self.running = True

        # Clean old socket file
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

        try:
            unix_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            unix_sock.bind(self.socket_path)
            unix_sock.listen(5)
            unix_sock.settimeout(0.5)
            t_unix = threading.Thread(target=self._listen_loop, args=(unix_sock,), daemon=True)
            t_unix.start()
            self._threads.append(t_unix)
        except Exception as e:
            print(f"// [WARN] Could not bind Unix socket: {e}")

        try:
            tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            tcp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            tcp_sock.bind(("127.0.0.1", self.tcp_port))
            tcp_sock.listen(5)
            tcp_sock.settimeout(0.5)
            t_tcp = threading.Thread(target=self._listen_loop, args=(tcp_sock,), daemon=True)
            t_tcp.start()
            self._threads.append(t_tcp)
        except Exception as e:
            print(f"// [WARN] Could not bind TCP socket: {e}")

        print("┌──────────────────────────────────────────────┐")
        print("│  DYNAQ PYTHON BACKEND SERVER (ONLINE)        │")
        print("│  IPC Socket : {:<30} │".format(self.socket_path))
        print("│  TCP Port   : {:<30} │".format(f"127.0.0.1:{self.tcp_port}"))
        print("│  Rust Engine: {:<30} │".format(RustBridge.get().version()[:30]))
        print("└──────────────────────────────────────────────┘")

    def _listen_loop(self, s: socket.socket) -> None:
        while self.running:
            try:
                conn, _ = s.accept()
                client_thread = threading.Thread(target=self._handle_client, args=(conn,), daemon=True)
                client_thread.start()
            except socket.timeout:
                continue
            except Exception:
                break
        try:
            s.close()
        except Exception:
            pass

    def _handle_client(self, conn: socket.socket) -> None:
        conn.settimeout(5.0)
        buffer = b""
        try:
            while self.running:
                data = conn.recv(4096)
                if not data:
                    break
                buffer += data
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        req = json.loads(line.decode("utf-8"))
                        resp = self.dispatch(req)
                    except Exception as err:
                        resp = {"status": "error", "message": str(err)}

                    resp_bytes = (json.dumps(resp) + "\n").encode("utf-8")
                    conn.sendall(resp_bytes)
        except Exception:
            pass
        finally:
            conn.close()

    def dispatch(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches RPC commands."""
        cmd = req.get("cmd")

        if cmd == "ping":
            return {"status": "ok", "version": "1.0.0-beta.2", "rust": RustBridge.get().is_available}

        elif cmd == "get_status":
            return {
                "status": "online",
                "sample_rate": self.sample_rate,
                "buffer_frames": self.buffer_size,
                "latency_ms": self.latency_ms,
                "capture_source": "systemAudio",
                "master_gain_db": self.master_gain_db,
                "limiter": {
                    "enabled": self.limiter_enabled,
                    "ceiling_db": self.limiter_ceiling_db,
                },
                "bands": self.bands,
            }

        elif cmd == "get_telemetry":
            return {
                "status": "ok",
                "peak_left_db": -12.4,
                "peak_right_db": -12.1,
                "lufs_integrated": -14.2,
                "lufs_momentary": -13.8,
                "correlation": 0.94,
                "spectrum_64": [round(-60.0 + (i % 16) * 2.5, 1) for i in range(64)],
            }

        elif cmd == "set_band":
            idx = int(req.get("index", 0))
            if 0 <= idx < len(self.bands):
                if "frequency" in req:
                    self.bands[idx]["frequency"] = float(req["frequency"])
                if "gain" in req:
                    self.bands[idx]["gain"] = float(req["gain"])
                if "q" in req:
                    self.bands[idx]["q"] = float(req["q"])
                if "filter_type" in req:
                    self.bands[idx]["type"] = str(req["filter_type"])
                if "is_enabled" in req:
                    self.bands[idx]["enabled"] = bool(req["is_enabled"])
                return {"status": "ok", "band": self.bands[idx]}
            return {"status": "error", "message": f"Invalid band index {idx}"}

        elif cmd == "set_master_gain":
            self.master_gain_db = float(req.get("gain_db", 0.0))
            return {"status": "ok", "master_gain_db": self.master_gain_db}

        elif cmd == "set_limiter":
            self.limiter_ceiling_db = float(req.get("ceiling_db", -0.5))
            self.limiter_enabled = bool(req.get("is_enabled", True))
            return {
                "status": "ok",
                "ceiling_db": self.limiter_ceiling_db,
                "enabled": self.limiter_enabled,
            }

        return {"status": "error", "message": f"Unknown command '{cmd}'"}

    def stop(self) -> None:
        """Stops the backend server cleanly."""
        self.running = False
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass


def main():
    server = DynaQBackendServer()
    server.start()

    def handle_sig(sig, frame):
        print("\n// [SHUTTING DOWN PYTHON BACKEND]")
        server.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)

    while True:
        time.sleep(1.0)


if __name__ == "__main__":
    main()

