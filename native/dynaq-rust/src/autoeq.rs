use crate::biquad::{calculate_biquad, BiquadCoeffs, FilterType};
use crate::error::DspError;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AutoEqBand {
    pub frequency_hz: f64,
    pub gain_db: f64,
    pub q: f64,
    pub filter_type: i32, // 0 = Bell, 1 = LowShelf, 2 = HighShelf
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct CurvePoint {
    pub freq_hz: f64,
    pub db: f64,
}

/// Evaluates composite EQ curve in dB across an array of test frequencies.
pub fn evaluate_composite_curve(
    bands: &[AutoEqBand],
    freqs: &[f64],
    sample_rate: f64,
) -> Vec<f64> {
    let coeffs: Vec<Option<BiquadCoeffs>> = bands
        .iter()
        .map(|b| {
            let ft = match b.filter_type {
                1 => FilterType::LowShelf,
                2 => FilterType::HighShelf,
                _ => FilterType::Bell,
            };
            calculate_biquad(ft, b.frequency_hz, b.gain_db, b.q, sample_rate).ok()
        })
        .collect();

    freqs
        .iter()
        .map(|&f| {
            let mut sum_db = 0.0;
            for c in coeffs.iter().flatten() {
                sum_db += c.magnitude_db_at(f, sample_rate);
            }
            sum_db
        })
        .collect()
}

/// Calculates Root-Mean-Square Error (RMSE) between composite EQ and target delta.
pub fn calculate_rmse(
    bands: &[AutoEqBand],
    freqs: &[f64],
    target_delta: &[f64],
    sample_rate: f64,
) -> f64 {
    if freqs.is_empty() || freqs.len() != target_delta.len() {
        return f64::MAX;
    }
    let composite = evaluate_composite_curve(bands, freqs, sample_rate);
    let mut sum_sq = 0.0;
    for i in 0..freqs.len() {
        let diff = composite[i] - target_delta[i];
        sum_sq += diff * diff;
    }
    (sum_sq / (freqs.len() as f64)).sqrt()
}

/// Optimizes a set of parametric EQ bands to fit a target deviation curve using
/// residual peak identification and iterative coordinate descent.
pub fn optimize_autoeq(
    target_curve: &[CurvePoint],
    measured_curve: &[CurvePoint],
    num_bands: usize,
    sample_rate: f64,
) -> Result<(Vec<AutoEqBand>, f64), DspError> {
    if target_curve.is_empty() {
        return Err(DspError::InvalidParameter("Target curve is empty".into()));
    }
    if measured_curve.is_empty() {
        return Err(DspError::InvalidParameter("Measured curve is empty".into()));
    }
    let bands_count = num_bands.clamp(1, 16);

    // 1. Generate logarithmic evaluation grid (64 sample points from 20 Hz to 20,000 Hz)
    let grid_size = 64;
    let mut freqs = Vec::with_capacity(grid_size);
    let log_min = 20.0f64.ln();
    let log_max = 20000.0f64.ln();
    for i in 0..grid_size {
        let t = i as f64 / ((grid_size - 1) as f64);
        freqs.push((log_min + t * (log_max - log_min)).exp());
    }

    // 2. Interpolate target delta = target - measured
    let mut target_delta = Vec::with_capacity(grid_size);
    for &f in &freqs {
        let tgt_val = interpolate_curve(target_curve, f);
        let meas_val = interpolate_curve(measured_curve, f);
        target_delta.push(tgt_val - meas_val);
    }

    // 3. Initialize bands across logarithmic frequency centers
    let mut bands = Vec::with_capacity(bands_count);
    for i in 0..bands_count {
        let t = (i as f64 + 0.5) / (bands_count as f64);
        let f0 = (log_min + t * (log_max - log_min)).exp();
        let init_gain = interpolate_curve_points(&freqs, &target_delta, f0).clamp(-12.0, 12.0);
        bands.push(AutoEqBand {
            frequency_hz: f0,
            gain_db: init_gain,
            q: 1.414,
            filter_type: 0, // Bell
        });
    }

    let mut current_rmse = calculate_rmse(&bands, &freqs, &target_delta, sample_rate);

    // 4. Multi-pass Coordinate Descent Optimization
    let max_iterations = 25;
    for _ in 0..max_iterations {
        let mut improved = false;

        for b in 0..bands_count {
            // A. Optimize Gain
            let gain_steps = [-1.5, -0.5, 0.5, 1.5];
            for &g_step in &gain_steps {
                let old_gain = bands[b].gain_db;
                let test_gain = (old_gain + g_step).clamp(-18.0, 18.0);
                bands[b].gain_db = test_gain;
                let test_rmse = calculate_rmse(&bands, &freqs, &target_delta, sample_rate);
                if test_rmse < current_rmse - 1e-4 {
                    current_rmse = test_rmse;
                    improved = true;
                } else {
                    bands[b].gain_db = old_gain;
                }
            }

            // B. Optimize Frequency (shift within +/- 15%)
            let freq_ratios = [0.90, 0.96, 1.04, 1.10];
            for &f_ratio in &freq_ratios {
                let old_freq = bands[b].frequency_hz;
                let test_freq = (old_freq * f_ratio).clamp(20.0, 19000.0);
                bands[b].frequency_hz = test_freq;
                let test_rmse = calculate_rmse(&bands, &freqs, &target_delta, sample_rate);
                if test_rmse < current_rmse - 1e-4 {
                    current_rmse = test_rmse;
                    improved = true;
                } else {
                    bands[b].frequency_hz = old_freq;
                }
            }

            // C. Optimize Q factor
            let q_steps = [0.70, 0.90, 1.10, 1.40];
            for &q_ratio in &q_steps {
                let old_q = bands[b].q;
                let test_q = (old_q * q_ratio).clamp(0.3, 10.0);
                bands[b].q = test_q;
                let test_rmse = calculate_rmse(&bands, &freqs, &target_delta, sample_rate);
                if test_rmse < current_rmse - 1e-4 {
                    current_rmse = test_rmse;
                    improved = true;
                } else {
                    bands[b].q = old_q;
                }
            }
        }

        if !improved {
            break;
        }
    }

    Ok((bands, current_rmse))
}

fn interpolate_curve(curve: &[CurvePoint], target_freq: f64) -> f64 {
    if curve.is_empty() {
        return 0.0;
    }
    if target_freq <= curve[0].freq_hz {
        return curve[0].db;
    }
    if target_freq >= curve[curve.len() - 1].freq_hz {
        return curve[curve.len() - 1].db;
    }

    for i in 0..(curve.len() - 1) {
        let f0 = curve[i].freq_hz;
        let f1 = curve[i + 1].freq_hz;
        if target_freq >= f0 && target_freq <= f1 {
            let log_f0 = f0.ln();
            let log_f1 = f1.ln();
            let log_target = target_freq.ln();
            let t = if (log_f1 - log_f0).abs() > 1e-6 {
                (log_target - log_f0) / (log_f1 - log_f0)
            } else {
                0.0
            };
            return curve[i].db + t * (curve[i + 1].db - curve[i].db);
        }
    }
    curve[curve.len() - 1].db
}

fn interpolate_curve_points(freqs: &[f64], values: &[f64], target_freq: f64) -> f64 {
    if freqs.is_empty() {
        return 0.0;
    }
    if target_freq <= freqs[0] {
        return values[0];
    }
    if target_freq >= freqs[freqs.len() - 1] {
        return values[values.len() - 1];
    }
    for i in 0..(freqs.len() - 1) {
        if target_freq >= freqs[i] && target_freq <= freqs[i + 1] {
            let t = (target_freq - freqs[i]) / (freqs[i + 1] - freqs[i]);
            return values[i] + t * (values[i + 1] - values[i]);
        }
    }
    values[values.len() - 1]
}

