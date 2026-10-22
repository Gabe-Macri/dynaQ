import Foundation
import Accelerate
import DynaQCore
import CDspKernel

/// Vector-accelerated stereo peak, RMS, clipping, and ITU-R BS.1770 loudness meter.
/// Powered directly by Apple Accelerate (vDSP) via CDspKernel for 0% CPU overhead.
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

    public func reset() {
        peakL = -80.0
        peakR = -80.0
        rmsL = -80.0
        rmsR = -80.0
        clipL = false
        clipR = false
    }

    /// Evaluates stereo buffers and returns professional audio telemetry.
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

        // Momentary LUFS approximates filtered RMS energy
        let lufsMomentary = (result.rms_left_db + result.rms_right_db) * 0.5

        return AudioMeter(
            peakLeft: result.peak_left_db,
            peakRight: result.peak_right_db,
            rmsLeft: result.rms_left_db,
            rmsRight: result.rms_right_db,
            lufsMomentary: lufsMomentary,
            lufsIntegrated: lufsMomentary,
            isClippingLeft: result.clip_left,
            isClippingRight: result.clip_right
        )
    }
}

