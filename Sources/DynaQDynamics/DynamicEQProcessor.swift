import Foundation
import DynaQCore

/// Professional Dynamic Equalizer Envelope Detection and Gain Modulation Engine.
/// Detects sidechain signal energy with an integrated frequency-selective sidechain bandpass filter
/// and applies precision upward/downward dynamic gain offsets with smooth ballistic smoothing,
/// anti-denormal protection, and NaN containment.
public final class DynamicEQProcessor: @unchecked Sendable {
    private var envelope: Float = 0.0
    private var currentGainOffset: Float = 0.0

    // Sidechain 2nd-order Direct Form II Transposed Bandpass Filter State
    private var lastScFreq: Float = 0.0
    private var lastScQ: Float = 0.0
    private var lastScSR: Float = 0.0
    private var sc_b0: Float = 1.0
    private var sc_b1: Float = 0.0
    private var sc_b2: Float = -1.0
    private var sc_a1: Float = 0.0
    private var sc_a2: Float = 0.0
    private var sc_s1: Float = 0.0
    private var sc_s2: Float = 0.0

    public private(set) var currentDynamicGainReduction: Float = 0.0

    public init() {}

    public func reset() {
        envelope = 0.0
        currentGainOffset = 0.0
        currentDynamicGainReduction = 0.0
        sc_s1 = 0.0
        sc_s2 = 0.0
        lastScFreq = 0.0
        lastScQ = 0.0
        lastScSR = 0.0
    }

    private func updateSidechainCoeffs(freq: Float, q: Float, sampleRate: Float) {
        guard freq != lastScFreq || q != lastScQ || sampleRate != lastScSR else { return }
        lastScFreq = freq
        lastScQ = q
        lastScSR = sampleRate

        let nyquist = sampleRate * 0.495
        let clampedFreq = min(max(freq, 20.0), nyquist)
        let clampedQ = max(q, 0.2)

        let w0 = 2.0 * Float.pi * (clampedFreq / sampleRate)
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * clampedQ)

        let a0 = 1.0 + alpha
        let invA0 = (abs(a0) > 1e-6) ? (1.0 / a0) : 1.0

