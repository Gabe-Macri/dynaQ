import XCTest
import CDspKernel
@testable import DynaQCore
@testable import DynaQDSP
@testable import DynaQDynamics
@testable import DynaQAnalysis
@testable import DynaQAudioDriver

final class CDspKernelTests: XCTestCase {

    func testLockFreeRingBufferReadWrite() {
        let capacity = 512
        guard let rb = c_ringbuffer_create(capacity) else {
            XCTFail("Failed to allocate c_ringbuffer")
            return
        }
        defer { c_ringbuffer_destroy(rb) }

        XCTAssertEqual(c_ringbuffer_available_read(rb), 0)

        let testCount = 128
        let inputL = (0..<testCount).map { Float($0) * 0.01 }
        let inputR = (0..<testCount).map { Float($0) * -0.01 }

        let written = c_ringbuffer_write_stereo(rb, inputL, inputR, testCount)
        XCTAssertEqual(written, testCount)
        XCTAssertEqual(c_ringbuffer_available_read(rb), testCount)

        var readL = [Float](repeating: 0.0, count: testCount)
        var readR = [Float](repeating: 0.0, count: testCount)

        let readCount = c_ringbuffer_read_stereo(rb, &readL, &readR, testCount)
        XCTAssertEqual(readCount, testCount)
        XCTAssertEqual(c_ringbuffer_available_read(rb), 0)

        for i in 0..<testCount {
            XCTAssertEqual(readL[i], inputL[i], accuracy: 1e-6)
            XCTAssertEqual(readR[i], inputR[i], accuracy: 1e-6)
        }
    }

    func testRingBufferWrapAround() {
        let capacity = 64
        guard let rb = c_ringbuffer_create(capacity) else {
            XCTFail("Failed to allocate ring buffer")
            return
        }
        defer { c_ringbuffer_destroy(rb) }

        // Fill and drain across multiple wrap-arounds
        for cycle in 0..<10 {
            let count = 40
            let inputL = (0..<count).map { Float(cycle * 100 + $0) }
            let inputR = (0..<count).map { Float(cycle * 100 + $0) * 2.0 }

            let written = c_ringbuffer_write_stereo(rb, inputL, inputR, count)
            XCTAssertEqual(written, count)

            var readL = [Float](repeating: 0.0, count: count)
            var readR = [Float](repeating: 0.0, count: count)
            let read = c_ringbuffer_read_stereo(rb, &readL, &readR, count)
            XCTAssertEqual(read, count)

            for i in 0..<count {
                XCTAssertEqual(readL[i], inputL[i], accuracy: 1e-5)
                XCTAssertEqual(readR[i], inputR[i], accuracy: 1e-5)
            }
        }
    }

    func testMidSideEncodeDecodeReconstruction() {
        let count = 256
        let leftIn = (0..<count).map { sin(Float($0) * 0.1) }
        let rightIn = (0..<count).map { cos(Float($0) * 0.1) }

        var mid = [Float](repeating: 0.0, count: count)
        var side = [Float](repeating: 0.0, count: count)

        c_dsp_midside_encode(leftIn, rightIn, &mid, &side, count)

        var leftOut = [Float](repeating: 0.0, count: count)
        var rightOut = [Float](repeating: 0.0, count: count)

        c_dsp_midside_decode(mid, side, &leftOut, &rightOut, count)

        for i in 0..<count {
            XCTAssertEqual(leftOut[i], leftIn[i], accuracy: 1e-5, "L = M + S reconstruction failed.")
            XCTAssertEqual(rightOut[i], rightIn[i], accuracy: 1e-5, "R = M - S reconstruction failed.")
        }
    }

    func testVectorDownmixStereoToMono() {
        let count = 128
        let left = [Float](repeating: 0.8, count: count)
        let right = [Float](repeating: 0.4, count: count)
        var mono = [Float](repeating: 0.0, count: count)

        c_dsp_downmix_stereo_to_mono(left, right, &mono, count)

        for i in 0..<count {
            XCTAssertEqual(mono[i], 0.6, accuracy: 1e-5, "Mono downmix should be (0.8 + 0.4) * 0.5 = 0.6")
        }
    }

    func testLimiterClampsAboveCeiling() {
        let count = 64
        var left = [Float](repeating: 2.0, count: count)
        var right = [Float](repeating: -3.0, count: count)

        let linearCeiling: Float = 0.95
        c_dsp_limiter_process_stereo(&left, &right, count, linearCeiling, true)

        for i in 0..<count {
            XCTAssertLessThanOrEqual(left[i], linearCeiling + 0.01)
            XCTAssertGreaterThanOrEqual(right[i], -linearCeiling - 0.01)
        }
    }

