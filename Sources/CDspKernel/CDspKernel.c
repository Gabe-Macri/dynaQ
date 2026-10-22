#include "CDspKernel.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdatomic.h>
#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#else
#include <math.h>

// Cross-platform vector arithmetic fallbacks for Linux / Docker container environments
static inline void vDSP_vsmul(const float* a, int ia, const float* b, float* c, int ic, size_t n) {
    float s = *b;
    for (size_t i = 0; i < n; i++) c[i * ic] = a[i * ia] * s;
}

static inline void vDSP_vasm(const float* a, int ia, const float* b, int ib, const float* c, float* d, int id, size_t n) {
    float s = *c;
    for (size_t i = 0; i < n; i++) d[i * id] = (a[i * ia] + b[i * ib]) * s;
}

static inline void vDSP_vsub(const float* b, int ib, const float* a, int ia, float* c, int ic, size_t n) {
    for (size_t i = 0; i < n; i++) c[i * ic] = a[i * ia] - b[i * ib];
}

static inline void vDSP_vadd(const float* a, int ia, const float* b, int ib, float* c, int ic, size_t n) {
    for (size_t i = 0; i < n; i++) c[i * ic] = a[i * ia] + b[i * ib];
}

static inline void vDSP_maxmgv(const float* a, int ia, float* c, size_t n) {
    float max_val = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float v = fabsf(a[i * ia]);
        if (v > max_val) max_val = v;
    }
    *c = max_val;
}

static inline void vDSP_measqv(const float* a, int ia, float* c, size_t n) {
    float sum_sq = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float v = a[i * ia];
        sum_sq += v * v;
    }
    *c = (n > 0) ? (sum_sq / (float)n) : 0.0f;
}
#endif

// ============================================================================
// 1. Lock-Free Atomic Single-Producer Single-Consumer (SPSC) Ring Buffer
// ============================================================================

struct c_ringbuffer {
    float* left;
    float* right;
    size_t capacity;
    size_t mask;
    _Atomic size_t write_index;
    _Atomic size_t read_index;
};

c_ringbuffer_t* c_ringbuffer_create(size_t capacity) {
    // Ensure capacity is a power of 2 for fast bitmask wrapping
    size_t cap = 1;
    while (cap < capacity) {
        cap <<= 1;
    }

    c_ringbuffer_t* rb = (c_ringbuffer_t*)malloc(sizeof(c_ringbuffer_t));
    if (!rb) return NULL;

    rb->capacity = cap;
    rb->mask = cap - 1;
    rb->left = (float*)calloc(cap, sizeof(float));
    rb->right = (float*)calloc(cap, sizeof(float));
    atomic_init(&rb->write_index, 0);
    atomic_init(&rb->read_index, 0);

    return rb;
}

void c_ringbuffer_destroy(c_ringbuffer_t* rb) {
    if (!rb) return;
    if (rb->left) free(rb->left);
    if (rb->right) free(rb->right);
    free(rb);
}

void c_ringbuffer_reset(c_ringbuffer_t* rb) {
    if (!rb) return;
    atomic_store_explicit(&rb->write_index, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->read_index, 0, memory_order_relaxed);
    memset(rb->left, 0, rb->capacity * sizeof(float));
    memset(rb->right, 0, rb->capacity * sizeof(float));
}

size_t c_ringbuffer_available_read(const c_ringbuffer_t* rb) {
    if (!rb) return 0;
    size_t w = atomic_load_explicit(&rb->write_index, memory_order_acquire);
    size_t r = atomic_load_explicit(&rb->read_index, memory_order_acquire);
    return (w >= r) ? (w - r) : 0;
}

size_t c_ringbuffer_available_write(const c_ringbuffer_t* rb) {
    if (!rb) return 0;
    size_t read_avail = c_ringbuffer_available_read(rb);
    return (rb->capacity > read_avail) ? (rb->capacity - read_avail) : 0;
}

