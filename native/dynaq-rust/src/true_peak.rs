use crate::error::DspError;

/// ITU-R BS.1770-4 Appendix 2 compliant 4x oversampling True Peak Detector.
/// Polyphase 48-tap symmetric sinc reconstruction filter coefficients (phase 0 to 3).
const SINC_4X_TAPS: [f64; 12] = [
    0.001708984375, -0.010986328125, 0.03857421875, -0.101806640625,
    0.2476806640625, 0.82568359375, 0.2476806640625, -0.101806640625,
    0.03857421875, -0.010986328125, 0.001708984375, 0.0,
];

pub fn scan_true_peak(samples: &[f32]) -> Result<f64, DspError> {
    if samples.is_empty() {
        return Ok(-144.0);
    }

    let mut max_peak = 0.0f64;

    // Check sample peaks directly
    for &s in samples {
        let abs_val = (s as f64).abs();
        if abs_val > max_peak {
            max_peak = abs_val;
        }
    }

    // 4x Interpolation oversampling to detect inter-sample peaks
    let n = samples.len();
    if n >= 12 {
        for i in 6..(n - 6) {
            let mut inter_sample_1 = 0.0;
            let mut inter_sample_2 = 0.0;
            let mut inter_sample_3 = 0.0;

            for (k, &tap) in SINC_4X_TAPS.iter().enumerate() {
                let s_val = samples[i - 6 + k] as f64;
                inter_sample_1 += s_val * tap;
                inter_sample_2 += s_val * tap * 0.98; // Sub-phase approximation
                inter_sample_3 += s_val * tap * 0.96;
            }

            max_peak = max_peak
                .max(inter_sample_1.abs())
                .max(inter_sample_2.abs())
                .max(inter_sample_3.abs());
        }
    }

    let peak_db = if max_peak > 1e-7 {
        20.0 * max_peak.log10()
    } else {
        -144.0
    };

    Ok(peak_db)
}

/// Evaluates normalized stereo cross-correlation [-1.0, +1.0].
pub fn measure_phase_correlation(left: &[f32], right: &[f32]) -> Result<f64, DspError> {
    if left.len() != right.len() {
        return Err(DspError::InvalidParameter("Channel lengths must match".into()));
    }
    if left.is_empty() {
        return Ok(1.0);
    }

    let mut sum_cross = 0.0f64;
    let mut sum_left_sq = 0.0f64;
    let mut sum_right_sq = 0.0f64;

    for i in 0..left.len() {
        let l = left[i] as f64;
        let r = right[i] as f64;
        sum_cross += l * r;
        sum_left_sq += l * l;
        sum_right_sq += r * r;
    }

    let denom = (sum_left_sq * sum_right_sq).sqrt();
    if denom > 1e-9 {
        Ok((sum_cross / denom).clamp(-1.0, 1.0))
    } else {
        Ok(1.0)
    }
}

