import Foundation
import Accelerate
import DynaQCore
import DynaQDynamics
import CDspKernel

/// Core DSP Engine executing multi-band parametric, dynamic, and Mid/Side equalization.
/// Offloaded to high-performance C vector kernel (CDspKernel) for zero-overhead audio processing.
public final class ParametricEQEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Float = 48000.0

    private var profile: EQProfile
    private var bandFilters: [BiquadFilter] = []
    private var dynamicProcessors: [DynamicEQProcessor] = []

    // Native C DSP engine state
    private var cEngine = c_eq_engine_t()

    // Precomputed curve cache for zero-lag UI rendering
    private var cachedCurve: [Float] = []
    private let cachedPointsCount = 128
    private var cachedFrequencies: [Float] = []

    // Preamp and Master linear factors
    private var preampLinear: Float = 1.0
    private var masterLinear: Float = 1.0

    public init(profile: EQProfile = DefaultPresets.harmanHeadphoneTarget, sampleRate: Float = 48000.0) {
        self.profile = profile
        self.sampleRate = max(sampleRate, 8000.0)
        c_eq_engine_init(&cEngine)

        // Precompute fixed logarithmically spaced frequencies
        let logMin = log10(Float(20.0))
        let logMax = log10(Float(20000.0))
        var freqs = [Float](repeating: 0.0, count: cachedPointsCount)
        for i in 0..<cachedPointsCount {
            let norm = Float(i) / Float(cachedPointsCount - 1)
            freqs[i] = pow(10.0, logMin + norm * (logMax - logMin))
        }
        self.cachedFrequencies = freqs

        rebuildEngine()
    }

    /// Sets the operating sample rate and updates all filter coefficients.
    public func setSampleRate(_ newRate: Float) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = max(newRate, 8000.0)
        recalculateAllCoefficients(immediate: true)
        updateCurveCache()
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
            updateCurveCache()
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
        c_eq_engine_set_gains(&cEngine, preampLinear, masterLinear)
        updateCurveCache()
    }

    /// Set bypass mode.
    public func setBypassed(_ bypassed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        profile.isBypassed = bypassed
        syncEngineParams()
    }

    /// Returns the precalculated 128-point frequency response curve for instant zero-lag UI rendering.
    public func getCachedCurve() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return cachedCurve
    }

    // MARK: - Internal Engine Setup

    private func rebuildEngine() {
        preampLinear = pow(10.0, profile.preampGain / 20.0)
        masterLinear = pow(10.0, profile.masterGain / 20.0)

        bandFilters = profile.bands.map { _ in BiquadFilter() }
        dynamicProcessors = profile.bands.map { _ in DynamicEQProcessor() }

        c_eq_engine_set_gains(&cEngine, preampLinear, masterLinear)
        syncEngineParams()

        cEngine.band_count = Int32(min(profile.bands.count, Int(C_DSP_MAX_BANDS)))

        for i in 0..<profile.bands.count {
            updateBandCoefficients(index: i, immediate: true)
        }
        updateCurveCache()
    }

    private func syncEngineParams() {
        let modeInt: Int32
        switch profile.monitorMode {
        case .stereo: modeInt = 0
        case .mono: modeInt = 1
        case .sides: modeInt = 2
        case .leftOnly: modeInt = 3
        case .rightOnly: modeInt = 4
        }
        c_eq_engine_set_params(&cEngine, profile.isBypassed, profile.phaseInvert, modeInt)
    }

    private func recalculateAllCoefficients(immediate: Bool) {
        for i in 0..<profile.bands.count {
            updateBandCoefficients(index: i, immediate: immediate)
        }
    }

    private func updateBandCoefficients(index: Int, immediate: Bool) {
        guard index < profile.bands.count, index < Int(C_DSP_MAX_BANDS) else { return }
        let band = profile.bands[index]

        if index < bandFilters.count {
            bandFilters[index].isBypassed = !band.isEnabled
        }

        let coeffs = BiquadCoefficients.calculate(
            type: band.filterType,
            frequency: band.frequency,
            gainDB: band.gain,
            q: band.q,
            sampleRate: sampleRate
        )

        if index < bandFilters.count {
            bandFilters[index].setCoefficients(coeffs, immediate: immediate)
        }

        let cCoeffs = c_biquad_coeffs_t(
            b0: coeffs.b0,
            b1: coeffs.b1,
            b2: coeffs.b2,
            a1: coeffs.a1,
            a2: coeffs.a2
        )

        let routeInt: Int32
        switch band.routing {
        case .stereo: routeInt = 0
        case .mid: routeInt = 1
        case .side: routeInt = 2
        case .left: routeInt = 3
        case .right: routeInt = 4
        }

        c_eq_engine_set_band(&cEngine, Int32(index), cCoeffs, routeInt, band.isEnabled, immediate)
    }

    private func updateCurveCache() {
        let activeBands = profile.bands.filter { $0.isEnabled }
        let currentSR = sampleRate
        var totalDB = [Float](repeating: 0.0, count: cachedFrequencies.count)

        for band in activeBands {
            let coeffs = BiquadCoefficients.calculate(
                type: band.filterType,
                frequency: band.frequency,
                gainDB: band.gain,
                q: band.q,
                sampleRate: currentSR
            )
            for i in 0..<cachedFrequencies.count {
                totalDB[i] += coeffs.magnitudeResponse(at: cachedFrequencies[i], sampleRate: currentSR)
            }
        }
        self.cachedCurve = totalDB
    }

    // MARK: - Real-time Audio Processing (Offloaded to C Backend)

    public func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard !profile.isBypassed else { return }

        // Dynamic EQ modulation if any active
        for i in 0..<profile.bands.count {
            let band = profile.bands[i]
            if band.isDynamic && band.isEnabled && i < dynamicProcessors.count {
                let dyn = dynamicProcessors[i]
                let offsetDB = dyn.processBlock(samples: left, count: count, sampleRate: sampleRate, band: band)
                if abs(offsetDB) > 0.02 {
                    let dynCoeffs = BiquadCoefficients.calculate(
                        type: band.filterType,
                        frequency: band.frequency,
                        gainDB: band.gain + offsetDB,
                        q: band.q,
                        sampleRate: sampleRate
                    )
                    let cCoeffs = c_biquad_coeffs_t(
                        b0: dynCoeffs.b0,
                        b1: dynCoeffs.b1,
                        b2: dynCoeffs.b2,
                        a1: dynCoeffs.a1,
                        a2: dynCoeffs.a2
                    )
                    let routeInt: Int32
                    switch band.routing {
                    case .stereo: routeInt = 0
                    case .mid: routeInt = 1
                    case .side: routeInt = 2
                    case .left: routeInt = 3
                    case .right: routeInt = 4
                    }
                    c_eq_engine_set_band(&cEngine, Int32(i), cCoeffs, routeInt, true, false)
                }
            }
        }

        // Single vectorized C call for all active filter bands, Mid/Side matrixing, phase, and gains
        c_eq_engine_process_stereo(&cEngine, left, right, count)
    }

    // MARK: - Frequency Curve Evaluation (For UI Visualization)

    public func evaluateCompositeResponse(at frequencies: [Float]) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let activeBands = profile.bands.filter { $0.isEnabled }
        let currentSR = sampleRate
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
