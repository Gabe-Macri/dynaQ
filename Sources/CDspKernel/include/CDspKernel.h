#ifndef CDSPKERNEL_H
#define CDSPKERNEL_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

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
void c_eq_engine_set_gains(c_eq_engine_t* eq, float preamp_gain_linear, float master_gain_linear);
void c_eq_engine_set_params(c_eq_engine_t* eq, bool is_bypassed, bool phase_invert, int monitor_mode);
void c_eq_engine_process_stereo(c_eq_engine_t* eq, float* left, float* right, size_t count);

// ============================================================================
// 3. Vectorized Mid/Side Encoding & Decoding
// ============================================================================

void c_dsp_midside_encode(const float* left, const float* right, float* mid, float* side, size_t count);
void c_dsp_midside_decode(const float* mid, const float* side, float* left, float* right, size_t count);

// ============================================================================
// 4. Vectorized Dynamics: Soft-Knee Peak Limiter
// ============================================================================

void c_dsp_limiter_process_stereo(float* left, float* right, size_t count, float linear_ceiling, bool enabled);

// ============================================================================
// 5. Accelerate-Powered Telemetry: Peak, RMS & Clip Measurement
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
