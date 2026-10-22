"""dynaQ IPC Client.

Connects to the native dynaQ router / CoreAudio HAL daemon via Unix Domain Socket
(/tmp/dynaq_ipc.sock) or TCP fallback (127.0.0.1:9876).
Enables programmatic real-time telemetry inspection, EQ control, and AutoEQ profile synchronization.
"""

import json
import os
import socket
from typing import Any, Dict, List, Optional, Tuple, Union

from .errors import DynaQConnectionError, DynaQProtocolError
from .rust_bridge import RustBridge


class DynaQClient:
    """Client for controlling and monitoring the dynaQ audio system."""

    DEFAULT_SOCKET_PATH = "/tmp/dynaq_ipc.sock"
    DEFAULT_TCP_HOST = "127.0.0.1"
    DEFAULT_TCP_PORT = 9876

    def __init__(
        self,
        socket_path: str = DEFAULT_SOCKET_PATH,
        tcp_host: Optional[str] = None,
        tcp_port: int = DEFAULT_TCP_PORT,
        timeout: float = 2.0,
    ):
        self.socket_path = socket_path
        self.tcp_host = tcp_host
        self.tcp_port = tcp_port
        self.timeout = timeout
        self._sock: Optional[socket.socket] = None

    def connect(self) -> None:
        """Establishes connection to dynaQ IPC endpoint."""
        self.close()

        # Try Unix Domain Socket first
        if not self.tcp_host and os.path.exists(self.socket_path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(self.timeout)
                s.connect(self.socket_path)
                self._sock = s
                return
            except Exception:
                try:
                    s.close()
                except Exception:
                    pass

        # Fallback to TCP loopback socket
        host = self.tcp_host or self.DEFAULT_TCP_HOST
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(self.timeout)
            s.connect((host, self.tcp_port))
            self._sock = s
        except Exception as e:
            raise DynaQConnectionError(
                f"Failed to connect to dynaQ IPC at {self.socket_path} or {host}:{self.tcp_port}: {e}"
            )

    def close(self) -> None:
        """Closes IPC socket."""
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None

    def __enter__(self) -> "DynaQClient":
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def send_command(self, cmd: str, **kwargs) -> Dict[str, Any]:
        """Sends a JSON-RPC formatted command and waits for response."""
        if not self._sock:
            self.connect()

        payload = {"cmd": cmd, **kwargs}
        req_bytes = (json.dumps(payload) + "\n").encode("utf-8")

        try:
            self._sock.sendall(req_bytes)
            data = b""
            while not data.endswith(b"\n"):
                chunk = self._sock.recv(4096)
                if not chunk:
                    break
                data += chunk

            if not data:
                raise DynaQProtocolError("Empty response from dynaQ daemon")

            resp = json.loads(data.decode("utf-8").strip())
            if resp.get("status") == "error":
                raise DynaQProtocolError(resp.get("message", "Unknown daemon error"))
            return resp
        except (socket.error, json.JSONDecodeError) as e:
            self.close()
            raise DynaQProtocolError(f"IPC transaction failed: {e}")

    def ping(self) -> bool:
        """Pings dynaQ daemon."""
        try:
            resp = self.send_command("ping")
            return resp.get("status") == "ok"
        except Exception:
            return False

    def get_status(self) -> Dict[str, Any]:
        """Fetches active hardware device, sample rate, buffer size, and roundtrip latency."""
        return self.send_command("get_status")

    def get_telemetry(self) -> Dict[str, Any]:
        """Fetches real-time metering (peak L/R, LUFS, phase correlation, and 64-bin FFT spectrum)."""
        return self.send_command("get_telemetry")

    def set_band(
        self,
        index: int,
        frequency: float,
        gain: float,
        q: float = 1.414,
        filter_type: str = "Bell",
        is_enabled: bool = True,
    ) -> bool:
        """Modifies a parametric EQ band in real time."""
        resp = self.send_command(
            "set_band",
            index=index,
            frequency=frequency,
            gain=gain,
            q=q,
            filter_type=filter_type,
            is_enabled=is_enabled,
        )
        return resp.get("status") == "ok"

    def set_master_gain(self, gain_db: float) -> bool:
        """Adjusts master output trim (-24.0 to +12.0 dB)."""
        resp = self.send_command("set_master_gain", gain_db=gain_db)
        return resp.get("status") == "ok"

    def set_limiter(self, ceiling_db: float, is_enabled: bool = True) -> bool:
        """Configures lookahead true peak brickwall limiter."""
        resp = self.send_command("set_limiter", ceiling_db=ceiling_db, is_enabled=is_enabled)
        return resp.get("status") == "ok"

    def apply_autoeq(
        self,
        target_curve: List[Tuple[float, float]],
        measured_curve: List[Tuple[float, float]],
        num_bands: int = 8,
        sample_rate: float = 48000.0,
    ) -> Dict[str, Any]:
        """Calculates optimal parametric EQ bands via the Rust optimization engine and applies them to dynaQ."""
        rust = RustBridge.get()
        bands, rmse = rust.optimize_autoeq(target_curve, measured_curve, num_bands, sample_rate)

        # Apply bands to connected dynaQ instance
        for i, band in enumerate(bands):
            self.set_band(
                index=i,
                frequency=band.frequency_hz,
                gain=band.gain_db,
                q=band.q,
                filter_type="Bell",
                is_enabled=True,
            )

        return {
            "status": "ok",
            "rmse_db": rmse,
            "bands": [
                {
                    "index": i,
                    "frequency": b.frequency_hz,
                    "gain": b.gain_db,
                    "q": b.q,
                }
                for i, b in enumerate(bands)
            ],
        }
