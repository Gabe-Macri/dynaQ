import Foundation
import CDspKernel

/// Precision Stereo Phase Correlation and Spatial Imaging Analyzer.
/// Computes normalized cross-correlation:
///   +1.0 = Pure Mono (In-Phase)
///    0.0 = Wide Stereo / Uncorrelated
///   -1.0 = Destructive Out-of-Phase Cancellation
public final class StereoPhaseCorrelation: @unchecked Sendable {
    public private(set) var smoothedCorrelation: Float = 1.0
    public private(set) var balance: Float = 0.5 // 0.0 = full left, 0.5 = center, 1.0 = full right

    public init() {}

    public func reset() {
        smoothedCorrelation = 1.0
        balance = 0.5
    }

    /// Evaluates phase correlation and balance across a stereo audio block.
    public func processStereo(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        count: Int
    ) -> (correlation: Float, balance: Float) {
        guard count > 0 else {
            return (smoothedCorrelation, balance)
        }

        let rawCorr = c_dsp_measure_phase_correlation(left, right, count)

        // Smooth correlation to prevent visual jitter
        smoothedCorrelation += (rawCorr - smoothedCorrelation) * 0.2

        // Measure stereo balance
        var sumL: Float = 0.0
        var sumR: Float = 0.0
        for i in 0..<count {
            sumL += abs(left[i])
            sumR += abs(right[i])
        }
        let total = sumL + sumR
        if total > 1e-6 {
            let instantBal = sumR / total
            balance += (instantBal - balance) * 0.2
        } else {
            balance = 0.5
        }

        return (smoothedCorrelation, balance)
    }
}

