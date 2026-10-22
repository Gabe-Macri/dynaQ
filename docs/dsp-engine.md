# EQ & Signal Processing

The `DynaQDSP` module implements parametric equalization, dynamic gain modulation, frequency modulation (FM EQ), soft-knee headroom guarding, spectral telemetry, and ITU-R BS.1770 loudness monitoring.

---

## Parametric Equalizer

dynaQ supports up to 16 arbitrary biquad filter bands per profile. Each band can be assigned independent routing targets and operational modes:
- **Stereo**: Processes Left and Right channels uniformly.
- **Mid**: Processes correlated center information ($\text{L} + \text{R}$).
- **Side**: Processes stereophonic differential ($\text{L} - \text{R}$).
- **Left Only / Right Only**: Isolates individual stereo channels.
- **Band Solo**: Isolates the selected band's passband for critical acoustic auditing while muting outside spectrum energy.

---

## RBJ Biquad Filter Mathematics

Filter coefficients derive from Robert Bristow-Johnson (RBJ) Audio EQ Cookbook equations:

### Intermediate Variables

Given sample rate $f_s$, center frequency $f_0$, quality factor $Q$, and gain $G\text{ (dB)}$:

$$\omega_0 = 2\pi \frac{f_0}{f_s}, \quad \alpha = \frac{\sin(\omega_0)}{2Q}, \quad A = 10^{\frac{G}{40}}$$

### Filter Topologies

