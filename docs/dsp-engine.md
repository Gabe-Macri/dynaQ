# EQ & Signal Processing

The `DynaQDSP` module implements parametric equalization, dynamic frequency-selective compression, spectral telemetry, and ITU-R BS.1770 loudness monitoring.

---

## Parametric Equalizer

dynaQ supports up to 16 arbitrary biquad filter bands per profile. Each band can be assigned independent routing targets:
- **Stereo**: Processes Left and Right channels uniformly.
- **Mid**: Processes only the center channel (Left + Right).
- **Side**: Processes only the stereophonic differential (Left - Right).
- **Left Only**: Targets the left channel exclusively.
- **Right Only**: Targets the right channel exclusively.

---

## RBJ Biquad Filter Mathematics

Coefficients are calculated using the Robert Bristow-Johnson (RBJ) Audio EQ Cookbook derivations:

### Common Intermediate Variables

Given sample rate $f_s$, center frequency $f_0$, quality factor $Q$, and gain in decibels $G$:

$$\omega_0 = 2\pi \frac{f_0}{f_s}$$
$$\alpha = \frac{\sin(\omega_0)}{2Q}$$
$$A = 10^{\frac{G}{40}} = \sqrt{10^{\frac{G}{20}}}$$

### Peaking (Bell) Filter

$$b_0 = 1 + \alpha A, \quad b_1 = -2\cos(\omega_0), \quad b_2 = 1 - \alpha A$$
$$a_0 = 1 + \frac{\alpha}{A}, \quad a_1 = -2\cos(\omega_0), \quad a_2 = 1 - \frac{\alpha}{A}$$

### Low Shelf Filter

$$b_0 = A \left[ (A+1) - (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha \right]$$
$$b_1 = 2A \left[ (A-1) - (A+1)\cos(\omega_0) \right]$$
$$b_2 = A \left[ (A+1) - (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha \right]$$
$$a_0 = (A+1) + (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha$$
$$a_1 = -2 \left[ (A-1) + (A+1)\cos(\omega_0) \right]$$
$$a_2 = (A+1) + (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha$$

### High Shelf Filter

$$b_0 = A \left[ (A+1) + (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha \right]$$
$$b_1 = -2A \left[ (A-1) + (A+1)\cos(\omega_0) \right]$$
$$b_2 = A \left[ (A+1) + (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha \right]$$
$$a_0 = (A+1) - (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha$$
$$a_1 = 2 \left[ (A-1) - (A+1)\cos(\omega_0) \right]$$
$$a_2 = (A+1) - (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha$$

### High-Pass (Low Cut) Filter

$$b_0 = \frac{1 + \cos(\omega_0)}{2}, \quad b_1 = -(1 + \cos(\omega_0)), \quad b_2 = \frac{1 + \cos(\omega_0)}{2}$$
$$a_0 = 1 + \alpha, \quad a_1 = -2\cos(\omega_0), \quad a_2 = 1 - \alpha$$

### Low-Pass (High Cut) Filter

$$b_0 = \frac{1 - \cos(\omega_0)}{2}, \quad b_1 = 1 - \cos(\omega_0), \quad b_2 = \frac{1 - \cos(\omega_0)}{2}$$
$$a_0 = 1 + \alpha, \quad a_1 = -2\cos(\omega_0), \quad a_2 = 1 - \alpha$$

---

## Dynamic EQ Envelope Tracking

Each parametric band can operate in dynamic mode, modulating its gain based on the instantaneous energy within its passband.

```
Incoming Audio ---> [ Bandpass Sidechain Filter ]
                              |
                              v
                   [ Absolute Level Detector ]
                              |
                              v
                  [ Attack / Release Ballistics ]
                              |
                              v
                  [ Gain Modulation Transfer ]
                              |
                              +---> Modulates Target Biquad Gain
```

### Attack and Release Ballistics

The envelope detector smooths the detected magnitude using continuous time constants:

$$\alpha_{\text{attack}} = \exp\left(-\frac{1}{\tau_{\text{attack}} \cdot f_s}\right)$$
$$\alpha_{\text{release}} = \exp\left(-\frac{1}{\tau_{\text{release}} \cdot f_s}\right)$$

For each sample:

$$e[n] = \begin{cases}
\alpha_{\text{attack}} e[n-1] + (1 - \alpha_{\text{attack}}) |x[n]| & \text{if } |x[n]| > e[n-1] \\
\alpha_{\text{release}} e[n-1] + (1 - \alpha_{\text{release}}) |x[n]| & \text{if } |x[n]| \le e[n-1]
\end{cases}$$

### Dynamic Transfer Function

When the sidechain envelope $e_{\text{dB}} = 20 \log_{10}(e[n])$ exceeds the band threshold $T_{\text{dB}}$:

$$\Delta G_{\text{target}} = \left( 1 - \frac{1}{R} \right) (T_{\text{dB}} - e_{\text{dB}})$$

Where $R$ is the dynamic ratio (e.g., 2:1, 4:1) and the maximum dynamic deviation is constrained by the user-defined dynamic range parameter.

---

## Spectral Analysis and Loudness

### 1024-Point FFT Visualizer
Real-time frequency telemetry uses Apple Accelerate's `vDSP_DFT_Execute`:
1. Audio blocks are windowed with a 1024-point periodic Hann function (`vDSP_hann_window`).
2. Forward complex discrete Fourier transform produces 512 real frequency bins.
3. Magnitudes are evaluated via `vDSP_zvabs` and scaled to dBFS.
4. Linear frequency bins are mapped logarithmically into 64 display columns spanning 20 Hz to 20,000 Hz, with peak decay physics running at 60 fps.

### ITU-R BS.1770 / EBU R128 Loudness
Loudness monitoring uses standard K-weighting:
1. **Stage 1**: High-shelf filter modeling head diffraction (+4.0 dB at 1.5 kHz).
2. **Stage 2**: High-pass filter modeling human auditory response (-3.0 dB at 38 Hz).
3. Mean square calculation across gated 400 ms momentary windows and integrated long-term buffers.

