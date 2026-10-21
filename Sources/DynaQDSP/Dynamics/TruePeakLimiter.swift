import Foundation
import CDspKernel

/// Fast vectorized soft-knee true peak limiter to prevent digital overs and speaker damage.
/// Accelerated via C SIMD kernel (CDspKernel) for zero CPU overhead and transparent soft saturation.
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

    /// In-place limiting on stereo buffers using vectorized C kernel.
    @inline(__always)
    public func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard isEnabled else { return }
        c_dsp_limiter_process_stereo(left, right, count, linearCeiling, isEnabled)
    }
}
