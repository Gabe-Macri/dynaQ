import Foundation
import DynaQCore

/// Professional Dynamic Equalizer Envelope Detection and Gain Modulation Engine.
/// Detects sidechain signal energy and applies precision upward/downward dynamic gain offsets
/// with smooth ballistic smoothing, anti-denormal protection, and NaN containment.
public final class DynamicEQProcessor: @unchecked Sendable {
    private var envelope: Float = 0.0
    private var currentGainOffset: Float = 0.0

    public private(set) var currentDynamicGainReduction: Float = 0.0

    public init() {}

    public func reset() {
        envelope = 0.0
        currentGainOffset = 0.0
        currentDynamicGainReduction = 0.0
    }

    /// Evaluates a block of audio and calculates dynamic gain adjustment in dB.
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

        // Fast peak search
        var peak: Float = 0.0
        for i in 0..<count {
            let v = abs(samples[i])
            if v > peak && !v.isNaN && !v.isInfinite {
                peak = v
            }
        }

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

