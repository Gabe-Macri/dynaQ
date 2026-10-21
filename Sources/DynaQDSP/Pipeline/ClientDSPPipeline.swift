import Foundation
import os.lock
import DynaQCore
import DynaQAudioDriver
import CDspKernel

/// Dedicated Client-Side DSP Processing Pipeline.
/// Concentrates all heavy audio manipulations (multi-band parametric EQ, dynamic EQ,
/// FFT spectrum analysis, true peak limiting, and BS.1770 loudness metering) strictly on the client.
public final class ClientDSPPipeline: AudioProcessingClient, @unchecked Sendable {
    public let eqEngine: ParametricEQEngine
    public let limiter: TruePeakLimiter
    public let analyzer: SpectrumAnalyzer
    public let loudnessMeter: LoudnessMeter

    public var isBypassed: Bool = false

    // Real-time telemetry buffered for low-overhead UI display timer
    private var latestMeter: AudioMeter = .silent
    private var meterLock = os_unfair_lock_s()

    public var onMeterUpdate: ((AudioMeter) -> Void)?
    public var onSpectrumUpdate: (([Float]) -> Void)?

    private var telemetryTimer: Timer?
    private var monoScratch = [Float](repeating: 0.0, count: 8192)

    public init(initialProfile: EQProfile = DefaultPresets.harmanHeadphoneTarget, sampleRate: Float = 48000.0) {
        self.eqEngine = ParametricEQEngine(profile: initialProfile, sampleRate: sampleRate)
        self.limiter = TruePeakLimiter(ceilingDB: initialProfile.limiterCeiling, isEnabled: initialProfile.isLimiterEnabled)
        self.analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: sampleRate)
        self.loudnessMeter = LoudnessMeter()
        startTelemetryTimer()
    }

    deinit {
        stopTelemetryTimer()
    }

    /// Primary Real-Time Processing Callback invoked by the audio routing backend.
    /// All heavy manipulations happen exclusively here on the client.
    public func processAudioBlock(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int,
        sampleRate: Float
    ) {
        guard !isBypassed else { return }

        // 1. Heavy Multi-band Parametric & Dynamic EQ Filtering (Vector C Kernel)
        eqEngine.processStereo(left: left, right: right, count: count)

        // 2. Heavy True Peak Soft-Knee Limiting
        limiter.processStereo(left: left, right: right, count: count)

        // 3. Fast Vectorized Stereo Downmix & FFT Spectrum Analysis Feed
        let countToProcess = min(count, 8192)
        monoScratch.withUnsafeMutableBufferPointer { mPtr in
            c_dsp_downmix_stereo_to_mono(left, right, mPtr.baseAddress!, countToProcess)
            analyzer.feed(samples: mPtr.baseAddress!, count: countToProcess)
        }

        // 4. Vectorized BS.1770 / EBU R128 Peak & RMS Loudness Metering
        let meter = loudnessMeter.processStereo(left: left, right: right, count: count)
        os_unfair_lock_lock(&meterLock)
        latestMeter = meter
        os_unfair_lock_unlock(&meterLock)
    }

    /// Updates active EQ profile and synchronizes limiter.
    public func setProfile(_ profile: EQProfile) {
        eqEngine.setProfile(profile)
        limiter.ceilingDB = profile.limiterCeiling
        limiter.isEnabled = profile.isLimiterEnabled
        isBypassed = profile.isBypassed
    }

    /// Resets clip indicators.
    public func resetClip() {
        loudnessMeter.resetClip()
        os_unfair_lock_lock(&meterLock)
        latestMeter.isClippingLeft = false
        latestMeter.isClippingRight = false
        os_unfair_lock_unlock(&meterLock)
    }

    /// Starts optimized 30fps display refresh timer (batches metering + spectrum to UI).
    public func startTelemetryTimer() {
        stopTelemetryTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                os_unfair_lock_lock(&self.meterLock)
                let meter = self.latestMeter
                os_unfair_lock_unlock(&self.meterLock)

                let spectrum = self.analyzer.getSpectrumDB()

                self.onMeterUpdate?(meter)
                self.onSpectrumUpdate?(spectrum)
            }
        }
    }

    public func stopTelemetryTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.telemetryTimer?.invalidate()
            self?.telemetryTimer = nil
        }
    }
}

