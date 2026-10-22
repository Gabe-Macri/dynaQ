#ifndef CDSPKERNEL_H
#define CDSPKERNEL_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// 0. Unified C DSP Status & Error Codes
// ============================================================================

typedef enum {
    C_DSP_OK = 0,
    C_DSP_ERR_INVALID_PARAM = -1,
    C_DSP_ERR_NULL_POINTER = -2,
    C_DSP_ERR_UNSTABLE_FILTER = -3,
    C_DSP_ERR_BUFFER_OVERRUN = -4,
    C_DSP_ERR_BUFFER_UNDERRUN = -5,
    C_DSP_ERR_NOT_INITIALIZED = -6
} c_dsp_status_t;

// ============================================================================
// 1. Lock-Free Atomic Single-Producer Single-Consumer (SPSC) Ring Buffer
// ============================================================================

typedef struct c_ringbuffer c_ringbuffer_t;

c_ringbuffer_t* c_ringbuffer_create(size_t capacity);
void c_ringbuffer_destroy(c_ringbuffer_t* rb);
void c_ringbuffer_reset(c_ringbuffer_t* rb);
size_t c_ringbuffer_available_read(const c_ringbuffer_t* rb);
size_t c_ringbuffer_available_write(const c_ringbuffer_t* rb);

size_t c_ringbuffer_write_stereo(c_ringbuffer_t* rb, const float* left, const float* right, size_t count);
size_t c_ringbuffer_read_stereo(c_ringbuffer_t* rb, float* left, float* right, size_t count);

// ============================================================================
// 2. High-Performance Biquad Filter & Cascades
// ============================================================================

typedef struct {
    float b0, b1, b2, a1, a2;
} c_biquad_coeffs_t;

/// Jury stability test: returns true if filter poles are strictly inside the unit circle (|z| < 1)
bool c_biquad_is_stable(c_biquad_coeffs_t coeffs);

typedef struct {
    float s1_left, s2_left;
    float s1_right, s2_right;
    c_biquad_coeffs_t current;
    c_biquad_coeffs_t target;
    bool is_enabled;
    int routing; // 0 = Stereo, 1 = Mid, 2 = Side, 3 = LeftOnly, 4 = RightOnly
} c_biquad_channel_t;

#define C_DSP_MAX_BANDS 16

typedef struct {
    c_biquad_channel_t bands[C_DSP_MAX_BANDS];
    int band_count;
    float preamp_gain_linear;
    float master_gain_linear;
    bool is_bypassed;
    bool phase_invert;
    int monitor_mode; // 0 = Stereo, 1 = Mono, 2 = Sides
} c_eq_engine_t;

void c_eq_engine_init(c_eq_engine_t* eq);
void c_eq_engine_reset_state(c_eq_engine_t* eq);
void c_eq_engine_set_band(c_eq_engine_t* eq, int index, c_biquad_coeffs_t coeffs, int routing, bool enabled, bool immediate);
c_dsp_status_t c_eq_engine_set_band_safe(c_eq_engine_t* eq, int index, c_biquad_coeffs_t coeffs, int routing, bool enabled, bool immediate);
void c_eq_engine_set_gains(c_eq_engine_t* eq, float preamp_gain_linear, float master_gain_linear);
void c_eq_engine_set_params(c_eq_engine_t* eq, bool is_bypassed, bool phase_invert, int monitor_mode);
void c_eq_engine_process_stereo(c_eq_engine_t* eq, float* left, float* right, size_t count);

// ============================================================================
// 3. Vectorized Mid/Side Encoding & Decoding
// ============================================================================

void c_dsp_midside_encode(const float* left, const float* right, float* mid, float* side, size_t count);
void c_dsp_midside_decode(const float* mid, const float* side, float* left, float* right, size_t count);

// ============================================================================
// 4. Vectorized Dynamics: True-Peak Soft-Knee Limiter & Lookahead Limiter
// ============================================================================

void c_dsp_limiter_process_stereo(float* left, float* right, size_t count, float linear_ceiling, bool enabled);

typedef struct c_lookahead_limiter c_lookahead_limiter_t;

c_lookahead_limiter_t* c_lookahead_limiter_create(size_t lookahead_samples, float sample_rate, float ceiling_linear);
void c_lookahead_limiter_destroy(c_lookahead_limiter_t* lim);
void c_lookahead_limiter_reset(c_lookahead_limiter_t* lim);
void c_lookahead_limiter_set_ceiling(c_lookahead_limiter_t* lim, float ceiling_linear);
void c_lookahead_limiter_set_live_mode(c_lookahead_limiter_t* lim, bool live_mode);
bool c_lookahead_limiter_get_live_mode(const c_lookahead_limiter_t* lim);
void c_lookahead_limiter_process(c_lookahead_limiter_t* lim, float* left, float* right, size_t count);

// Explicit M/S to L/R Decoder Matrix guarantee
void c_dsp_ensure_midside_decoded(float* left, float* right, size_t count, bool is_midside);

// ============================================================================
// 5. Accelerate-Powered Telemetry: Peak, RMS, Clip & Phase Measurement
// ============================================================================

typedef struct {
    float peak_left_db;
    float peak_right_db;
    float rms_left_db;
    float rms_right_db;
    bool clip_left;
    bool clip_right;
} c_loudness_result_t;

void c_dsp_measure_loudness(
    const float* left,
    const float* right,
    size_t count,
    float* inout_peak_l,
    float* inout_peak_r,
    float* inout_rms_l,
    float* inout_rms_r,
    bool* inout_clip_l,
    bool* inout_clip_r,
    c_loudness_result_t* result
);

float c_dsp_measure_phase_correlation(const float* left, const float* right, size_t count);

// ============================================================================
// 6. Vector Utility Functions
// ============================================================================

void c_dsp_downmix_stereo_to_mono(const float* left, const float* right, float* mono, size_t count);
void c_dsp_apply_gain(float* buffer, float gain, size_t count);
void c_dsp_interleave_stereo(const float* left, const float* right, float* interleaved, size_t count);
void c_dsp_deinterleave_stereo(const float* interleaved, float* left, float* right, size_t count);

#ifdef __cplusplus
}
#endif

#endif // CDSPKERNEL_H