import Foundation
import Accelerate
import DynaQCore
import DynaQDynamics
import CDspKernel

/// Core DSP Engine executing multi-band parametric, dynamic, Frequency-Modulated (FM), and Mid/Side equalization.
/// Offloaded to high-performance C vector kernel (CDspKernel) for zero-overhead real-time audio processing.
public final class ParametricEQEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Float = 48000.0

    private var profile: EQProfile
    private var bandFilters: [BiquadFilter] = []
    private var dynamicProcessors: [DynamicEQProcessor] = []

    // Frequency Modulation (FM) LFO Phase Accumulators & Live Modulated Frequencies
    private var lfoPhases: [Float] = []
    private var liveModulatedFrequencies: [Float] = []

    // Native C DSP engine state
    private var cEngine = c_eq_engine_t()

    // Precomputed curve cache for zero-lag UI rendering
    private var cachedCurve: [Float] = []
    private let cachedPointsCount = 128
    private var cachedFrequencies: [Float] = []

    // Preamp and Master linear factors
    private var preampLinear: Float = 1.0
    private var masterLinear: Float = 1.0

    // Headroom Buffer & Anti-Clip Saturation Guard
    public var isHeadroomGuardEnabled: Bool = true

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
        c_eq_engine_set_master_fx(&cEngine, profile.stereoWidth, profile.monoBassCutoff, profile.analogDrive, sampleRate)
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

    /// Indicates whether any active EQ bands utilize Mid/Side matrixing.
    public var isMidSideActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return profile.bands.contains { $0.isEnabled && ($0.routing == .mid || $0.routing == .side) }
    }

    /// Returns the precalculated 128-point frequency response curve for instant zero-lag UI rendering.
    public func getCachedCurve() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return cachedCurve
    }

    /// Returns the current real-time modulated frequency for a given band index (FM telemetry).
    public func getModulatedFrequency(forBandIndex index: Int) -> Float {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < liveModulatedFrequencies.count else {
            return (index >= 0 && index < profile.bands.count) ? profile.bands[index].frequency : 1000.0
        }
        return liveModulatedFrequencies[index]
    }

    // MARK: - Internal Engine Setup

    private func rebuildEngine() {
        preampLinear = pow(10.0, profile.preampGain / 20.0)
        masterLinear = pow(10.0, profile.masterGain / 20.0)

        bandFilters = profile.bands.map { _ in BiquadFilter() }
        dynamicProcessors = profile.bands.map { _ in DynamicEQProcessor() }
        lfoPhases = [Float](repeating: 0.0, count: profile.bands.count)
        liveModulatedFrequencies = profile.bands.map { $0.frequency }

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
        c_eq_engine_set_master_fx(&cEngine, profile.stereoWidth, profile.monoBassCutoff, profile.analogDrive, sampleRate)
    }

    private func recalculateAllCoefficients(immediate: Bool) {
        for i in 0..<profile.bands.count {
            updateBandCoefficients(index: i, immediate: immediate)
        }
    }

    private func updateBandCoefficients(index: Int, immediate: Bool) {
        guard index < profile.bands.count, index < Int(C_DSP_MAX_BANDS) else { return }
        let band = profile.bands[index]

        // Solo Logic: If ANY band is soloed, only soloed bands are enabled
        let anySolo = profile.bands.contains { $0.isSolo }
        let effectiveEnabled = anySolo ? (band.isSolo && band.isEnabled) : band.isEnabled

        if index < bandFilters.count {
            bandFilters[index].isBypassed = !effectiveEnabled
        }

        let freq = (index < liveModulatedFrequencies.count) ? liveModulatedFrequencies[index] : band.frequency
        let coeffs = BiquadCoefficients.calculate(
            type: band.filterType,
            frequency: freq,
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

        c_eq_engine_set_band(&cEngine, Int32(index), cCoeffs, routeInt, effectiveEnabled, immediate)
    }

    private func updateCurveCache() {
        let anySolo = profile.bands.contains { $0.isSolo }
        let activeBands = profile.bands.filter { b in
            anySolo ? (b.isSolo && b.isEnabled) : b.isEnabled
        }
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
        guard !profile.isBypassed, count > 0 else { return }

        let anySolo = profile.bands.contains { $0.isSolo }

        // 1. Dynamic EQ & Frequency Modulation (FM EQ)
        for i in 0..<profile.bands.count {
            let band = profile.bands[i]
            let effectiveEnabled = anySolo ? (band.isSolo && band.isEnabled) : band.isEnabled
            guard effectiveEnabled else { continue }

            var targetFreq = band.frequency
            var targetGain = band.gain

            // Frequency Modulation (FM Mode)
            if band.isFMEnabled {
                if band.fmMode == .lfo {
                    // Periodic sinusoidal frequency sweep
                    let deltaPhase = 2.0 * Float.pi * band.fmRate * (Float(count) / sampleRate)
                    var phase = (i < lfoPhases.count) ? lfoPhases[i] : 0.0
                    phase = fmod(phase + deltaPhase, 2.0 * Float.pi)
                    if i < lfoPhases.count { lfoPhases[i] = phase }

                    let lfoVal = sin(phase)
                    let octaveShift = lfoVal * band.fmDepth
                    targetFreq = band.frequency * pow(2.0, octaveShift)
                } else if band.fmMode == .envelope && i < dynamicProcessors.count {
                    // Signal envelope tracking FM
                    let dyn = dynamicProcessors[i]
                    let offsetDB = dyn.processStereoBlock(left: left, right: right, count: count, sampleRate: sampleRate, band: band)
                    // Normalized dynamic envelope deflection
                    let envFactor = min(max(offsetDB / max(abs(band.dynamicRange), 1.0), -1.0), 1.0)
                    let octaveShift = envFactor * band.fmDepth
                    targetFreq = band.frequency * pow(2.0, octaveShift)
                }

                targetFreq = min(max(targetFreq, 20.0), min(20000.0, sampleRate * 0.48))
                if i < liveModulatedFrequencies.count {
                    liveModulatedFrequencies[i] = targetFreq
                }
            } else {
                if i < liveModulatedFrequencies.count {
                    liveModulatedFrequencies[i] = band.frequency
                }
            }

            // Dynamic Gain Modulation with frequency-targeted sidechain
            if band.isDynamic && !band.isFMEnabled && i < dynamicProcessors.count {
                let dyn = dynamicProcessors[i]
                let offsetDB = dyn.processStereoBlock(left: left, right: right, count: count, sampleRate: sampleRate, band: band)
                targetGain += offsetDB
            }

            // If FM or Dynamic EQ modulated parameters, smoothly update biquad target
            if band.isFMEnabled || (band.isDynamic && abs(targetGain - band.gain) > 0.02) {
                let dynCoeffs = BiquadCoefficients.calculate(
                    type: band.filterType,
                    frequency: targetFreq,
                    gainDB: targetGain,
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

        // 2. Vectorized C EQ processing (filters, preamp, master gain, M/S, phase)
        c_eq_engine_process_stereo(&cEngine, left, right, count)

        // 3. Headroom Buffer & Anti-Clip Saturation Guard
        // Prevents harsh digital clipping when aggressive filter settings or resonant peaks occur
        if isHeadroomGuardEnabled {
            applySoftSaturationHeadroom(left: left, right: right, count: count)
        }
    }

    /// Internal smooth soft-saturation curve preventing settings from clipping into harsh digital rail distortion.
    private func applySoftSaturationHeadroom(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        for i in 0..<count {
            let l = left[i]
            let r = right[i]

            // Rational soft-knee saturation: if |x| > 0.85, gently compress toward ceiling
            if abs(l) > 0.85 {
                let sgn: Float = l > 0 ? 1.0 : -1.0
                let excess = (abs(l) - 0.85) / 0.15
                left[i] = sgn * (0.85 + 0.138 * tanh(excess))
            }
            if abs(r) > 0.85 {
                let sgn: Float = r > 0 ? 1.0 : -1.0
                let excess = (abs(r) - 0.85) / 0.15
                right[i] = sgn * (0.85 + 0.138 * tanh(excess))
            }
        }
    }

    // MARK: - Frequency Curve Evaluation (For UI Visualization)

    public func evaluateCompositeResponse(at frequencies: [Float]) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let anySolo = profile.bands.contains { $0.isSolo }
        let activeBands = profile.bands.filter { b in
            anySolo ? (b.isSolo && b.isEnabled) : b.isEnabled
        }
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
