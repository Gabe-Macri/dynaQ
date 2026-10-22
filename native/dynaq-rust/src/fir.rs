use crate::error::DspError;
use std::f64::consts::PI;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FirWindow {
    Hann,
    Hamming,
    Blackman,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FirType {
    LowPass,
    HighPass,
    BandPass,
}

/// Generates a windowed-sinc FIR filter kernel.
pub fn generate_fir_kernel(
    fir_type: FirType,
    num_taps: usize,
    cutoff_hz: f64,
    sample_rate: f64,
    window: FirWindow,
) -> Result<Vec<f64>, DspError> {
    if num_taps < 3 || num_taps > 8192 || num_taps % 2 == 0 {
        return Err(DspError::InvalidParameter(
            "Taps must be an odd integer between 3 and 8192".into(),
        ));
    }
    if sample_rate < 8000.0 || sample_rate > 384000.0 {
        return Err(DspError::InvalidParameter("Sample rate out of bounds".into()));
    }
    let fc = cutoff_hz / sample_rate;
    if fc <= 0.001 || fc >= 0.499 {
        return Err(DspError::InvalidParameter(
            "Normalized cutoff frequency fc must be in (0.001, 0.499)".into(),
        ));
    }

    let m = (num_taps - 1) as f64;
    let mut taps = Vec::with_capacity(num_taps);

    // Compute windowed sinc coefficients
    let mut sum = 0.0;
    for i in 0..num_taps {
        let n = i as f64 - m * 0.5;

        // Ideal sinc response
        let sinc = if n.abs() < 1e-9 {
            2.0 * fc
        } else {
            (2.0 * PI * fc * n).sin() / (PI * n)
        };

        // Window function
        let win = match window {
            FirWindow::Hann => 0.5 * (1.0 - (2.0 * PI * i as f64 / m).cos()),
            FirWindow::Hamming => 0.54 - 0.46 * (2.0 * PI * i as f64 / m).cos(),
            FirWindow::Blackman => {
                0.42 - 0.5 * (2.0 * PI * i as f64 / m).cos()
                    + 0.08 * (4.0 * PI * i as f64 / m).cos()
            }
        };

        let mut h = sinc * win;
        if fir_type == FirType::HighPass {
            // Spectral inversion for high-pass
            h = if n.abs() < 1e-9 { 1.0 - h } else { -h };
        }
        sum += h;
        taps.push(h);
    }

    // Normalize DC gain to unity for low-pass
    if fir_type == FirType::LowPass && sum.abs() > 1e-9 {
        let inv_sum = 1.0 / sum;
        for t in &mut taps {
            *t *= inv_sum;
        }
    }

    Ok(taps)
}

/// Direct stateful FIR convolver for real-time and offline processing.
#[derive(Debug, Clone)]
pub struct FirFilter {
    taps: Vec<f32>,
    history: Vec<f32>,
    history_idx: usize,
}

impl FirFilter {
    pub fn new(taps: &[f64]) -> Self {
        let f32_taps: Vec<f32> = taps.iter().map(|&x| x as f32).collect();
        let len = f32_taps.len();
        Self {
            taps: f32_taps,
            history: vec![0.0; len],
            history_idx: 0,
        }
    }

    pub fn reset(&mut self) {
        self.history.fill(0.0);
        self.history_idx = 0;
    }

    /// Processes in-place buffer with zero allocations.
    pub fn process_block(&mut self, samples: &mut [f32]) {
        let num_taps = self.taps.len();
        for s in samples.iter_mut() {
            let input = *s;
            self.history[self.history_idx] = input;

            let mut acc = 0.0f32;
            let mut h_idx = self.history_idx;
            for tap in &self.taps {
                acc += tap * self.history[h_idx];
                if h_idx == 0 {
                    h_idx = num_taps - 1;
                } else {
                    h_idx -= 1;
                }
            }

            self.history_idx = (self.history_idx + 1) % num_taps;
            *s = acc;
        }
    }
}

