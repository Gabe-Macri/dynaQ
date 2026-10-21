import XCTest
@testable import DynaQCore
@testable import DynaQDSP

final class BiquadFilterTests: XCTestCase {

    func testBellFilterMagnitudeAtCenterFrequency() {
        let sampleRate: Float = 48000.0
        let centerFreq: Float = 1000.0
        let targetGain: Float = 6.0
        let q: Float = 1.414

        let coeffs = BiquadCoefficients.calculate(
            type: .bell,
            frequency: centerFreq,
            gainDB: targetGain,
            q: q,
            sampleRate: sampleRate
        )

        let magAtCenter = coeffs.magnitudeResponse(at: centerFreq, sampleRate: sampleRate)
        XCTAssertEqual(magAtCenter, targetGain, accuracy: 0.1, "Bell filter peak should match target gain at center frequency.")
    }

    func testLowPassFilterAttenuatesHighFrequencies() {
        let sampleRate: Float = 48000.0
        let cutoffFreq: Float = 500.0
        let q: Float = 0.707

        let coeffs = BiquadCoefficients.calculate(
            type: .lowPass,
            frequency: cutoffFreq,
            gainDB: 0.0,
            q: q,
            sampleRate: sampleRate
        )

        let passbandMag = coeffs.magnitudeResponse(at: 100.0, sampleRate: sampleRate)
        let stopbandMag = coeffs.magnitudeResponse(at: 10000.0, sampleRate: sampleRate)

        XCTAssertEqual(passbandMag, 0.0, accuracy: 0.5, "Passband should be near 0 dB.")
        XCTAssertLessThan(stopbandMag, -20.0, "High frequencies should be heavily attenuated.")
    }

    func testBiquadProcessingStability() {
        let filter = BiquadFilter()
        let coeffs = BiquadCoefficients.calculate(
            type: .bell,
            frequency: 1000.0,
            gainDB: 12.0,
            q: 2.0,
            sampleRate: 48000.0
        )
        filter.setCoefficients(coeffs, immediate: true)

        let count = 2048
        var buffer = [Float](repeating: 0.0, count: count)
        // Unit impulse
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { ptr in
            filter.process(buffer: ptr.baseAddress!, count: count, channel: 0)
        }

        // Verify impulse response is finite and stable
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Filtered output must not be NaN.")
            XCTAssertFalse(sample.isInfinite, "Filtered output must not be Infinite.")
        }
    }

    func testPhaseInversion() {
        var profileNormal = DefaultPresets.studioFlat
        profileNormal.phaseInvert = false
        let engineNormal = ParametricEQEngine(profile: profileNormal, sampleRate: 48000.0)

        var profileInverted = DefaultPresets.studioFlat
        profileInverted.phaseInvert = true
        let engineInverted = ParametricEQEngine(profile: profileInverted, sampleRate: 48000.0)

        var leftA: [Float] = [0.5, 0.25, -0.75, 0.33]
        var rightA: [Float] = [0.1, -0.4, 0.8, -0.2]
        var leftB = leftA
        var rightB = rightA
        let count = leftA.count

        leftA.withUnsafeMutableBufferPointer { lPtr in
            rightA.withUnsafeMutableBufferPointer { rPtr in
                engineNormal.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: count)
            }
        }

        leftB.withUnsafeMutableBufferPointer { lPtr in
            rightB.withUnsafeMutableBufferPointer { rPtr in
                engineInverted.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: count)
            }
        }

        for i in 0..<count {
            XCTAssertEqual(leftB[i], -leftA[i], accuracy: 0.0001, "Phase inversion must flip polarity 180°.")
            XCTAssertEqual(rightB[i], -rightA[i], accuracy: 0.0001, "Phase inversion must flip polarity 180°.")
        }
    }

    func testParametricEQEngineCompositeEvaluation() {
        let profile = DefaultPresets.harmanHeadphoneTarget
        let engine = ParametricEQEngine(profile: profile, sampleRate: 48000.0)

        let freqs: [Float] = [20.0, 100.0, 1000.0, 3200.0, 10000.0]
        let responses = engine.evaluateCompositeResponse(at: freqs)

        XCTAssertEqual(responses.count, freqs.count)
        // Harman curve has a presence boost around 3.2kHz
        let index3k = freqs.firstIndex(of: 3200.0)!
        XCTAssertGreaterThan(responses[index3k], 1.0, "Harman curve should have positive gain around 3.2 kHz.")
    }
}