size_t c_ringbuffer_write_stereo(c_ringbuffer_t* rb, const float* left, const float* right, size_t count) {
    if (!rb || !left || !right || count == 0) return 0;

    size_t w = atomic_load_explicit(&rb->write_index, memory_order_relaxed);
    size_t r = atomic_load_explicit(&rb->read_index, memory_order_acquire);
    size_t in_buffer = (w >= r) ? (w - r) : 0;
    size_t available = (rb->capacity > in_buffer) ? (rb->capacity - in_buffer) : 0;

    size_t to_write = (count < available) ? count : available;
    if (to_write == 0) return 0;

    size_t mask = rb->mask;
    size_t start_idx = w & mask;
    size_t part1 = rb->capacity - start_idx;

    if (to_write <= part1) {
        memcpy(rb->left + start_idx, left, to_write * sizeof(float));
        memcpy(rb->right + start_idx, right, to_write * sizeof(float));
    } else {
        memcpy(rb->left + start_idx, left, part1 * sizeof(float));
        memcpy(rb->right + start_idx, right, part1 * sizeof(float));
        size_t part2 = to_write - part1;
        memcpy(rb->left, left + part1, part2 * sizeof(float));
        memcpy(rb->right, right + part1, part2 * sizeof(float));
    }

    atomic_store_explicit(&rb->write_index, w + to_write, memory_order_release);
    return to_write;
}

size_t c_ringbuffer_read_stereo(c_ringbuffer_t* rb, float* left, float* right, size_t count) {
    if (!rb || !left || !right || count == 0) return 0;

    size_t r = atomic_load_explicit(&rb->read_index, memory_order_relaxed);
    size_t w = atomic_load_explicit(&rb->write_index, memory_order_acquire);
    size_t available = (w >= r) ? (w - r) : 0;

    size_t to_read = (count < available) ? count : available;

    if (to_read > 0) {
        size_t mask = rb->mask;
        size_t start_idx = r & mask;
        size_t part1 = rb->capacity - start_idx;

        if (to_read <= part1) {
            memcpy(left, rb->left + start_idx, to_read * sizeof(float));
            memcpy(right, rb->right + start_idx, to_read * sizeof(float));
        } else {
            memcpy(left, rb->left + start_idx, part1 * sizeof(float));
            memcpy(right, rb->right + start_idx, part1 * sizeof(float));
            size_t part2 = to_read - part1;
            memcpy(left + part1, rb->left, part2 * sizeof(float));
            memcpy(right + part1, rb->right, part2 * sizeof(float));
        }

        atomic_store_explicit(&rb->read_index, r + to_read, memory_order_release);
    }

    // Zero-fill underruns to prevent glitching and stale repeat buffers
    if (to_read < count) {
        memset(left + to_read, 0, (count - to_read) * sizeof(float));
        memset(right + to_read, 0, (count - to_read) * sizeof(float));
    }

    return to_read;
}

// ============================================================================
// 2. High-Performance Biquad Filter & Cascade Processing
// ============================================================================

void c_eq_engine_init(c_eq_engine_t* eq) {
    if (!eq) return;
    memset(eq, 0, sizeof(c_eq_engine_t));
    eq->preamp_gain_linear = 1.0f;
    eq->master_gain_linear = 1.0f;
    eq->is_bypassed = false;
    eq->phase_invert = false;
    eq->monitor_mode = 0; // Stereo

    for (int i = 0; i < C_DSP_MAX_BANDS; i++) {
        eq->bands[i].current.b0 = 1.0f;
        eq->bands[i].target.b0 = 1.0f;
        eq->bands[i].is_enabled = true;
        eq->bands[i].routing = 0; // Stereo
    }
}

void c_eq_engine_reset_state(c_eq_engine_t* eq) {
    if (!eq) return;
    for (int i = 0; i < C_DSP_MAX_BANDS; i++) {
        eq->bands[i].s1_left = 0.0f;
        eq->bands[i].s2_left = 0.0f;
        eq->bands[i].s1_right = 0.0f;
        eq->bands[i].s2_right = 0.0f;
    }
}

void c_eq_engine_set_band(c_eq_engine_t* eq, int index, c_biquad_coeffs_t coeffs, int routing, bool enabled, bool immediate) {
    if (!eq || index < 0 || index >= C_DSP_MAX_BANDS) return;
    eq->bands[index].target = coeffs;
    eq->bands[index].routing = routing;
    eq->bands[index].is_enabled = enabled;
    if (immediate) {
        eq->bands[index].current = coeffs;
    }
    if (index >= eq->band_count) {
        eq->band_count = index + 1;
    }
}

void c_eq_engine_set_gains(c_eq_engine_t* eq, float preamp_gain_linear, float master_gain_linear) {
    if (!eq) return;
    eq->preamp_gain_linear = preamp_gain_linear;
    eq->master_gain_linear = master_gain_linear;
}

