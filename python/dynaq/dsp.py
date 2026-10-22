"""dynaQ Pure-Python DSP Utilities and Standard Acoustic Target Curves.

Provides mathematical biquad calculators, curve interpolation, and
industry-standard headphone/speaker target curves (Harman, Diffuse Field, Studio Flat).
"""

import math
from typing import List, Tuple

# Standard Target Curves: List of (frequency_hz, db_offset)
HARMAN_OVER_EAR: List[Tuple[float, float]] = [
    (20.0, 5.5),
    (50.0, 5.0),
    (100.0, 4.0),
    (200.0, 1.5),
    (500.0, 0.0),
    (1000.0, 0.0),
    (2000.0, 3.5),
    (3000.0, 7.5),
    (4000.0, 5.0),
    (6000.0, 1.0),
    (8000.0, 0.0),
    (10000.0, -1.5),
    (20000.0, -5.0),
]

HARMAN_IN_EAR: List[Tuple[float, float]] = [
    (20.0, 9.0),
    (50.0, 8.5),
    (100.0, 7.0),
    (200.0, 2.5),
    (500.0, 0.5),
    (1000.0, 0.0),
    (2000.0, 6.0),
    (3000.0, 10.0),
    (4000.0, 6.5),
    (6000.0, 2.0),
    (8000.0, 1.0),
    (10000.0, 0.0),
    (20000.0, -4.0),
]

DIFFUSE_FIELD: List[Tuple[float, float]] = [
    (20.0, 0.0),
    (100.0, 0.0),
    (1000.0, 0.0),
    (3000.0, 8.0),
    (6000.0, 3.0),
    (9000.0, 6.0),
    (12000.0, 2.0),
    (20000.0, -2.0),
]

STUDIO_FLAT: List[Tuple[float, float]] = [
    (20.0, 0.0),
    (100.0, 0.0),
    (1000.0, 0.0),
    (10000.0, 0.0),
    (20000.0, 0.0),
]


def interpolate_curve(curve: List[Tuple[float, float]], target_freq: float) -> float:
    """Performs logarithmic frequency interpolation along a discrete response curve."""
    if not curve:
        return 0.0
    if target_freq <= curve[0][0]:
        return curve[0][1]
    if target_freq >= curve[-1][0]:
        return curve[-1][1]

    for i in range(len(curve) - 1):
        f0, db0 = curve[i]
        f1, db1 = curve[i + 1]
        if f0 <= target_freq <= f1:
            log_f0 = math.log(f0)
            log_f1 = math.log(f1)
            log_target = math.log(target_freq)
            t = (log_target - log_f0) / (log_f1 - log_f0) if (log_f1 - log_f0) != 0 else 0.0
            return db0 + t * (db1 - db0)
    return curve[-1][1]


def biquad_bell_magnitude(freq: float, f0: float, gain_db: float, q: float, sample_rate: float = 48000.0) -> float:
    """Evaluates the magnitude response in dB of a parametric bell filter at target frequency."""
    w0 = 2.0 * math.pi * f0 / sample_rate
    alpha = math.sin(w0) / (2.0 * q)
    a = 10.0 ** (gain_db / 40.0)

    b0 = 1.0 + alpha * a
    b1 = -2.0 * math.cos(w0)
    b2 = 1.0 - alpha * a
    a0 = 1.0 + alpha / a
    a1 = -2.0 * math.cos(w0)
    a2 = 1.0 - alpha / a

    inv_a0 = 1.0 / a0
    b0 *= inv_a0
    b1 *= inv_a0
    b2 *= inv_a0
    a1 *= inv_a0
    a2 *= inv_a0

    omega = 2.0 * math.pi * min(freq, sample_rate * 0.499) / sample_rate
    cos1 = math.cos(omega)
    sin1 = math.sin(omega)
    cos2 = math.cos(2.0 * omega)
    sin2 = math.sin(2.0 * omega)

    num_re = b0 + b1 * cos1 + b2 * cos2
    num_im = -b1 * sin1 - b2 * sin2
    den_re = 1.0 + a1 * cos1 + a2 * cos2
    den_im = -a1 * sin1 - a2 * sin2

    num_sq = num_re * num_re + num_im * num_im
    den_sq = den_re * den_re + den_im * den_im
    if den_sq <= 1e-12:
        return 0.0

    return 10.0 * math.log10(max(num_sq / den_sq, 1e-12))

