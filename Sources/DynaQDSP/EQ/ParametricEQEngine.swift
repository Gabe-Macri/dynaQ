import Foundation
import Accelerate
import DynaQCore

/// Core DSP Engine executing multi-band parametric and dynamic equalization.
public final class ParametricEQEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Float = 48000.0

    private var profile: EQProfile
    private var bandFilters: [BiquadFilter] = []
    private var dynamicProcessors: [DynamicEQProcessor] = []

    // Preamp and Master linear factors
    private var preampLinear: Float = 1.0
    private var masterLinear: Float = 1.0

    public init(profile: EQProfile = DefaultPresets.studioFlat, sampleRate: Float = 48000.0) {
        self.profile = profile
        self.sampleRate = max(sampleRate, 8000.0)
        rebuildEngine()
    }

    /// Sets the operating sample rate and updates all filter coefficients.
    public func setSampleRate(_ newRate: Float) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = max(newRate, 8000.0)
        recalculateAllCoefficients(immediate: true)
    }

    /// Updates the current EQ profile.
    public func setProfile(_ newProfile: EQProfile) {
        lock.lock()
        defer { lock.unlock() }
        self.profile = newProfile
        rebuildEngine()
    }

    /// Returns the currently active profile.
    public func currentProfile() -> EQProfile {
        lock.lock()
        defer { lock.unlock() }
        return profile
    }

    /// Update a single band in real time without audio glitching.
    public func updateBand(_ band: EQBand) {
        lock.lock()
        defer { lock.unlock() }

        if let index = profile.bands.firstIndex(where: { $0.id == band.id }) {
            profile.bands[index] = band
            updateBandCoefficients(index: index, immediate: false)
        }
    }

    /// Update master and preamp gains.
    public func setGains(preampDB: Float, masterDB: Float) {
        lock.lock()
        defer { lock.unlock() }
        profile.preampGain = preampDB
        profile.masterGain = masterDB
        preampLinear = pow(10.0, preampDB / 20.0)
        masterLinear = pow(10.0, masterDB / 20.0)
    }

    /// Set bypass mode.
    public func setBypassed(_ bypassed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        profile.isBypassed = bypassed
    }

    // MARK: - Internal Engine Setup

    private func rebuildEngine() {
        preampLinear = pow(10.0, profile.preampGain / 20.0)
        masterLinear = pow(10.0, profile.masterGain / 20.0)

        bandFilters = profile.bands.map { _ in BiquadFilter() }
        dynamicProcessors = profile.bands.map { _ in DynamicEQProcessor() }

        for i in 0..<profile.bands.count {
            updateBandCoefficients(index: i, immediate: true)
        }
    }

    private func recalculateAllCoefficients(immediate: Bool) {
        for i in 0..<profile.bands.count {
            updateBandCoefficients(index: i, immediate: immediate)
        }
    }

    private func updateBandCoefficients(index: Int, immediate: Bool) {
        guard index < profile.bands.count, index < bandFilters.count else { return }
        let band = profile.bands[index]

        let filter = bandFilters[index]
        filter.isBypassed = !band.isEnabled

        if !band.isEnabled {
            filter.setCoefficients(.bypass, immediate: immediate)
            return
        }

        let coeffs = BiquadCoefficients.calculate(
            type: band.filterType,
            frequency: band.frequency,
            gainDB: band.gain,
            q: band.q,
            sampleRate: sampleRate
        )
        filter.setCoefficients(coeffs, immediate: immediate)
    }

    // MARK: - Real-time Audio Processing

    public func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard !profile.isBypassed else { return }

        lock.lock()
        let localBands = profile.bands
        let pLinear = preampLinear
        let mLinear = masterLinear
        lock.unlock()

        // 1. Preamp Gain
        if abs(pLinear - 1.0) > 0.001 {
            var factor = pLinear
            vDSP_vsmul(left, 1, &factor, left, 1, vDSP_Length(count))
            vDSP_vsmul(right, 1, &factor, right, 1, vDSP_Length(count))
        }

        // 2. Process Cascade of Biquad Filter Bands
        for i in 0..<bandFilters.count {
            let filter = bandFilters[i]
            guard !filter.isBypassed else { continue }

            let band = localBands[i]
            if band.isDynamic {
                let dyn = dynamicProcessors[i]
                let offsetDB = dyn.processBlock(samples: left, count: count, sampleRate: sampleRate, band: band)
                if abs(offsetDB) > 0.01 {
                    let dynCoeffs = BiquadCoefficients.calculate(
                        type: band.filterType,
                        frequency: band.frequency,
                        gainDB: band.gain + offsetDB,
                        q: band.q,
                        sampleRate: sampleRate
                    )
                    filter.setCoefficients(dynCoeffs, immediate: false)
                }
            }

            filter.process(buffer: left, count: count, channel: 0)
            filter.process(buffer: right, count: count, channel: 1)
        }

        // 3. Master Output Gain
        if abs(mLinear - 1.0) > 0.001 {
            var factor = mLinear
            vDSP_vsmul(left, 1, &factor, left, 1, vDSP_Length(count))
            vDSP_vsmul(right, 1, &factor, right, 1, vDSP_Length(count))
        }
    }

    // MARK: - Frequency Curve Evaluation (For UI Visualization)

    /// Computes composite magnitude response in dB across all enabled bands at arbitrary frequencies.
    public func evaluateCompositeResponse(at frequencies: [Float]) -> [Float] {
        lock.lock()
        let activeBands = profile.bands.filter { $0.isEnabled }
        let currentSR = sampleRate
        lock.unlock()

        var totalDB = [Float](repeating: 0.0, count: frequencies.count)

        for band in activeBands {
            let coeffs = BiquadCoefficients.calculate(
                type: band.filterType,
                frequency: band.frequency,
                gainDB: band.gain,
                q: band.q,
                sampleRate: currentSR
            )
            for i in 0..<frequencies.count {
                totalDB[i] += coeffs.magnitudeResponse(at: frequencies[i], sampleRate: currentSR)
            }
        }

        return totalDB
    }
}
