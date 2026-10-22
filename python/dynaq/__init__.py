"""dynaQ Pro Audio Python SDK and Backend Package.

High-performance acoustic optimization, real-time CoreAudio telemetry streaming,
and Rust-accelerated DSP bridging.
"""

from .client import DynaQClient
from .dsp import DIFFUSE_FIELD, HARMAN_IN_EAR, HARMAN_OVER_EAR, STUDIO_FLAT, interpolate_curve
from .errors import (
    DynaQConnectionError,
    DynaQDSPError,
    DynaQError,
    DynaQOptimizationError,
    DynaQProtocolError,
)
from .rust_bridge import AutoEqBand, CurvePoint, RustBridge
from .server import DynaQBackendServer

__version__ = "1.0.0-beta.2"
__all__ = [
    "DynaQClient",
    "DynaQBackendServer",
    "RustBridge",
    "AutoEqBand",
    "CurvePoint",
    "HARMAN_OVER_EAR",
    "HARMAN_IN_EAR",
    "DIFFUSE_FIELD",
    "STUDIO_FLAT",
    "interpolate_curve",
    "DynaQError",
    "DynaQConnectionError",
    "DynaQProtocolError",
    "DynaQDSPError",
    "DynaQOptimizationError",
]

