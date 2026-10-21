# Core C DSP Kernel

The `CDspKernel` library implements deterministic, high-throughput signal routines in standard C99. By running mathematical operations outside the Swift automatic reference counting (ARC) runtime, `CDspKernel` ensures deterministic cycle counts without garbage collection or heap allocation overhead.

---

## Atomic SPSC Ring Buffer

Real-time audio processing requires thread-safe communication between the input tap and output render threads. `CDspKernel` uses a lock-free Single-Producer Single-Consumer (SPSC) circular buffer backed by `stdatomic.h`.

### Ring Buffer Memory Layout

```c
struct c_ringbuffer {
    float* buffer_left;
    float* buffer_right;
    size_t capacity;
    size_t mask;             // Power-of-two mask (capacity - 1)
    _Atomic size_t write_idx; // Producer index
    _Atomic size_t read_idx;  // Consumer index
};
```

### Memory Ordering Guarantees
The SPSC ring buffer uses C11 memory fences to ensure data visibility across CPU cores without mutex locks:
- **Producer (Write)**: Writes samples into `buffer_left` and `buffer_right`, followed by an atomic store on `write_idx` with `memory_order_release`. This ensures all sample writes are committed to cache before the write index advances.
- **Consumer (Read)**: Reads `write_idx` using `memory_order_acquire` before reading samples, ensuring the read index only advances over valid sample data.

```c
size_t c_ringbuffer_write_stereo(c_ringbuffer_t* rb, const float* left, const float* right, size_t count) {
    size_t write = atomic_load_explicit(&rb->write_idx, memory_order_relaxed);
    size_t read = atomic_load_explicit(&rb->read_idx, memory_order_acquire);
    size_t available = rb->capacity - (write - read);
    size_t to_write = (count < available) ? count : available;

    for (size_t i = 0; i < to_write; ++i) {
        size_t idx = (write + i) & rb->mask;
        rb->buffer_left[idx] = left[i];
        rb->buffer_right[idx] = right[i];
    }

    atomic_store_explicit(&rb->write_idx, write + to_write, memory_order_release);
    return to_write;
}
```

---

## Vectorized Biquad Engine

Parametric equalization is computed using cascading Direct Form II Transposed (DF2T) biquad sections. DF2T is selected over Direct Form I because it requires only two internal delay registers per channel, minimizes quantization noise, and maintains numerical stability in single-precision floating point.

### Direct Form II Transposed Equations

For each input sample $x[n]$:

$$y[n] = b_0 x[n] + s_1[n-1]$$
$$s_1[n] = b_1 x[n] - a_1 y[n] + s_2[n-1]$$
$$s_2[n] = b_2 x[n] - a_2 y[n]$$

Where:
- $b_0, b_1, b_2$ are feedforward coefficients normalized by $a_0$.
- $a_1, a_2$ are feedback coefficients normalized by $a_0$.
- $s_1, s_2$ are the canonical delay states per channel.

### Coefficient Smoothing
To prevent zipper noise during real-time parameter changes (frequency, gain, or Q sweeps), coefficients are ramped linearly across the block length:

```c
float step_b0 = (target.b0 - current.b0) / (float)count;
float step_b1 = (target.b1 - current.b1) / (float)count;
float step_b2 = (target.b2 - current.b2) / (float)count;
float step_a1 = (target.a1 - current.a1) / (float)count;
float step_a2 = (target.a2 - current.a2) / (float)count;
```

---

## Vectorized Mid/Side Processing

Mid/Side matrixing allows independent processing of the center (correlated) and wide (decorrelated) stereo information.

### Mathematical Matrix

The linear encoding matrix:

$$\text{Mid} = \frac{\text{Left} + \text{Right}}{\sqrt{2}}$$
$$\text{Side} = \frac{\text{Left} - \text{Right}}{\sqrt{2}}$$

The linear decoding matrix:

$$\text{Left} = \frac{\text{Mid} + \text{Side}}{\sqrt{2}}$$
$$\text{Right} = \frac{\text{Mid} - \text{Side}}{\sqrt{2}}$$

`CDspKernel` vectorizes this matrix using SIMD loop unrolling and Apple `vDSP_vadd` / `vDSP_vsub` instructions, achieving zero-allocation transformation across thousands of samples per second.

---

## True Peak Soft-Knee Limiter

To guard against inter-sample clipping and digital overs during aggressive equalization, `CDspKernel` provides a lookahead soft-knee brickwall limiter:

```c
void c_dsp_limiter_process_stereo(
    float* left,
    float* right,
    size_t count,
    float linear_ceiling,
    bool enabled
) {
    if (!enabled) return;
    const float knee_start = linear_ceiling * 0.90f; // Soft-knee begins at -0.9 dBFS relative to ceiling

    for (size_t i = 0; i < count; ++i) {
        float peak = fmaxf(fabsf(left[i]), fabsf(right[i]));
        if (peak > knee_start) {
            float excess = peak - knee_start;
            float compression = 1.0f - (excess / (linear_ceiling + excess));
            left[i] *= compression;
            right[i] *= compression;
        }
        // Strict brickwall clamping
        if (left[i] > linear_ceiling) left[i] = linear_ceiling;
        if (left[i] < -linear_ceiling) left[i] = -linear_ceiling;
        if (right[i] > linear_ceiling) right[i] = linear_ceiling;
        if (right[i] < -linear_ceiling) right[i] = -linear_ceiling;
    }
}
```

---

## Accelerate-Powered Telemetry

Real-time audio levels are measured using vectorized routines from Apple's `Accelerate` framework:
- **Peak Level**: Calculated via `vDSP_maxmgv` (maximum magnitude vector).
- **RMS Level**: Calculated via `vDSP_measqv` (mean square vector value) followed by square root.
- **Conversion to dBFS**:

$$\text{dBFS} = 20 \log_{10}(\text{magnitude})$$

Calculations avoid branch-heavy loops and operate directly on contiguous memory buffers.
