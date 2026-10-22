use crate::autoeq::{optimize_autoeq, AutoEqBand, CurvePoint};
use crate::biquad::{calculate_biquad, BiquadCoeffs, FilterType};
use crate::error::StatusCode;
use crate::fir::{generate_fir_kernel, FirType, FirWindow};
use crate::true_peak::{measure_phase_correlation, scan_true_peak};
use std::ffi::CString;
use std::os::raw::{c_char, c_double, c_float, c_int};

const VERSION_STR: &[u8] = b"1.0.0-beta.2 (Rust SIMD Pro-DSP)\0";

#[no_mangle]
pub extern "C" fn dynaq_rust_version() -> *const c_char {
    VERSION_STR.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn dynaq_rust_optimize_autoeq(
    target_curve_ptr: *const CurvePoint,
    target_len: usize,
    measured_curve_ptr: *const CurvePoint,
    measured_len: usize,
    num_bands: usize,
    sample_rate: c_double,
    out_bands_ptr: *mut AutoEqBand,
    out_rmse_ptr: *mut c_double,
) -> c_int {
    if target_curve_ptr.is_null()
        || measured_curve_ptr.is_null()
        || out_bands_ptr.is_null()
        || out_rmse_ptr.is_null()
    {
        return StatusCode::ErrNullPtr as c_int;
    }
    if target_len == 0 || measured_len == 0 || num_bands == 0 || sample_rate <= 0.0 {
        return StatusCode::ErrInvalidParam as c_int;
    }

    let target_slice = unsafe { std::slice::from_raw_parts(target_curve_ptr, target_len) };
    let measured_slice = unsafe { std::slice::from_raw_parts(measured_curve_ptr, measured_len) };

    match optimize_autoeq(target_slice, measured_slice, num_bands, sample_rate) {
        Ok((bands, rmse)) => {
            let write_len = bands.len().min(num_bands);
            unsafe {
                std::ptr::copy_nonoverlapping(bands.as_ptr(), out_bands_ptr, write_len);
                *out_rmse_ptr = rmse;
            }
            StatusCode::Success as c_int
        }
        Err(err) => StatusCode::from(&err) as c_int,
    }
}

#[no_mangle]
pub extern "C" fn dynaq_rust_generate_fir(
    fir_type: c_int,
    num_taps: usize,
    cutoff_hz: c_double,
    sample_rate: c_double,
    out_taps_ptr: *mut c_double,
) -> c_int {
    if out_taps_ptr.is_null() {
        return StatusCode::ErrNullPtr as c_int;
    }
    let f_type = match fir_type {
        1 => FirType::HighPass,
        2 => FirType::BandPass,
        _ => FirType::LowPass,
    };

    match generate_fir_kernel(f_type, num_taps, cutoff_hz, sample_rate, FirWindow::Blackman) {
        Ok(taps) => {
            unsafe {
                std::ptr::copy_nonoverlapping(taps.as_ptr(), out_taps_ptr, taps.len());
            }
            StatusCode::Success as c_int
        }
        Err(err) => StatusCode::from(&err) as c_int,
    }
}

#[no_mangle]
pub extern "C" fn dynaq_rust_scan_true_peak(
    samples_ptr: *const c_float,
    count: usize,
    out_peak_db_ptr: *mut c_double,
) -> c_int {
    if samples_ptr.is_null() || out_peak_db_ptr.is_null() {
        return StatusCode::ErrNullPtr as c_int;
    }
    let slice = unsafe { std::slice::from_raw_parts(samples_ptr, count) };
    match scan_true_peak(slice) {
        Ok(peak_db) => {
            unsafe { *out_peak_db_ptr = peak_db };
            StatusCode::Success as c_int
        }
        Err(err) => StatusCode::from(&err) as c_int,
    }
}

#[no_mangle]
pub extern "C" fn dynaq_rust_measure_phase_correlation(
    left_ptr: *const c_float,
    right_ptr: *const c_float,
    count: usize,
    out_corr_ptr: *mut c_double,
) -> c_int {
    if left_ptr.is_null() || right_ptr.is_null() || out_corr_ptr.is_null() {
        return StatusCode::ErrNullPtr as c_int;
    }
    let left_slice = unsafe { std::slice::from_raw_parts(left_ptr, count) };
    let right_slice = unsafe { std::slice::from_raw_parts(right_ptr, count) };

    match measure_phase_correlation(left_slice, right_slice) {
        Ok(corr) => {
            unsafe { *out_corr_ptr = corr };
            StatusCode::Success as c_int
        }
        Err(err) => StatusCode::from(&err) as c_int,
    }
}

#[no_mangle]
pub extern "C" fn dynaq_rust_calculate_biquad(
    filter_type: c_int,
    freq_hz: c_double,
    gain_db: c_double,
    q: c_double,
    sample_rate: c_double,
    out_coeffs_ptr: *mut BiquadCoeffs,
) -> c_int {
    if out_coeffs_ptr.is_null() {
        return StatusCode::ErrNullPtr as c_int;
    }
    let ft = match filter_type {
        1 => FilterType::LowShelf,
        2 => FilterType::HighShelf,
        3 => FilterType::LowPass,
        4 => FilterType::HighPass,
        5 => FilterType::Notch,
        _ => FilterType::Bell,
    };

    match calculate_biquad(ft, freq_hz, gain_db, q, sample_rate) {
        Ok(coeffs) => {
            unsafe { *out_coeffs_ptr = coeffs };
            StatusCode::Success as c_int
        }
        Err(err) => StatusCode::from(&err) as c_int,
    }
}

#[no_mangle]
pub extern "C" fn dynaq_rust_evaluate_magnitude(
    coeffs_ptr: *const BiquadCoeffs,
    freq_hz: c_double,
    sample_rate: c_double,
    out_db_ptr: *mut c_double,
) -> c_int {
    if coeffs_ptr.is_null() || out_db_ptr.is_null() {
        return StatusCode::ErrNullPtr as c_int;
    }
    let coeffs = unsafe { *coeffs_ptr };
    let db = coeffs.magnitude_db_at(freq_hz, sample_rate);
    unsafe { *out_db_ptr = db };
    StatusCode::Success as c_int
}

#[no_mangle]
pub extern "C" fn dynaq_rust_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
