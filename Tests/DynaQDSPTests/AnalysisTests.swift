import XCTest
import DynaQCore
@testable import DynaQAnalysis

final class AnalysisTests: XCTestCase {

    func testSpectrumAnalyzerZeroLockFeedAndGetSpectrum() {
        let analyzer = SpectrumAnalyzer(fftSize: 512, binCount: 64, sampleRate: 48000.0)

        // Generate 1 kHz pure sine wave
        let sampleCount = 512
        var sineWave = [Float](repeating: 0.0, count: sampleCount)
        let freq: Float = 1000.0
        for i in 0..<sampleCount {
            sineWave[i] = sin(2.0 * Float.pi * freq * Float(i) / 48000.0) * 0.8
        }

        // Feed audio samples into lock-free accumulation buffer
        analyzer.feed(samples: sineWave, count: sampleCount)

        // Request display spectrum
        let spectrum = analyzer.getSpectrumDB()

        XCTAssertEqual(spectrum.count, 64)

        // Find peak bin in spectrum
        var maxDB: Float = -100.0
        var maxBin: Int = 0
        for b in 0..<spectrum.count {
            if spectrum[b] > maxDB {
                maxDB = spectrum[b]
                maxBin = b
            }
        }

        // 1 kHz should appear strongly near middle of the 64 log bins (around bin 25-35)
        XCTAssertGreaterThan(maxDB, -30.0, "1 kHz tone should produce strong spectral peak")
        XCTAssertTrue(maxBin >= 20 && maxBin <= 45, "1 kHz tone should peak in the mid-frequency bins (found at bin \(maxBin))")
    }

    func testLoudnessMeterCalculatesAccurately() {
        let meter = LoudnessMeter()
        let count = 512
        // Signal at linear 0.5 (-6.02 dBFS)
        let left = [Float](repeating: 0.5, count: count)
        let right = [Float](repeating: 0.5, count: count)

        let result = meter.processStereo(left: left, right: right, count: count)

        XCTAssertEqual(result.peakLeft, -6.02, accuracy: 0.2)
        XCTAssertEqual(result.peakRight, -6.02, accuracy: 0.2)
        XCTAssertFalse(result.isClippingLeft)
        XCTAssertFalse(result.isClippingRight)
    }

    func testStereoPhaseCorrelation() {
        let phaseMeter = StereoPhaseCorrelation()
        let count = 256

        // Case 1: Pure mono in-phase signal
        let monoL = (0..<count).map { sin(Float($0) * 0.1) }
        let monoR = monoL
        let inPhaseResult = phaseMeter.processStereo(left: monoL, right: monoR, count: count)

        XCTAssertGreaterThan(inPhaseResult.correlation, 0.8, "Identical L/R channels should correlate close to +1.0")
        XCTAssertEqual(inPhaseResult.balance, 0.5, accuracy: 0.05, "Centered mono should have 0.5 balance")

        // Case 2: Out of phase signal (L = -R)
        let outPhaseR = monoL.map { -$0 }
        var outPhaseResult = (correlation: Float(0), balance: Float(0))
        for _ in 0..<15 {
            outPhaseResult = phaseMeter.processStereo(left: monoL, right: outPhaseR, count: count)
        }

        XCTAssertLessThan(outPhaseResult.correlation, -0.8, "Inverted R channel should drop correlation toward -1.0")
    }

    func testAnalysisErrorDescriptions() {
        let err1 = AnalysisError.unsupportedFFTSize(500)
        let err2 = AnalysisError.invalidBinCount(1000)
        let err3 = AnalysisError.nullBuffer

        XCTAssertTrue(err1.localizedDescription.contains("500"))
        XCTAssertTrue(err2.localizedDescription.contains("1000"))
        XCTAssertTrue(err3.localizedDescription.contains("null or empty"))
    }
}
