import Foundation
import Accelerate

/// High-performance stereo Direct-Form II Transposed Biquad Filter.
public final class BiquadFilter: @unchecked Sendable {
    private var targetCoeffs: BiquadCoefficients = .bypass
    private var currentCoeffs: BiquadCoefficients = .bypass

    // State memory for Direct Form II Transposed: Left (0) and Right (1)
    private var s1: (Float, Float) = (0.0, 0.0)
    private var s2: (Float, Float) = (0.0, 0.0)

    public var isBypassed: Bool = false

    public init() {}

    /// Updates target coefficients. If immediate is true, coefficients snap without ramping.
    public func setCoefficients(_ coeffs: BiquadCoefficients, immediate: Bool = false) {
        self.targetCoeffs = coeffs
        if immediate {
            self.currentCoeffs = coeffs
        }
    }

    /// Reset internal filter state (prevents clicks when switching presets).
    public func resetState() {
        s1 = (0.0, 0.0)
        s2 = (0.0, 0.0)
    }

    /// In-place processing for single channel buffer.
    public func process(buffer: UnsafeMutablePointer<Float>, count: Int, channel: Int) {
        guard !isBypassed else { return }

        // Quick ramp coefficients toward target
        currentCoeffs.b0 += (targetCoeffs.b0 - currentCoeffs.b0) * 0.1
        currentCoeffs.b1 += (targetCoeffs.b1 - currentCoeffs.b1) * 0.1
        currentCoeffs.b2 += (targetCoeffs.b2 - currentCoeffs.b2) * 0.1
        currentCoeffs.a1 += (targetCoeffs.a1 - currentCoeffs.a1) * 0.1
        currentCoeffs.a2 += (targetCoeffs.a2 - currentCoeffs.a2) * 0.1

        let b0 = currentCoeffs.b0
        let b1 = currentCoeffs.b1
        let b2 = currentCoeffs.b2
        let a1 = currentCoeffs.a1
        let a2 = currentCoeffs.a2

        var state1 = (channel == 0) ? s1.0 : s1.1
        var state2 = (channel == 0) ? s2.0 : s2.1

        for i in 0..<count {
            let x = buffer[i]
            let y = b0 * x + state1
            state1 = b1 * x - a1 * y + state2
            state2 = b2 * x - a2 * y
            buffer[i] = y
        }

        // Anti-denormal flushing
        if abs(state1) < 1e-15 { state1 = 0.0 }
        if abs(state2) < 1e-15 { state2 = 0.0 }

        if channel == 0 {
            s1.0 = state1
            s2.0 = state2
        } else {
            s1.1 = state1
            s2.1 = state2
        }
    }
}

