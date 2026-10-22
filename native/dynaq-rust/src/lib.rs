pub mod autoeq;
pub mod biquad;
pub mod capi;
pub mod error;
pub mod fir;
pub mod true_peak;

pub use autoeq::{optimize_autoeq, AutoEqBand, CurvePoint};
pub use biquad::{calculate_biquad, BiquadCoeffs, FilterType};
pub use error::{DspError, StatusCode};
pub use fir::{generate_fir_kernel, FirFilter, FirType, FirWindow};
pub use true_peak::{measure_phase_correlation, scan_true_peak};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_biquad_stability_checks() {
        // Stable Bell filter
        let stable = calculate_biquad(FilterType::Bell, 1000.0, 6.0, 1.414, 48000.0).unwrap();
        assert!(stable.is_stable());

        // Unstable coefficients
        let unstable = BiquadCoeffs {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: -2.1,
            a2: 1.05,
        };
        assert!(!unstable.is_stable());
    }

    #[test]
    fn test_biquad_frequency_response() {
        let coeffs = calculate_biquad(FilterType::Bell, 1000.0, 6.0, 2.0, 48000.0).unwrap();
        let mag_center = coeffs.magnitude_db_at(1000.0, 48000.0);
        let mag_far = coeffs.magnitude_db_at(50.0, 48000.0);

        assert!((mag_center - 6.0).abs() < 0.2);
        assert!(mag_far.abs() < 0.5);
    }

    #[test]
    fn test_autoeq_optimization_reduces_rmse() {
        // Measured curve with a 6dB mid-bass bump at 200 Hz
        let measured = vec![
            CurvePoint { freq_hz: 20.0, db: 0.0 },
            CurvePoint { freq_hz: 100.0, db: 3.0 },
            CurvePoint { freq_hz: 200.0, db: 6.0 },
            CurvePoint { freq_hz: 500.0, db: 1.0 },
            CurvePoint { freq_hz: 1000.0, db: 0.0 },
            CurvePoint { freq_hz: 10000.0, db: 0.0 },
        ];

        // Target curve is flat (0.0 dB)
        let target = vec![
            CurvePoint { freq_hz: 20.0, db: 0.0 },
            CurvePoint { freq_hz: 1000.0, db: 0.0 },
            CurvePoint { freq_hz: 20000.0, db: 0.0 },
        ];

        let (bands, rmse) = optimize_autoeq(&target, &measured, 5, 48000.0).unwrap();
        assert_eq!(bands.len(), 5);
        // Optimization must achieve significant error reduction
        assert!(rmse < 3.5, "RMSE should be significantly reduced (got {})", rmse);
    }

    #[test]
    fn test_fir_kernel_generation() {
        let taps = generate_fir_kernel(FirType::LowPass, 63, 1000.0, 48000.0, FirWindow::Blackman).unwrap();
        assert_eq!(taps.len(), 63);

        // Center tap should have largest weight
        let center = taps[31];
        assert!(center > 0.0);

        let mut convolver = FirFilter::new(&taps);
        let mut block = vec![0.0f32; 128];
        block[0] = 1.0; // Unit impulse
        convolver.process_block(&mut block);

        // Impulse response output matches FIR taps
        for i in 0..63 {
            assert!((block[i] - taps[i] as f32).abs() < 1e-5);
        }
    }

    #[test]
    fn test_true_peak_scanning() {
        // Signal with clipping peak
        let mut samples = vec![0.5f32; 100];
        samples[50] = 1.5; // +3.52 dBFS

        let peak_db = scan_true_peak(&samples).unwrap();
        assert!((peak_db - 3.52).abs() < 0.2);
    }

    #[test]
    fn test_phase_correlation() {
        let left = vec![1.0f32, -0.5, 0.8, -0.2, 0.5];
        let right = left.clone();

        let corr_mono = measure_phase_correlation(&left, &right).unwrap();
        assert!((corr_mono - 1.0).abs() < 1e-5);

        let inverted: Vec<f32> = left.iter().map(|&x| -x).collect();
        let corr_inv = measure_phase_correlation(&left, &inverted).unwrap();
        assert!((corr_inv - (-1.0)).abs() < 1e-5);
    }
}

