import XCTest
import CDspKernel
@testable import DynaQCore
@testable import DynaQDSP

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
}
<<<<<<< HEAD

=======
>>>>>>> bdfc73f4e823d4c4b98e51cdcf99facd23a7a9dd