        sc_b0 = alpha * invA0
        sc_b1 = 0.0
        sc_b2 = -alpha * invA0
        sc_a1 = (-2.0 * cosW0) * invA0
        sc_a2 = (1.0 - alpha) * invA0
    }

    /// Evaluates a block of stereo audio with channel-aware sidechain detection
    /// and calculates dynamic gain adjustment in dB.
    public func processStereoBlock(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        count: Int,
        sampleRate: Float,
        band: EQBand
    ) -> Float {
        guard band.isDynamic, band.isEnabled, count > 0, sampleRate > 0 else {
            currentDynamicGainReduction = 0.0
            return 0.0
        }

        var peak: Float = 0.0

        if band.useSidechainFilter {
            updateSidechainCoeffs(freq: band.frequency, q: band.q, sampleRate: sampleRate)
            var s1 = sc_s1
            var s2 = sc_s2
            let b0 = sc_b0
            let b2 = sc_b2
            let a1 = sc_a1
            let a2 = sc_a2

            for i in 0..<count {
                let l = left[i]
                let r = right[i]
                let scInput: Float
                switch band.routing {
                case .stereo:
                    scInput = 0.5 * (l + r)
                case .mid:
                    scInput = 0.5 * (l + r)
                case .side:
                    scInput = 0.5 * (l - r)
                case .left:
                    scInput = l
                case .right:
                    scInput = r
                }

                let y = b0 * scInput + s1
                s1 = -a1 * y + s2
                s2 = b2 * scInput - a2 * y

                let mag = abs(y)
                if mag > peak && !mag.isNaN && !mag.isInfinite {
                    peak = mag
                }
            }

            if abs(s1) < 1e-15 || s1.isNaN { s1 = 0.0 }
            if abs(s2) < 1e-15 || s2.isNaN { s2 = 0.0 }
            sc_s1 = s1
            sc_s2 = s2
        } else {
            for i in 0..<count {
                let l = left[i]
                let r = right[i]
                let scInput: Float
                switch band.routing {
                case .stereo:
                    scInput = max(abs(l), abs(r))
                case .mid:
                    scInput = abs(0.5 * (l + r))
                case .side:
                    scInput = abs(0.5 * (l - r))
                case .left:
                    scInput = abs(l)
                case .right:
                    scInput = abs(r)
                }

                if scInput > peak && !scInput.isNaN && !scInput.isInfinite {
                    peak = scInput
                }
            }
        }

        return calculateDynamicOffset(peak: peak, count: count, sampleRate: sampleRate, band: band)
    }

    /// Evaluates a block of single-channel audio and calculates dynamic gain adjustment in dB.
    public func processBlock(
        samples: UnsafePointer<Float>,
        count: Int,
        sampleRate: Float,
        band: EQBand
    ) -> Float {
        guard band.isDynamic, band.isEnabled, count > 0, sampleRate > 0 else {
            currentDynamicGainReduction = 0.0
            return 0.0
        }

        var peak: Float = 0.0

        if band.useSidechainFilter {
            updateSidechainCoeffs(freq: band.frequency, q: band.q, sampleRate: sampleRate)
            var s1 = sc_s1
            var s2 = sc_s2
            let b0 = sc_b0
            let b2 = sc_b2
            let a1 = sc_a1
            let a2 = sc_a2

            for i in 0..<count {
                let x = samples[i]
                let y = b0 * x + s1
                s1 = -a1 * y + s2
                s2 = b2 * x - a2 * y

                let mag = abs(y)
                if mag > peak && !mag.isNaN && !mag.isInfinite {
                    peak = mag
                }
            }

            if abs(s1) < 1e-15 || s1.isNaN { s1 = 0.0 }
            if abs(s2) < 1e-15 || s2.isNaN { s2 = 0.0 }
            sc_s1 = s1
            sc_s2 = s2
        } else {
            for i in 0..<count {
                let v = abs(samples[i])
                if v > peak && !v.isNaN && !v.isInfinite {
                    peak = v
                }
            }
        }

        return calculateDynamicOffset(peak: peak, count: count, sampleRate: sampleRate, band: band)
    }

    private func calculateDynamicOffset(
        peak: Float,
        count: Int,
        sampleRate: Float,
        band: EQBand
    ) -> Float {
        // Ballistics time constants
        let attackSec = max(band.attackMs * 0.001, 0.0005)
        let releaseSec = max(band.releaseMs * 0.001, 0.005)
        let blockTimeSec = Float(count) / sampleRate

        let attackCoeff = 1.0 - exp(-blockTimeSec / attackSec)
        let releaseCoeff = 1.0 - exp(-blockTimeSec / releaseSec)

        // Envelope detection with denormal guard
        if peak > envelope {
            envelope += (peak - envelope) * attackCoeff
        } else {
            envelope += (peak - envelope) * releaseCoeff
        }

        if envelope.isNaN || envelope.isInfinite || abs(envelope) < 1e-15 {
            envelope = 0.0
        }

        // Convert envelope to dBFS
        let envDB = envelope > 1e-5 ? 20.0 * log10(envelope) : -100.0

        var targetDelta: Float = 0.0
        if envDB > band.dynamicThreshold {
            let overShoot = envDB - band.dynamicThreshold
            let ratio = max(band.dynamicRatio, 1.0)
            let rawCompression = overShoot * (1.0 - 1.0 / ratio)

            // Dynamic range clamp
            if band.dynamicRange < 0 {
                // Downward compression (de-essing, controlling resonant peaks)
                targetDelta = -min(rawCompression, abs(band.dynamicRange))
            } else {
                // Upward expansion
                targetDelta = min(rawCompression, band.dynamicRange)
            }
        }

        // Low-pass smoothing on gain offset
        currentGainOffset += (targetDelta - currentGainOffset) * 0.2
        if currentGainOffset.isNaN || currentGainOffset.isInfinite {
            currentGainOffset = 0.0
        }

        currentDynamicGainReduction = currentGainOffset
        return currentGainOffset
    }
}

