import Foundation

/// Fast soft-knee true peak limiter to prevent digital overs and speaker damage.
public final class TruePeakLimiter: @unchecked Sendable {
    public var ceilingDB: Float = -0.2 {
        didSet {
            linearCeiling = pow(10.0, ceilingDB / 20.0)
        }
    }
    public var isEnabled: Bool = true

    private var linearCeiling: Float = 0.9772 // ~ -0.2 dBFS

    public init(ceilingDB: Float = -0.2, isEnabled: Bool = true) {
        self.ceilingDB = ceilingDB
        self.isEnabled = isEnabled
        self.linearCeiling = pow(10.0, ceilingDB / 20.0)
    }

    /// In-place limiting on stereo buffers.
    public func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard isEnabled else { return }
        let c = linearCeiling
        let knee = c * 0.85

        for i in 0..<count {
            left[i] = limitSample(left[i], ceiling: c, knee: knee)
            right[i] = limitSample(right[i], ceiling: c, knee: knee)
        }
    }

    @inline(__always)
    private func limitSample(_ x: Float, ceiling: Float, knee: Float) -> Float {
        let absX = abs(x)
        if absX <= knee {
            return x
        }
        let sign: Float = x < 0 ? -1.0 : 1.0
        // Soft compression between knee and ceiling
        let over = absX - knee
        let range = ceiling - knee
        let saturated = knee + range * tanh(over / range)
        return sign * min(saturated, ceiling)
    }
}

