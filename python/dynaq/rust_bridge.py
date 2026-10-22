"""dynaQ Rust C-ABI Bridge.

Binds the high-performance compiled Rust audio optimization engine via ctypes.
Enables microsecond AutoEQ curve fitting, Blackman windowed FIR generation,
and 4x oversampled true peak calculation.
"""

import ctypes
import os
import sys
from dataclasses import dataclass
from typing import List, Optional, Tuple

from .errors import DynaQDSPError, DynaQOptimizationError


@dataclass
class AutoEqBand:
    frequency_hz: float
    gain_db: float
    q: float
    filter_type: int  # 0: Bell, 1: LowShelf, 2: HighShelf


@dataclass
class CurvePoint:
    freq_hz: float
    db: float


@dataclass
class BiquadCoeffs:
    b0: float
    b1: float
    b2: float
    a1: float
    a2: float


# C Structure Definitions
class _CCurvePoint(ctypes.Structure):
    _fields_ = [("freq_hz", ctypes.c_double), ("db", ctypes.c_double)]


class _CAutoEqBand(ctypes.Structure):
    _fields_ = [
        ("frequency_hz", ctypes.c_double),
        ("gain_db", ctypes.c_double),
        ("q", ctypes.c_double),
        ("filter_type", ctypes.c_int32),
    ]


class _CBiquadCoeffs(ctypes.Structure):
    _fields_ = [
        ("b0", ctypes.c_double),
        ("b1", ctypes.c_double),
        ("b2", ctypes.c_double),
        ("a1", ctypes.c_double),
        ("a2", ctypes.c_double),
    ]


def _find_rust_dylib() -> Optional[str]:
    # 1. Environment variable
    env_path = os.environ.get("DYNAQ_RUST_LIB")
    if env_path and os.path.isfile(env_path):
        return env_path

    # 2. Workspace native target
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    candidate = os.path.join(base_dir, "native", "dynaq-rust", "target", "release", "libdynaq_rust.dylib")
    if os.path.isfile(candidate):
        return candidate

    # 3. App bundle Frameworks
    app_candidate = "/Applications/dynaQ.app/Contents/Frameworks/libdynaq_rust.dylib"
    if os.path.isfile(app_candidate):
        return app_candidate

    # 4. Standard /usr/local/lib
    sys_candidate = "/usr/local/lib/libdynaq_rust.dylib"
    if os.path.isfile(sys_candidate):
        return sys_candidate

    return None