void c_eq_engine_set_params(c_eq_engine_t* eq, bool is_bypassed, bool phase_invert, int monitor_mode) {
    if (!eq) return;
    eq->is_bypassed = is_bypassed;
    eq->phase_invert = phase_invert;
    eq->monitor_mode = monitor_mode;
}

static inline void process_biquad_single_channel(
    float* __restrict__ buffer,
    size_t count,
    c_biquad_coeffs_t* __restrict__ curr,
    const c_biquad_coeffs_t* __restrict__ target,
    float* __restrict__ s1_ptr,
    float* __restrict__ s2_ptr
) {
    // Smooth coefficients toward target or snap if close
    if (fabsf(target->b0 - curr->b0) < 1e-6f && fabsf(target->a1 - curr->a1) < 1e-6f) {
        *curr = *target;
    } else {
        curr->b0 += (target->b0 - curr->b0) * 0.15f;
        curr->b1 += (target->b1 - curr->b1) * 0.15f;
        curr->b2 += (target->b2 - curr->b2) * 0.15f;
        curr->a1 += (target->a1 - curr->a1) * 0.15f;
        curr->a2 += (target->a2 - curr->a2) * 0.15f;
    }

    const float b0 = curr->b0;
    const float b1 = curr->b1;
    const float b2 = curr->b2;
    const float a1 = curr->a1;
    const float a2 = curr->a2;

    float s1 = *s1_ptr;
    float s2 = *s2_ptr;

    #pragma clang loop unroll_count(4)
    for (size_t i = 0; i < count; i++) {
        float x = buffer[i];
        float y = b0 * x + s1;
        s1 = b1 * x - a1 * y + s2;
        s2 = b2 * x - a2 * y;

        // Guard against NaN/Inf divergences and denormals
        if (isnan(y) || isinf(y)) {
            y = 0.0f;
            s1 = 0.0f;
            s2 = 0.0f;
        } else if (fabsf(y) < 1e-15f) {
            y = 0.0f;
        }
        buffer[i] = y;
    }

    // Flush state denormals
    if (fabsf(s1) < 1e-15f) s1 = 0.0f;
    if (fabsf(s2) < 1e-15f) s2 = 0.0f;

    *s1_ptr = s1;
    *s2_ptr = s2;
}

void c_eq_engine_process_stereo(c_eq_engine_t* eq, float* left, float* right, size_t count) {
    if (!eq || !left || !right || count == 0 || eq->is_bypassed) return;

    // 1. Vectorized Preamp Gain
    if (fabsf(eq->preamp_gain_linear - 1.0f) > 1e-4f) {
        float g = eq->preamp_gain_linear;
        vDSP_vsmul(left, 1, &g, left, 1, count);
        vDSP_vsmul(right, 1, &g, right, 1, count);
    }

    // 2. Phase Inversion (Ø 180° polarity flip on both channels)
    if (eq->phase_invert) {
        float neg = -1.0f;
        vDSP_vsmul(left, 1, &neg, left, 1, count);
        vDSP_vsmul(right, 1, &neg, right, 1, count);
    }

    // Thread-safe scratch memory for Mid/Side matrixing
    float stack_mid[2048];
    float stack_side[2048];
    float* mid_buf = stack_mid;
    float* side_buf = stack_side;
    bool allocated = false;

    if (count > 2048) {
        mid_buf = (float*)malloc(count * sizeof(float));
        side_buf = (float*)malloc(count * sizeof(float));
        allocated = true;
    }

    // 3. Cascade of Biquad Filter Bands
    for (int b = 0; b < eq->band_count; b++) {
        c_biquad_channel_t* band = &eq->bands[b];
        if (!band->is_enabled) continue;

        switch (band->routing) {
            case 0: // Stereo (both channels)
                process_biquad_single_channel(left, count, &band->current, &band->target, &band->s1_left, &band->s2_left);
                process_biquad_single_channel(right, count, &band->current, &band->target, &band->s1_right, &band->s2_right);
                break;

            case 3: // Left Only
                process_biquad_single_channel(left, count, &band->current, &band->target, &band->s1_left, &band->s2_left);
                break;

            case 4: // Right Only
                process_biquad_single_channel(right, count, &band->current, &band->target, &band->s1_right, &band->s2_right);
                break;

            case 1: // Mid Channel Only: Mid = (L + R) * 0.5, Side = (L - R) * 0.5
                c_dsp_midside_encode(left, right, mid_buf, side_buf, count);
                process_biquad_single_channel(mid_buf, count, &band->current, &band->target, &band->s1_left, &band->s2_left);
                c_dsp_midside_decode(mid_buf, side_buf, left, right, count);
                break;

            case 2: // Side Channel Only
                c_dsp_midside_encode(left, right, mid_buf, side_buf, count);
                process_biquad_single_channel(side_buf, count, &band->current, &band->target, &band->s1_right, &band->s2_right);
                c_dsp_midside_decode(mid_buf, side_buf, left, right, count);
                break;
        }
    }

    if (allocated) {
        if (mid_buf) free(mid_buf);
        if (side_buf) free(side_buf);
    }

    // 4. Vectorized Master Gain
    if (fabsf(eq->master_gain_linear - 1.0f) > 1e-4f) {
        float g = eq->master_gain_linear;
        vDSP_vsmul(left, 1, &g, left, 1, count);
        vDSP_vsmul(right, 1, &g, right, 1, count);
    }

    // 5. Monitor / Audition Mode
    if (eq->monitor_mode == 1) { // Mono Audition: (L + R) * 0.5
        float half = 0.5f;
        vDSP_vasm(left, 1, right, 1, &half, left, 1, count);
        memcpy(right, left, count * sizeof(float));
    } else if (eq->monitor_mode == 2) { // Sides Audition: (L - R) * 0.5
        for (size_t i = 0; i < count; i++) {
            float s = (left[i] - right[i]) * 0.5f;
            left[i] = s;
            right[i] = -s;
        }
    } else if (eq->monitor_mode == 3) { // Left Only
        memset(right, 0, count * sizeof(float));
    } else if (eq->monitor_mode == 4) { // Right Only
        memset(left, 0, count * sizeof(float));
    }
}

