import Foundation
import Accelerate
import DynaQCore

/// Stereo peak, RMS, and clipping detector.
public final class LoudnessMeter: @unchecked Sendable {
    private var peakL: Float = -80.0
    private var peakR: Float = -80.0
    private var rmsL: Float = -80.0
    private var rmsR: Float = -80.0
    private var clipL: Bool = false
    private var clipR: Bool = false

    public init() {}

    public func resetClip() {
        clipL = false
        clipR = false
    }

    public func processStereo(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        count: Int
    ) -> AudioMeter {
        guard count > 0 else { return .silent }

        var maxL: Float = 0.0
        var maxR: Float = 0.0
        var sumSquaresL: Float = 0.0
        var sumSquaresR: Float = 0.0

        for i in 0..<count {
            let absL = abs(left[i])
            let absR = abs(right[i])

            if absL > maxL { maxL = absL }
            if absR > maxR { maxR = absR }

            sumSquaresL += absL * absL
            sumSquaresR += absR * absR

            if absL >= 0.999 { clipL = true }
            if absR >= 0.999 { clipR = true }
        }

        let meanSqL = sumSquaresL / Float(count)
        let meanSqR = sumSquaresR / Float(count)

        let currRmsL = meanSqL > 1e-10 ? 10.0 * log10(meanSqL) : -80.0
        let currRmsR = meanSqR > 1e-10 ? 10.0 * log10(meanSqR) : -80.0

        let currPeakL = maxL > 1e-5 ? 20.0 * log10(maxL) : -80.0
        let currPeakR = maxR > 1e-5 ? 20.0 * log10(maxR) : -80.0

        // Smooth peak decay
        peakL = max(currPeakL, peakL - 0.5)
        peakR = max(currPeakR, peakR - 0.5)

        // Smooth RMS
        rmsL += (currRmsL - rmsL) * 0.2
        rmsR += (currRmsR - rmsR) * 0.2

        return AudioMeter(
            peakLeft: peakL,
            peakRight: peakR,
            rmsLeft: rmsL,
            rmsRight: rmsR,
            lufsMomentary: (rmsL + rmsR) * 0.5,
            lufsIntegrated: (rmsL + rmsR) * 0.5,
            isClippingLeft: clipL,
            isClippingRight: clipR
        )
    }
}

