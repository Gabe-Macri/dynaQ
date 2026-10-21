import XCTest
@testable import DynaQDSP

final class SpectrumAnalyzerTests: XCTestCase {

    func testSpectrumAnalyzerFeedAndOutput() {
        let analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: 48000.0)

        // Generate a 1 kHz sine tone
        let count = 2048
        var samples = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            samples[i] = sin(2.0 * .pi * 1000.0 * Float(i) / 48000.0)
        }

        samples.withUnsafeBufferPointer { ptr in
            analyzer.feed(samples: ptr.baseAddress!, count: count)
        }

        let spectrum = analyzer.getSpectrumDB()
        XCTAssertEqual(spectrum.count, 64)

        // Make sure at least one bin has elevated energy above floor
        let maxEnergy = spectrum.max() ?? -100.0
        XCTAssertGreaterThan(maxEnergy, -40.0, "FFT of 1kHz sine wave should show clear peak energy.")
    }
}

