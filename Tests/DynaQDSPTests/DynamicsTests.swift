import XCTest
import DynaQCore
@testable import DynaQDynamics

final class DynamicsTests: XCTestCase {

    func testTruePeakLimiterLookaheadClampsPeaks() throws {
        let limiter = TruePeakLimiter(ceilingDB: -0.5, lookaheadSamples: 32, sampleRate: 48000.0, isEnabled: true)

        let count = 256
        var left = [Float](repeating: 0.0, count: count)
        var right = [Float](repeating: 0.0, count: count)

        // Inject high-amplitude transient spike (+6 dBFS, linear 2.0)
        for i in 64..<96 {
            left[i] = 2.0
            right[i] = 2.0
        }

        limiter.processStereo(left: &left, right: &right, count: count)

        let linearCeiling: Float = Float(pow(10.0, -0.5 / 20.0)) // ~0.944

        // Lookahead limiter should suppress transient below or at linear ceiling
        for i in 0..<count {
            XCTAssertLessThanOrEqual(left[i], linearCeiling + 0.001, "Left sample at index \(i) exceeded ceiling")
            XCTAssertLessThanOrEqual(right[i], linearCeiling + 0.001, "Right sample at index \(i) exceeded ceiling")
        }
    }

    func testTruePeakLimiterStereoLinking() throws {
        let limiter = TruePeakLimiter(ceilingDB: -1.0, lookaheadSamples: 32, sampleRate: 48000.0, isEnabled: true)

        let count = 128
        // Left channel has heavy spike, right channel is quiet
        var left = [Float](repeating: 3.0, count: count)
        var right = [Float](repeating: 0.75, count: count)

        limiter.processStereo(left: &left, right: &right, count: count)

        for i in 32..<count {
            // Stereo relationship (Left is 4x Right) must be preserved across gain reduction
            if right[i] > 1e-4 {
                let ratio = left[i] / right[i]
                XCTAssertEqual(ratio, 4.0, accuracy: 0.05, "Stereo link must preserve spatial balance")
            }
        }
    }

    func testDynamicEQCompressionModulation() {
        let processor = DynamicEQProcessor()
        let band = EQBand(
            index: 0,
            frequency: 1000.0,
            gain: 0.0,
            q: 1.0,
            filterType: .bell,
            isEnabled: true,
            isDynamic: true,
            dynamicThreshold: -12.0,
            dynamicRange: -6.0,
            dynamicRatio: 4.0,
            attackMs: 5.0,
            releaseMs: 50.0
        )

        let count = 256
        // Hot signal at 0 dBFS (linear 1.0)
        let samples = [Float](repeating: 1.0, count: count)

        var gainReduction: Float = 0.0
        for _ in 0..<10 {
            gainReduction = processor.processBlock(samples: samples, count: count, sampleRate: 48000.0, band: band)
        }

        // Must apply negative dynamic gain (compression)
        XCTAssertLessThan(gainReduction, -1.0, "Downward dynamic EQ should reduce gain on hot signal")
        XCTAssertGreaterThanOrEqual(gainReduction, -6.0, "Gain reduction should not exceed dynamicRange")
    }

    func testDynamicsErrorDescriptions() {
        let err1 = DynamicsError.invalidCeiling(5.0)
        let err2 = DynamicsError.invalidSampleRate(4000.0)
        let err3 = DynamicsError.invalidLookahead(2048)

        XCTAssertTrue(err1.localizedDescription.contains("5.00 dBFS"))
        XCTAssertTrue(err2.localizedDescription.contains("4000 Hz"))
        XCTAssertTrue(err3.localizedDescription.contains("2048"))
    }
}
