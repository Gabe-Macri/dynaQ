use crate::error::DspError;
use std::f64::consts::PI;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BiquadCoeffs {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl BiquadCoeffs {
    pub fn identity() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }

    /// Validates stability using the Jury / Schur-Cohn stability criterion for second-order IIR filters:
    /// 1. |a2| < 1.0
    /// 2. 1 + a1 + a2 > 0
    /// 3. 1 - a1 + a2 > 0
    pub fn is_stable(&self) -> bool {
        if self.a2.abs() >= 1.0 - 1e-9 {
            return false;
        }
        if 1.0 + self.a1 + self.a2 <= 1e-9 {
            return false;
        }
        if 1.0 - self.a1 + self.a2 <= 1e-9 {
            return false;
        }
        true
    }

    /// Computes complex frequency response magnitude in dB at target frequency.
    pub fn magnitude_db_at(&self, freq_hz: f64, sample_rate: f64) -> f64 {
        if sample_rate <= 0.0 || freq_hz <= 0.0 {
            return 0.0;
        }
        let omega = 2.0 * PI * (freq_hz / sample_rate).min(0.499);
        let cos1 = omega.cos();
        let sin1 = omega.sin();
        let cos2 = (2.0 * omega).cos();
        let sin2 = (2.0 * omega).sin();

        // Numerator: b0 + b1*e^(-jw) + b2*e^(-2jw)
        let num_re = self.b0 + self.b1 * cos1 + self.b2 * cos2;
        let num_im = -self.b1 * sin1 - self.b2 * sin2;

        // Denominator: 1.0 + a1*e^(-jw) + a2*e^(-2jw)
        let den_re = 1.0 + self.a1 * cos1 + self.a2 * cos2;
        let den_im = -self.a1 * sin1 - self.a2 * sin2;

        let num_mag_sq = num_re * num_re + num_im * num_im;
        let den_mag_sq = den_re * den_re + den_im * den_im;

        if den_mag_sq <= 1e-20 {
            return 0.0;
        }

        let mag_sq = num_mag_sq / den_mag_sq;
        10.0 * (mag_sq.max(1e-12)).log10()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterType {
    Bell,
    LowShelf,
    HighShelf,
    LowPass,
    HighPass,
    Notch,
    BandPass,
    TiltShelf,
    AllPass,
}

/// Generates standard Audio EQ Cookbook biquad coefficients.
pub fn calculate_biquad(
    filter_type: FilterType,
    freq_hz: f64,
    gain_db: f64,
    q: f64,
    sample_rate: f64,
) -> Result<BiquadCoeffs, DspError> {
    if sample_rate < 8000.0 || sample_rate > 384000.0 {
        return Err(DspError::InvalidParameter(format!(
            "Sample rate {} out of range [8000, 384000]",
            sample_rate
        )));
    }
    if freq_hz < 10.0 || freq_hz > (sample_rate * 0.499) {
        return Err(DspError::InvalidParameter(format!(
            "Frequency {} out of range [10, Nyquist]",
            freq_hz
        )));
    }
    if q < 0.05 || q > 30.0 {
        return Err(DspError::InvalidParameter(format!(
            "Q factor {} out of range [0.05, 30.0]",
            q
        )));
    }

    let w0 = 2.0 * PI * freq_hz / sample_rate;
    let cos_w0 = w0.cos();
    let sin_w0 = w0.sin();
    let alpha = sin_w0 / (2.0 * q);
    let a = 10.0f64.powf(gain_db / 40.0);

    let (b0, b1, b2, a0, a1, a2) = match filter_type {
        FilterType::Bell => {
            let b0 = 1.0 + alpha * a;
            let b1 = -2.0 * cos_w0;
            let b2 = 1.0 - alpha * a;
            let a0 = 1.0 + alpha / a;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha / a;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::LowShelf => {
            let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
            let b0 = a * ((a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha);
            let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0);
            let b2 = a * ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha);
            let a0 = (a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
            let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0);
            let a2 = (a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::HighShelf => {
            let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
            let b0 = a * ((a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha);
            let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0);
            let b2 = a * ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha);
            let a0 = (a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
            let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0);
            let a2 = (a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::LowPass => {
            let b1 = 1.0 - cos_w0;
            let b0 = b1 * 0.5;
            let b2 = b0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::HighPass => {
            let b1 = -(1.0 + cos_w0);
            let b0 = (1.0 + cos_w0) * 0.5;
            let b2 = b0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::Notch => {
            let b0 = 1.0;
            let b1 = -2.0 * cos_w0;
            let b2 = 1.0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::BandPass => {
            let b0 = alpha;
            let b1 = 0.0;
            let b2 = -alpha;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::TiltShelf => {
            let tilt_a = 10.0f64.powf(gain_db / 20.0);
            let k = (w0 * 0.5).tan();
            let b0 = tilt_a + k;
            let b1 = k - tilt_a;
            let b2 = 0.0;
            let a0 = 1.0 + tilt_a * k;
            let a1 = tilt_a * k - 1.0;
            let a2 = 0.0;
            (b0, b1, b2, a0, a1, a2)
        }
        FilterType::AllPass => {
            let b0 = 1.0 - alpha;
            let b1 = -2.0 * cos_w0;
            let b2 = 1.0 + alpha;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            (b0, b1, b2, a0, a1, a2)
        }
    };

    if a0.abs() < 1e-12 {
        return Err(DspError::InvalidParameter("Singular biquad normalization divisor a0".into()));
    }

    let inv_a0 = 1.0 / a0;
    let coeffs = BiquadCoeffs {
        b0: b0 * inv_a0,
        b1: b1 * inv_a0,
        b2: b2 * inv_a0,
        a1: a1 * inv_a0,
        a2: a2 * inv_a0,
    };

    if !coeffs.is_stable() {
        return Err(DspError::UnstableFilter { pole_mag: coeffs.a2.abs().sqrt() });
    }

    Ok(coeffs)
}