// ============================================================================
// 3. Vectorized Mid/Side Encoding & Decoding
// ============================================================================

void c_dsp_midside_encode(const float* left, const float* right, float* mid, float* side, size_t count) {
    if (!left || !right || !mid || !side || count == 0) return;
    float half = 0.5f;
    // mid = (left + right) * 0.5
    vDSP_vasm(left, 1, right, 1, &half, mid, 1, count);
    // side = (left - right) * 0.5
    vDSP_vsub(right, 1, left, 1, side, 1, count);
    vDSP_vsmul(side, 1, &half, side, 1, count);
}

void c_dsp_midside_decode(const float* mid, const float* side, float* left, float* right, size_t count) {
    if (!mid || !side || !left || !right || count == 0) return;
    // left = mid + side
    vDSP_vadd(mid, 1, side, 1, left, 1, count);
    // right = mid - side
    vDSP_vsub(side, 1, mid, 1, right, 1, count);
}

// ============================================================================
// 4. Vectorized Dynamics: Soft-Knee Peak Limiter
// ============================================================================

void c_dsp_limiter_process_stereo(float* left, float* right, size_t count, float linear_ceiling, bool enabled) {
    if (!enabled || !left || !right || count == 0) return;

    const float ceiling = linear_ceiling > 0.05f ? linear_ceiling : 0.944f;
    const float knee = ceiling * 0.85f;
    const float range = ceiling - knee;
    const float inv_range = (range > 1e-6f) ? (1.0f / range) : 1.0f;

    #pragma clang loop unroll_count(4)
    for (size_t i = 0; i < count; i++) {
        float xl = left[i];
        float xr = right[i];
        float abs_l = fabsf(xl);
        float abs_r = fabsf(xr);
        float max_peak = fmaxf(abs_l, abs_r);

        if (max_peak > knee) {
            float over = (max_peak - knee) * inv_range;
            float target = knee + range * (over / (1.0f + over));
            if (target > ceiling) target = ceiling;
            float gain = (max_peak > 1e-9f) ? (target / max_peak) : 1.0f;
            if (gain > 1.0f) gain = 1.0f;

            // Stereo-linked gain compression preserves spatial stereo image without distortion
            xl *= gain;
            xr *= gain;
        }

        // Brickwall ceiling guard for true inter-sample peaks
        if (xl > ceiling) xl = ceiling;
        else if (xl < -ceiling) xl = -ceiling;

        if (xr > ceiling) xr = ceiling;
        else if (xr < -ceiling) xr = -ceiling;

        left[i] = xl;
        right[i] = xr;
    }
}