    func testLoudnessMeasurementAccurate() {
        let count = 256
        let left = [Float](repeating: 0.5, count: count)
        let right = [Float](repeating: 0.5, count: count)

        var peakL: Float = -80.0
        var peakR: Float = -80.0
        var rmsL: Float = -80.0
        var rmsR: Float = -80.0
        var clipL: Bool = false
        var clipR: Bool = false
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

        // 20 * log10(0.5) is ~ -6.02 dB
        XCTAssertEqual(result.peak_left_db, -6.02, accuracy: 0.1)
        XCTAssertEqual(result.peak_right_db, -6.02, accuracy: 0.1)
        XCTAssertFalse(result.clip_left)
        XCTAssertFalse(result.clip_right)
    }

    func testClientDSPPipelineProcessing() {
        let pipeline = ClientDSPPipeline(initialProfile: DefaultPresets.harmanHeadphoneTarget, sampleRate: 48000.0)

        let count = 256
        var left = [Float](repeating: 0.5, count: count)
        var right = [Float](repeating: 0.5, count: count)

        // Process through client pipeline
        pipeline.processAudioBlock(left: &left, right: &right, count: count, sampleRate: 48000.0)

        // Check output is valid and non-NaN
        for i in 0..<count {
            XCTAssertFalse(left[i].isNaN)
            XCTAssertFalse(right[i].isNaN)
        }
    }

    func testAudioRouterWithClientAndPassthrough() {
        let router = AudioRouterBackend()

        // 1. Without client: passthrough
        XCTAssertNil(router.client)

        // 2. Attach client
        let pipeline = ClientDSPPipeline(initialProfile: DefaultPresets.studioFlat, sampleRate: 48000.0)
        router.client = pipeline
        XCTAssertNotNil(router.client)
    }

    func testLimiterStereoLinkedGainPreservation() {
        let count = 128
        // Left channel has a hot peak, right channel has a lower signal
        var left = [Float](repeating: 2.0, count: count)
        var right = [Float](repeating: 0.5, count: count)

        let linearCeiling: Float = 0.95
        c_dsp_limiter_process_stereo(&left, &right, count, linearCeiling, true)

        for i in 0..<count {
            // Left must not exceed ceiling
            XCTAssertLessThanOrEqual(left[i], linearCeiling + 0.001)
            // Stereo relationship (left is 4x right) must be strictly maintained to preserve spatial image
            let ratio = left[i] / right[i]
            XCTAssertEqual(ratio, 4.0, accuracy: 1e-4, "Stereo link must preserve channel balance across limiting.")
        }
    }

    func testRingBufferUnderrunBehavior() {
        let capacity = 256
        guard let rb = c_ringbuffer_create(capacity) else {
            XCTFail("Failed to allocate ring buffer")
            return
        }
        defer { c_ringbuffer_destroy(rb) }

        // Write 32 frames
        let inputL = [Float](repeating: 0.77, count: 32)
        let inputR = [Float](repeating: 0.88, count: 32)
        let written = c_ringbuffer_write_stereo(rb, inputL, inputR, 32)
        XCTAssertEqual(written, 32)

        // Attempt to read 64 frames (underrun situation)
        var readL = [Float](repeating: -1.0, count: 64)
        var readR = [Float](repeating: -1.0, count: 64)
        let readCount = c_ringbuffer_read_stereo(rb, &readL, &readR, 64)

        // Must return only available 32 frames without crashing or corrupting
        XCTAssertEqual(readCount, 32)
        XCTAssertEqual(c_ringbuffer_available_read(rb), 0)

        for i in 0..<32 {
            XCTAssertEqual(readL[i], 0.77, accuracy: 1e-6)
            XCTAssertEqual(readR[i], 0.88, accuracy: 1e-6)
        }
    }

    func testBiquadFilterDenormalAndNaNProtection() {
        var eq = c_eq_engine_t()
        c_eq_engine_init(&eq)

        let coeffs = c_biquad_coeffs_t(b0: 1.0, b1: -1.8, b2: 0.81, a1: -1.8, a2: 0.81)
        c_eq_engine_set_band(&eq, 0, coeffs, 0, true, true)

        // Feed NaN samples
        var left = [Float](repeating: Float.nan, count: 64)
        var right = [Float](repeating: Float.nan, count: 64)
        c_eq_engine_process_stereo(&eq, &left, &right, 64)

        // The filter must not blow up into infinity
        for i in 0..<64 {
            XCTAssertFalse(left[i].isInfinite)
            XCTAssertFalse(right[i].isInfinite)
        }

        // Subsequent audio must recover cleanly
        var validL = (0..<64).map { sin(Float($0) * 0.1) }
        var validR = (0..<64).map { cos(Float($0) * 0.1) }
        c_eq_engine_process_stereo(&eq, &validL, &validR, 64)

        for i in 0..<64 {
            XCTAssertFalse(validL[i].isNaN)
            XCTAssertFalse(validL[i].isInfinite)
            XCTAssertFalse(validR[i].isNaN)
            XCTAssertFalse(validR[i].isInfinite)
        }
    }

