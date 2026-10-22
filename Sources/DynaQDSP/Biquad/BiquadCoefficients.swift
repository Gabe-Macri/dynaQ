import Foundation
import DynaQCore

/// Normalized Biquad Filter Coefficients:
/// y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
public struct BiquadCoefficients: Sendable, Equatable {
    public var b0: Float
    public var b1: Float
    public var b2: Float
    public var a1: Float
    public var a2: Float

    public init(b0: Float = 1.0, b1: Float = 0.0, b2: Float = 0.0, a1: Float = 0.0, a2: Float = 0.0) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public static let bypass = BiquadCoefficients(b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)

    /// Computes coefficients based on the Robert Bristow-Johnson Audio EQ Cookbook.
    public static func calculate(
        type: FilterType,
        frequency: Float,
        gainDB: Float,
        q: Float,
        sampleRate: Float
    ) -> BiquadCoefficients {
        guard sampleRate > 0 else { return .bypass }

        // Clamp Nyquist limit
        let nyquist = sampleRate * 0.495
        let clampedFreq = min(max(frequency, 10.0), nyquist)
        let clampedQ = max(q, 0.05)

        let w0 = 2.0 * Float.pi * (clampedFreq / sampleRate)
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * clampedQ)

        // Gain factor A = 10^(gainDB / 40)
        let A = pow(10.0, gainDB / 40.0)

        var b0: Float = 1.0
        var b1: Float = 0.0
        var b2: Float = 0.0
        var a0: Float = 1.0
        var a1: Float = 0.0
        var a2: Float = 0.0

        switch type {
        case .bell:
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosW0
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha / A

        case .lowShelf:
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha)
            b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)
            b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha)
            a0 = (A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha
            a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0)
            a2 = (A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha

        case .highShelf:
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha)
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)
            b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha)
            a0 = (A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0)
            a2 = (A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha

        case .lowPass:
            b0 = (1.0 - cosW0) * 0.5
            b1 = 1.0 - cosW0
            b2 = (1.0 - cosW0) * 0.5
            a0 = 1.0 + alpha
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha

        case .highPass:
            b0 = (1.0 + cosW0) * 0.5
            b1 = -(1.0 + cosW0)
            b2 = (1.0 + cosW0) * 0.5
            a0 = 1.0 + alpha
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha

        case .notch:
            b0 = 1.0
            b1 = -2.0 * cosW0
            b2 = 1.0
            a0 = 1.0 + alpha
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha

        case .bandPass:
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
            a0 = 1.0 + alpha
            a1 = -2.0 * cosW0
            a2 = 1.0 - alpha
        }

        // Normalize so a0 == 1.0
        guard a0 != 0.0 else { return .bypass }
        let invA0 = 1.0 / a0
        let coeffs = BiquadCoefficients(
            b0: b0 * invA0,
            b1: b1 * invA0,
            b2: b2 * invA0,
            a1: a1 * invA0,
            a2: a2 * invA0
        )

        // Validate pole stability: if poles lie on/outside unit circle, fail-safe to bypass
        return coeffs.isStable ? coeffs : .bypass
    }

    /// Verifies stability according to the Jury / Schur-Cohn criterion (|z_poles| < 1.0).
    public var isStable: Bool {
        if a1.isNaN || a2.isNaN || a1.isInfinite || a2.isInfinite { return false }
        if abs(a2) >= 0.9999 { return false }
        if 1.0 + a1 + a2 <= 0.0001 { return false }
        if 1.0 - a1 + a2 <= 0.0001 { return false }
        return true
    }

    /// Evaluates the analytical magnitude response in decibels (dB) at a target frequency.
    public func magnitudeResponse(at frequency: Float, sampleRate: Float) -> Float {
        let w = 2.0 * Float.pi * (frequency / sampleRate)
        let cosW = cos(w)
        let cos2W = cos(2.0 * w)
        let sinW = sin(w)
        let sin2W = sin(2.0 * w)

        // Numerator N(e^jw) = b0 + b1*e^-jw + b2*e^-2jw
        let numReal = b0 + b1 * cosW + b2 * cos2W
        let numImag = -(b1 * sinW + b2 * sin2W)
        let numMagSq = numReal * numReal + numImag * numImag

        // Denominator D(e^jw) = 1 + a1*e^-jw + a2*e^-2jw
        let denReal = 1.0 + a1 * cosW + a2 * cos2W
        let denImag = -(a1 * sinW + a2 * sin2W)
        let denMagSq = denReal * denReal + denImag * denImag

        guard denMagSq > 1e-12 else { return 0.0 }
        let magRatio = sqrt(numMagSq / denMagSq)
        guard magRatio > 1e-9 else { return -120.0 }
        return 20.0 * log10(magRatio)
    }
}