class RustBridge:
    """Singleton wrapper for the libdynaq_rust native dynamic library."""

    _instance: Optional["RustBridge"] = None

    def __init__(self, lib_path: Optional[str] = None):
        target_path = lib_path or _find_rust_dylib()
        self.is_available = False
        self._lib = None

        if target_path and os.path.isfile(target_path):
            try:
                self._lib = ctypes.CDLL(target_path)
                self._setup_function_signatures()
                self.is_available = True
                self.lib_path = target_path
            except Exception as e:
                self.is_available = False
                self.lib_path = None
        else:
            self.lib_path = None

    def _setup_function_signatures(self):
        lib = self._lib
        # dynaq_rust_version() -> *const c_char
        lib.dynaq_rust_version.restype = ctypes.c_char_p
        lib.dynaq_rust_version.argtypes = []

        # dynaq_rust_optimize_autoeq(...)
        lib.dynaq_rust_optimize_autoeq.restype = ctypes.c_int
        lib.dynaq_rust_optimize_autoeq.argtypes = [
            ctypes.POINTER(_CCurvePoint),
            ctypes.c_size_t,
            ctypes.POINTER(_CCurvePoint),
            ctypes.c_size_t,
            ctypes.c_size_t,
            ctypes.c_double,
            ctypes.POINTER(_CAutoEqBand),
            ctypes.POINTER(ctypes.c_double),
        ]

        # dynaq_rust_generate_fir(...)
        lib.dynaq_rust_generate_fir.restype = ctypes.c_int
        lib.dynaq_rust_generate_fir.argtypes = [
            ctypes.c_int,
            ctypes.c_size_t,
            ctypes.c_double,
            ctypes.c_double,
            ctypes.POINTER(ctypes.c_double),
        ]

        # dynaq_rust_scan_true_peak(...)
        lib.dynaq_rust_scan_true_peak.restype = ctypes.c_int
        lib.dynaq_rust_scan_true_peak.argtypes = [
            ctypes.POINTER(ctypes.c_float),
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_double),
        ]

        # dynaq_rust_measure_phase_correlation(...)
        lib.dynaq_rust_measure_phase_correlation.restype = ctypes.c_int
        lib.dynaq_rust_measure_phase_correlation.argtypes = [
            ctypes.POINTER(ctypes.c_float),
            ctypes.POINTER(ctypes.c_float),
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_double),
        ]

    @classmethod
    def get(cls) -> "RustBridge":
        if cls._instance is None:
            cls._instance = RustBridge()
        return cls._instance

    def version(self) -> str:
        if not self.is_available:
            return "Unavailable (Pure Python Fallback)"
        res = self._lib.dynaq_rust_version()
        return res.decode("utf-8") if res else "Unknown"

    def optimize_autoeq(
        self,
        target_curve: List[Tuple[float, float]],
        measured_curve: List[Tuple[float, float]],
        num_bands: int = 8,
        sample_rate: float = 48000.0,
    ) -> Tuple[List[AutoEqBand], float]:
        if not self.is_available:
            raise DynaQOptimizationError("Native Rust helper library not loaded")

        t_arr = (_CCurvePoint * len(target_curve))(
            *[_CCurvePoint(freq_hz=f, db=d) for f, d in target_curve]
        )
        m_arr = (_CCurvePoint * len(measured_curve))(
            *[_CCurvePoint(freq_hz=f, db=d) for f, d in measured_curve]
        )
        out_bands = (_CAutoEqBand * num_bands)()
        out_rmse = ctypes.c_double(0.0)

        status = self._lib.dynaq_rust_optimize_autoeq(
            t_arr,
            len(target_curve),
            m_arr,
            len(measured_curve),
            num_bands,
            ctypes.c_double(sample_rate),
            out_bands,
            ctypes.byref(out_rmse),
        )

        if status != 0:
            raise DynaQOptimizationError(f"Optimization returned non-zero code: {status}")

        result_bands = [
            AutoEqBand(
                frequency_hz=round(b.frequency_hz, 1),
                gain_db=round(b.gain_db, 2),
                q=round(b.q, 2),
                filter_type=b.filter_type,
            )
            for b in out_bands
        ]
        return result_bands, round(out_rmse.value, 3)

    def generate_fir(
        self,
        cutoff_hz: float,
        num_taps: int = 63,
        fir_type: int = 0,
        sample_rate: float = 48000.0,
    ) -> List[float]:
        if not self.is_available:
            raise DynaQDSPError("Native Rust helper library not loaded")

        out_taps = (ctypes.c_double * num_taps)()
        status = self._lib.dynaq_rust_generate_fir(
            fir_type,
            num_taps,
            cutoff_hz,
            sample_rate,
            out_taps,
        )
        if status != 0:
            raise DynaQDSPError(f"FIR generation failed with code: {status}")

        return [round(t, 6) for t in out_taps]

    def scan_true_peak(self, samples: List[float]) -> float:
        if not self.is_available:
            # Fallback to direct max peak
            return max((abs(s) for s in samples), default=0.0)

        c_samples = (ctypes.c_float * len(samples))(*samples)
        out_peak = ctypes.c_double(0.0)
        status = self._lib.dynaq_rust_scan_true_peak(
            c_samples, len(samples), ctypes.byref(out_peak)
        )
        if status != 0:
            raise DynaQDSPError(f"True peak scan failed with code: {status}")
        return round(out_peak.value, 2)

    def measure_phase_correlation(self, left: List[float], right: List[float]) -> float:
        if not self.is_available:
            return 1.0

        count = min(len(left), len(right))
        c_left = (ctypes.c_float * count)(*left[:count])
        c_right = (ctypes.c_float * count)(*right[:count])
        out_corr = ctypes.c_double(1.0)

        status = self._lib.dynaq_rust_measure_phase_correlation(
            c_left, c_right, count, ctypes.byref(out_corr)
        )
        if status != 0:
            raise DynaQDSPError(f"Phase correlation measurement failed: {status}")
        return round(out_corr.value, 3)

