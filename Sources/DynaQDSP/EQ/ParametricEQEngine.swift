import Foundation
import Accelerate
import DynaQCore

/// Core DSP Engine executing multi-band parametric, dynamic, and Mid/Side equalization.
public final class ParametricEQEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Float = 48000.0

    private var profile: EQProfile
    private var bandFilters: [BiquadFilter] = []
    private var dynamicProcessors: [DynamicEQProcessor] = []

    // Scratch buffers for M/S and channel routing
    private var midScratch: [Float] = []
    private var sideScratch: [Float] = []

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
        let pInvert = profile.phaseInvert
        let mMode = profile.monitorMode
        lock.unlock()

        // Ensure scratch buffers capacity
        if midScratch.count < count {
            midScratch = [Float](repeating: 0.0, count: count)
            sideScratch = [Float](repeating: 0.0, count: count)
        }

        // 1. Preamp Gain
        if abs(pLinear - 1.0) > 0.001 {
            var factor = pLinear
            vDSP_vsmul(left, 1, &factor, left, 1, vDSP_Length(count))
            vDSP_vsmul(right, 1, &factor, right, 1, vDSP_Length(count))
        }

        // 2. Process Cascade of Biquad Filter Bands with M/S and Channel Routing
        for i in 0..<bandFilters.count {
            let filter = bandFilters[i]
            guard !filter.isBypassed else { continue }

            let band = localBands[i]

            // Dynamic EQ Modulation
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

            // Route processing based on band mode
            switch band.routing {
            case .stereo:
                filter.process(buffer: left, count: count, channel: 0)
                filter.process(buffer: right, count: count, channel: 1)

            case .left:
                filter.process(buffer: left, count: count, channel: 0)

            case .right:
                filter.process(buffer: right, count: count, channel: 1)

            case .mid:
                // Mid = (L + R) * 0.5, Side = (L - R) * 0.5
                midScratch.withUnsafeMutableBufferPointer { mPtr in
                    sideScratch.withUnsafeMutableBufferPointer { sPtr in
                        for n in 0..<count {
                            let l = left[n]
                            let r = right[n]
                            mPtr[n] = (l + r) * 0.5
                            sPtr[n] = (l - r) * 0.5
                        }
                        // Filter only the Mid component
                        filter.process(buffer: mPtr.baseAddress!, count: count, channel: 0)
                        // Reconstruct L = M + S, R = M - S
                        for n in 0..<count {
                            let m = mPtr[n]
                            let s = sPtr[n]
                            left[n] = m + s
                            right[n] = m - s
                        }
                    }
                }

            case .side:
                midScratch.withUnsafeMutableBufferPointer { mPtr in
                    sideScratch.withUnsafeMutableBufferPointer { sPtr in
                        for n in 0..<count {
                            let l = left[n]
                            let r = right[n]
                            mPtr[n] = (l + r) * 0.5
                            sPtr[n] = (l - r) * 0.5
                        }
                        // Filter only the Side component
                        filter.process(buffer: sPtr.baseAddress!, count: count, channel: 1)
                        // Reconstruct L = M + S, R = M - S
                        for n in 0..<count {
                            let m = mPtr[n]
                            let s = sPtr[n]
                            left[n] = m + s
                            right[n] = m - s
                        }
                    }
                }
            }
        }

        // 3. Monitor Mode Auditioning
        switch mMode {
        case .stereo:
            break
        case .mono:
            for n in 0..<count {
                let mono = (left[n] + right[n]) * 0.5
                left[n] = mono
                right[n] = mono
            }
        case .sides:
            for n in 0..<count {
                let side = (left[n] - right[n]) * 0.5
                left[n] = side
                right[n] = -side
            }
        case .leftOnly:
            for n in 0..<count {
                right[n] = 0.0
            }
        case .rightOnly:
            for n in 0..<count {
                left[n] = 0.0
            }
        }

        // 4. Polarity / Phase Invert (180°)
        if pInvert {
            var negOne: Float = -1.0
            vDSP_vsmul(left, 1, &negOne, left, 1, vDSP_Length(count))
            vDSP_vsmul(right, 1, &negOne, right, 1, vDSP_Length(count))
        }

        // 5. Master Output Gain
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