// ============================================================================
// 5. Accelerate-Powered Telemetry: Peak, RMS & Clip Measurement
// ============================================================================

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
) {
    if (!left || !right || count == 0 || !result) return;

    // Vectorized Peak Maximum Magnitude
    float max_l = 0.0f;
    float max_r = 0.0f;
    vDSP_maxmgv(left, 1, &max_l, count);
    vDSP_maxmgv(right, 1, &max_r, count);

    // Vectorized Mean Square
    float mean_sq_l = 0.0f;
    float mean_sq_r = 0.0f;
    vDSP_measqv(left, 1, &mean_sq_l, count);
    vDSP_measqv(right, 1, &mean_sq_r, count);

    // Clip detection
    if (max_l >= 0.999f && inout_clip_l) *inout_clip_l = true;
    if (max_r >= 0.999f && inout_clip_r) *inout_clip_r = true;

    // Decibel conversions
    float curr_rms_l = (mean_sq_l > 1e-10f) ? (10.0f * log10f(mean_sq_l)) : -80.0f;
    float curr_rms_r = (mean_sq_r > 1e-10f) ? (10.0f * log10f(mean_sq_r)) : -80.0f;

    float curr_peak_l = (max_l > 1e-5f) ? (20.0f * log10f(max_l)) : -80.0f;
    float curr_peak_r = (max_r > 1e-5f) ? (20.0f * log10f(max_r)) : -80.0f;

    // Smooth peak decay
    if (inout_peak_l) {
        *inout_peak_l = (curr_peak_l > *inout_peak_l - 0.5f) ? curr_peak_l : (*inout_peak_l - 0.5f);
        result->peak_left_db = *inout_peak_l;
    } else {
        result->peak_left_db = curr_peak_l;
    }

    if (inout_peak_r) {
        *inout_peak_r = (curr_peak_r > *inout_peak_r - 0.5f) ? curr_peak_r : (*inout_peak_r - 0.5f);
        result->peak_right_db = *inout_peak_r;
    } else {
        result->peak_right_db = curr_peak_r;
    }

    // Smooth RMS
    if (inout_rms_l) {
        *inout_rms_l += (curr_rms_l - *inout_rms_l) * 0.2f;
        result->rms_left_db = *inout_rms_l;
    } else {
        result->rms_left_db = curr_rms_l;
    }

    if (inout_rms_r) {
        *inout_rms_r += (curr_rms_r - *inout_rms_r) * 0.2f;
        result->rms_right_db = *inout_rms_r;
    } else {
        result->rms_right_db = curr_rms_r;
    }

    result->clip_left = inout_clip_l ? *inout_clip_l : false;
    result->clip_right = inout_clip_r ? *inout_clip_r : false;
}

// ============================================================================
// 6. Vector Utility Functions
// ============================================================================

void c_dsp_downmix_stereo_to_mono(const float* left, const float* right, float* mono, size_t count) {
    if (!left || !right || !mono || count == 0) return;
    float half = 0.5f;
    vDSP_vasm(left, 1, right, 1, &half, mono, 1, count);
}

void c_dsp_apply_gain(float* buffer, float gain, size_t count) {
    if (!buffer || count == 0) return;
    vDSP_vsmul(buffer, 1, &gain, buffer, 1, count);
}

void c_dsp_interleave_stereo(const float* left, const float* right, float* interleaved, size_t count) {
    if (!left || !right || !interleaved || count == 0) return;
#ifdef __APPLE__
    DSPSplitComplex split = { (float*)left, (float*)right };
    vDSP_ztoc(&split, 1, (DSPComplex*)interleaved, 2, count);
#else
    for (size_t i = 0; i < count; i++) {
        interleaved[2 * i] = left[i];
        interleaved[2 * i + 1] = right[i];
    }
#endif
}

void c_dsp_deinterleave_stereo(const float* interleaved, float* left, float* right, size_t count) {
    if (!interleaved || !left || !right || count == 0) return;
#ifdef __APPLE__
    DSPSplitComplex split = { (float*)left, (float*)right };
    vDSP_ctoz((const DSPComplex*)interleaved, 2, &split, 1, count);
#else
    for (size_t i = 0; i < count; i++) {
        left[i] = interleaved[2 * i];
        right[i] = interleaved[2 * i + 1];
    }
#endif
}