    func testBiquadStabilityJuryCheck() {
        // Stable filter (|a2| < 1, 1 + a1 + a2 > 0, 1 - a1 + a2 > 0)
        let stableCoeffs = c_biquad_coeffs_t(b0: 1.0, b1: 0.0, b2: 0.0, a1: -1.2, a2: 0.5)
        XCTAssertTrue(c_biquad_is_stable(stableCoeffs))

        // Unstable filter (|a2| >= 1.0)
        let unstableCoeffs1 = c_biquad_coeffs_t(b0: 1.0, b1: 0.0, b2: 0.0, a1: -1.2, a2: 1.05)
        XCTAssertFalse(c_biquad_is_stable(unstableCoeffs1))

        // Unstable filter (poles on real axis outside unit circle)
        let unstableCoeffs2 = c_biquad_coeffs_t(b0: 1.0, b1: 0.0, b2: 0.0, a1: 2.5, a2: 0.5)
        XCTAssertFalse(c_biquad_is_stable(unstableCoeffs2))

        // Safe setter rejects unstable biquad
        var eq = c_eq_engine_t()
        c_eq_engine_init(&eq)
        let status = c_eq_engine_set_band_safe(&eq, 0, unstableCoeffs1, 0, true, true)
        XCTAssertEqual(status, C_DSP_ERR_UNSTABLE_FILTER)
    }

    func testLookaheadLimiterCInterface() {
        guard let lim = c_lookahead_limiter_create(32, 48000.0, 0.9) else {
            XCTFail("Failed to allocate lookahead limiter")
            return
        }
        defer { c_lookahead_limiter_destroy(lim) }

        var left = [Float](repeating: 2.5, count: 64)
        var right = [Float](repeating: 2.5, count: 64)

        c_lookahead_limiter_process(lim, &left, &right, 64)

        for i in 32..<64 {
            XCTAssertLessThanOrEqual(left[i], 0.901, "Left sample should be clamped to 0.9 ceiling")
            XCTAssertLessThanOrEqual(right[i], 0.901, "Right sample should be clamped to 0.9 ceiling")
        }
    }

    func testPhaseCorrelationCInterface() {
        let count = 128
        let monoL = (0..<count).map { sin(Float($0) * 0.05) }
        let monoR = monoL

        let corrInPhase = c_dsp_measure_phase_correlation(monoL, monoR, count)
        XCTAssertEqual(corrInPhase, 1.0, accuracy: 1e-4)

        let outOfPhaseR = monoL.map { -$0 }
        let corrOutOfPhase = c_dsp_measure_phase_correlation(monoL, outOfPhaseR, count)
        XCTAssertEqual(corrOutOfPhase, -1.0, accuracy: 1e-4)
    }

    func testLookaheadLimiterLiveModeZeroLatency() {
        guard let lim = c_lookahead_limiter_create(32, 48000.0, 0.95) else {
            XCTFail("Failed to allocate lookahead limiter")
            return
        }
        defer { c_lookahead_limiter_destroy(lim) }

        // Enable Zero-Latency Live Mode
        c_lookahead_limiter_set_live_mode(lim, true)
        XCTAssertTrue(c_lookahead_limiter_get_live_mode(lim))

        let count = 16
        // Spikes at samples 0..15
        var left = [Float](repeating: 3.0, count: count)
        var right = [Float](repeating: 3.0, count: count)

        // In Live Mode, limiter immediately processes sample 0 with 0 lookahead delay
        c_lookahead_limiter_process(lim, &left, &right, count)

        for i in 0..<count {
            XCTAssertLessThanOrEqual(left[i], 0.951, "Sample \(i) must be clamped immediately without lookahead delay")
            XCTAssertLessThanOrEqual(right[i], 0.951, "Sample \(i) must be clamped immediately without lookahead delay")
        }
    }

    func testEnsureMidSideDecodedMatrix() {
        let count = 8
        // Mid = 0.8, Side = 0.2
        var left = [Float](repeating: 0.8, count: count)
        var right = [Float](repeating: 0.2, count: count)

        // Decode: L = Mid + Side = 1.0, R = Mid - Side = 0.6
        c_dsp_ensure_midside_decoded(&left, &right, count, true)

        for i in 0..<count {
            XCTAssertEqual(left[i], 1.0, accuracy: 1e-5, "L must equal Mid + Side")
            XCTAssertEqual(right[i], 0.6, accuracy: 1e-5, "R must equal Mid - Side")
        }
    }
}
