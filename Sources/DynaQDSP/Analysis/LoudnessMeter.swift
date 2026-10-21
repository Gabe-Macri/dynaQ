import Foundation
import Accelerate
import DynaQCore
import CDspKernel

/// Vector-accelerated stereo peak, RMS, and clipping detector.
/// Offloaded to Apple Accelerate hardware routines (vDSP_maxmgv, vDSP_measqv) via CDspKernel.
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

        var result = c_loudness_result_t()
        c_dsp_measure_loudness(
            left,
            right,
            count,
            &peakL,
            &peakR,
            &rmsL,
            &rmsR,
            &clipL,
            &clipR,
            &result
        )

        return AudioMeter(
            peakLeft: result.peak_left_db,
            peakRight: result.peak_right_db,
            rmsLeft: result.rms_left_db,
            rmsRight: result.rms_right_db,
            lufsMomentary: (result.rms_left_db + result.rms_right_db) * 0.5,
            lufsIntegrated: (result.rms_left_db + result.rms_right_db) * 0.5,
            isClippingLeft: result.clip_left,
            isClippingRight: result.clip_right
        )
    }
}