| Topology | Feedforward ($b_0, b_1, b_2$) | Feedback ($a_0, a_1, a_2$) |
| :--- | :--- | :--- |
| **Peaking (Bell)** | $b_0 = 1 + \alpha A$<br>$b_1 = -2\cos(\omega_0)$<br>$b_2 = 1 - \alpha A$ | $a_0 = 1 + \frac{\alpha}{A}$<br>$a_1 = -2\cos(\omega_0)$<br>$a_2 = 1 - \frac{\alpha}{A}$ |
| **Low Shelf** | $b_0 = A \left[ (A+1) - (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha \right]$<br>$b_1 = 2A \left[ (A-1) - (A+1)\cos(\omega_0) \right]$<br>$b_2 = A \left[ (A+1) - (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha \right]$ | $a_0 = (A+1) + (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha$<br>$a_1 = -2 \left[ (A-1) + (A+1)\cos(\omega_0) \right]$<br>$a_2 = (A+1) + (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha$ |
| **High Shelf** | $b_0 = A \left[ (A+1) + (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha \right]$<br>$b_1 = -2A \left[ (A-1) + (A+1)\cos(\omega_0) \right]$<br>$b_2 = A \left[ (A+1) + (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha \right]$ | $a_0 = (A+1) - (A-1)\cos(\omega_0) + 2\sqrt{A}\alpha$<br>$a_1 = 2 \left[ (A-1) - (A+1)\cos(\omega_0) \right]$<br>$a_2 = (A+1) - (A-1)\cos(\omega_0) - 2\sqrt{A}\alpha$ |
| **High Pass (Low Cut)** | $b_0 = \frac{1 + \cos(\omega_0)}{2}, \quad b_1 = -(1 + \cos(\omega_0)), \quad b_2 = \frac{1 + \cos(\omega_0)}{2}$ | $a_0 = 1 + \alpha, \quad a_1 = -2\cos(\omega_0), \quad a_2 = 1 - \alpha$ |
| **Low Pass (High Cut)** | $b_0 = \frac{1 - \cos(\omega_0)}{2}, \quad b_1 = 1 - \cos(\omega_0), \quad b_2 = \frac{1 - \cos(\omega_0)}{2}$ | $a_0 = 1 + \alpha, \quad a_1 = -2\cos(\omega_0), \quad a_2 = 1 - \alpha$ |

---

## Frequency Modulation (FM EQ)

In addition to static biquads, bands can modulate their center frequency in real time via two modes:

```
                      +-----------------------------+
                      |     Modulation Mode Mux     |
                      +-----------------------------+
                                     |
               +---------------------+---------------------+
               |                                           |
               v                                           v
      [.envelope Mode]                                [.lfo Mode]
+-----------------------------+             +-----------------------------+
| Bandpass Sidechain Detector |             | Phase Accumulator (θ[n])    |
+-----------------------------+             +-----------------------------+
               |                                           |
               v                                           v
| Transient Magnitude ΔE      |             | Sinusoidal Offset: sin(θ[n])|
+-----------------------------+             +-----------------------------+
               |                                           |
               +---------------------+---------------------+
                                     |
                                     v
                  f_target = f_0 · 2^(offset · depth)
                                     |
                                     v
                     Dynamic Biquad Recalculation
```

### 1. Envelope Follower Mode (`.envelope`)
Modulates the band center frequency dynamically based on signal transients:

$$f_{\text{target}} = f_0 \cdot 2^{(\Delta E \cdot \text{octaves})}$$

Where $\Delta E$ is the normalized envelope level above threshold ($0.0 \le \Delta E \le 1.0$), and $\text{octaves}$ defines the maximum sweep range ($\pm 3.0\text{ octaves}$).

### 2. LFO Sweep Mode (`.lfo`)
Modulates center frequency with a continuous low-frequency oscillator:

$$\theta[n] = \left(\theta[n-1] + 2\pi \frac{f_{\text{lfo}}}{f_s}\right) \pmod{2\pi}$$
$$f[n] = f_0 \cdot 2^{(\sin(\theta[n]) \cdot \text{depth})}$$

- **LFO Rate**: Configurable from $0.1\text{ Hz}$ to $20.0\text{ Hz}$.
- **Depth**: Configurable from $\pm 0.1$ to $\pm 3.0\text{ octaves}$.

---

## Dynamic Gain Modulation

Dynamic bands evaluate energy in their passband and modulate gain based on attack/release ballistics:

```
Incoming Audio ---> [ Bandpass Sidechain Filter ] ---> [ Envelope Detector ] ---> [ Gain Transfer ] ---> Biquad Gain
```

### Ballistics Formulation

$$\alpha_{\text{attack}} = \exp\left(-\frac{1}{\tau_{\text{attack}} \cdot f_s}\right), \quad \alpha_{\text{release}} = \exp\left(-\frac{1}{\tau_{\text{release}} \cdot f_s}\right)$$

$$e[n] = \begin{cases}
\alpha_{\text{attack}} e[n-1] + (1 - \alpha_{\text{attack}}) |x[n]| & \text{if } |x[n]| > e[n-1] \\
\alpha_{\text{release}} e[n-1] + (1 - \alpha_{\text{release}}) |x[n]| & \text{if } |x[n]| \le e[n-1]
\end{cases}$$

When sidechain envelope $e_{\text{dB}} = 20 \log_{10}(e[n])$ exceeds threshold $T_{\text{dB}}$:

$$\Delta G_{\text{target}} = \left( 1 - \frac{1}{R} \right) (T_{\text{dB}} - e_{\text{dB}})$$

---

## Anti-Clip Headroom Guard

Aggressive dynamic equalization and high-Q resonant boosts can drive inter-stage audio levels above $0\text{ dBFS}$. To prevent harsh digital clipping before the lookahead limiter, dynaQ provides a $+3.0\text{ dB}$ anti-clip headroom buffer with a rational soft-knee saturation transfer:

$$y = \begin{cases}
x & \text{if } |x| \le x_{\text{knee}} \\
\text{sgn}(x) \left( x_{\text{knee}} + (1 - x_{\text{knee}}) \tanh\left(\frac{|x| - x_{\text{knee}}}{1 - x_{\text{knee}}}\right) \right) & \text{if } |x| > x_{\text{knee}}
\end{cases}$$

Where $x_{\text{knee}} = 0.891\text{ (-1.0 dBFS)}$. This preserves transient punch while softly rounding off aggressive peaks.

---

## Spectral Analysis and Loudness

### 1024-Point FFT Visualizer
Real-time frequency telemetry uses Apple Accelerate's `vDSP_DFT_Execute`:
1. Audio blocks are windowed with a 1024-point periodic Hann function (`vDSP_hann_window`).
2. Forward complex discrete Fourier transform produces 512 real frequency bins.
3. Magnitudes are evaluated via `vDSP_zvabs` and converted to dBFS.
4. Linear bins map logarithmically into 64 display columns ($20\text{ Hz}$ to $20\text{ kHz}$) with peak decay physics.
5. Telemetry frames render through a single zero-allocation SwiftUI `Canvas` at 60–120 FPS.

### ITU-R BS.1770 / EBU R128 Loudness
Loudness monitoring uses standard two-stage K-weighting:
1. **Stage 1 (Head Diffraction)**: High-shelf filter (+4.0 dB at 1.5 kHz).
2. **Stage 2 (Auditory Contour)**: High-pass filter (-3.0 dB at 38 Hz).
3. Evaluates Momentary ($400\text{ ms}$ window), Short-Term ($3\text{ s}$ window), and Integrated LUFS.
