import Foundation
import os.lock
import DynaQCore
import DynaQAudioDriver
import DynaQDynamics
import DynaQAnalysis
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

    // Real-time lock-free SPSC visualizer ring buffer (decouples FFT & LUFS from DAC thread)
    private let visualizerRingBuffer = AudioRingBuffer(capacity: 32768)
    private var visScratchL = [Float](repeating: 0.0, count: 4096)
    private var visScratchR = [Float](repeating: 0.0, count: 4096)
    private var visScratchMono = [Float](repeating: 0.0, count: 4096)

    // Real-time telemetry buffered for low-overhead UI display timer
    private var latestMeter: AudioMeter = .silent
    private var meterLock = os_unfair_lock_s()

    public var onMeterUpdate: ((AudioMeter) -> Void)?
    public var onSpectrumUpdate: (([Float]) -> Void)?

    private var telemetryTimer: Timer?

    public init(initialProfile: EQProfile = DefaultPresets.harmanHeadphoneTarget, sampleRate: Float = 48000.0) {
        self.eqEngine = ParametricEQEngine(profile: initialProfile, sampleRate: sampleRate)
        self.limiter = TruePeakLimiter(
            ceilingDB: initialProfile.limiterCeiling,
            isEnabled: initialProfile.isLimiterEnabled,
            isLiveMode: initialProfile.isLiveMode
        )
        self.analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: sampleRate)
        self.loudnessMeter = LoudnessMeter()
        startTelemetryTimer()
    }

    deinit {
        stopTelemetryTimer()
    }

    /// Primary Real-Time Processing Callback invoked by the audio routing backend on the DAC thread.
    /// Strictly zero heap allocations, zero locks, and zero FFT/metering calculations on this thread.
    public func processAudioBlock(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int,
        sampleRate: Float
    ) {
        guard !isBypassed else { return }

        // 1. Heavy Multi-band Parametric & Dynamic EQ Filtering (Vector C Kernel)
        eqEngine.processStereo(left: left, right: right, count: count)

        // 2. Explicit M/S to L/R Decoder Matrix: Guarantee stereo is decoded to discrete L/R before limiting
        c_dsp_ensure_midside_decoded(left, right, count, eqEngine.isMidSideActive)

        // 3. True Peak Soft-Knee Limiting (Supports Zero-Latency Live Mode vs Lookahead 4x Oversampling)
        limiter.processStereo(left: left, right: right, count: count)

        // 4. Tap audio via lock-free SPSC ring buffer for background UI/worker thread
        // The DAC audio thread does ZERO FFT or LUFS math!
        visualizerRingBuffer.write(left: left, right: right, count: count)
    }

    /// Updates sample rate across all DSP engines and flushes the visualizer ring buffer.
    public func setSampleRate(_ rate: Float) {
        eqEngine.setSampleRate(rate)
        try? limiter.setSampleRate(rate)
        visualizerRingBuffer.reset()
    }

    /// AudioProcessingClient callback for hardware sample rate changes (e.g. AirPods 96kHz -> 48kHz).
    public func sampleRateDidChange(to newRate: Float) {
        setSampleRate(newRate)
    }

    /// Updates active EQ profile and synchronizes limiter.
    public func setProfile(_ profile: EQProfile) {
        eqEngine.setProfile(profile)
        limiter.ceilingDB = profile.limiterCeiling
        limiter.isEnabled = profile.isLimiterEnabled
        limiter.isLiveMode = profile.isLiveMode
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

    /// Starts optimized 30fps display refresh timer (processes visualizers on UI/worker thread).
    public func startTelemetryTimer() {
        stopTelemetryTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                // Drain pending frames from lock-free visualizer ring buffer onto worker buffers
                let maxFrames = 4096
                self.visScratchL.withUnsafeMutableBufferPointer { lPtr in
                    self.visScratchR.withUnsafeMutableBufferPointer { rPtr in
                        let framesRead = self.visualizerRingBuffer.read(
                            left: lPtr.baseAddress!,
                            right: rPtr.baseAddress!,
                            count: maxFrames
                        )
                        if framesRead > 0 {
                            // A. Vectorized Downmix & FFT Spectrum Analysis on worker thread
                            self.visScratchMono.withUnsafeMutableBufferPointer { mPtr in
                                c_dsp_downmix_stereo_to_mono(lPtr.baseAddress!, rPtr.baseAddress!, mPtr.baseAddress!, framesRead)
                                self.analyzer.feed(samples: mPtr.baseAddress!, count: framesRead)
                            }

                            // B. Vectorized BS.1770 / EBU R128 Peak & RMS Loudness Metering on worker thread
                            let meter = self.loudnessMeter.processStereo(
                                left: lPtr.baseAddress!,
                                right: rPtr.baseAddress!,
                                count: framesRead
                            )
                            os_unfair_lock_lock(&self.meterLock)
                            self.latestMeter = meter
                            os_unfair_lock_unlock(&self.meterLock)
                        }
                    }
                }

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

