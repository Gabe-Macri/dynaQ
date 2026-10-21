import Foundation
import AVFoundation
import CoreAudio
import DynaQCore
import DynaQDSP

/// Manages the real-time audio pipeline, attaching DSP stages and routing audio.
public final class AudioEngineManager: @unchecked Sendable {
    public static let shared = AudioEngineManager()

    public let eqEngine: ParametricEQEngine
    public let limiter: TruePeakLimiter
    public let analyzer: SpectrumAnalyzer
    public let loudnessMeter: LoudnessMeter

    private let engine = AVAudioEngine()
    private var isRunning = false
    private let lock = NSLock()

    // Real-time telemetry callbacks
    public var onMeterUpdate: ((AudioMeter) -> Void)?
    public var onSpectrumUpdate: (([Float]) -> Void)?

    // Telemetry dispatch timer
    private var telemetryTimer: Timer?

    public init() {
        let initialProfile = DefaultPresets.studioFlat
        self.eqEngine = ParametricEQEngine(profile: initialProfile, sampleRate: 48000.0)
        self.limiter = TruePeakLimiter(ceilingDB: initialProfile.limiterCeiling, isEnabled: initialProfile.isLimiterEnabled)
        self.analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: 48000.0)
        self.loudnessMeter = LoudnessMeter()
    }

    /// Starts the audio engine with system loopback or input tap.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "dynaQ.AudioEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio hardware format."])
        }

        eqEngine.setSampleRate(Float(inputFormat.sampleRate))

        let bufferSize: AVAudioFrameCount = 512
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processAudioBuffer(buffer: buffer)
        }

        try engine.start()
        isRunning = true

        DispatchQueue.main.async { [weak self] in
            self?.startTelemetryTimer()
        }
    }

    /// Stops the audio engine and releases taps.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        DispatchQueue.main.async { [weak self] in
            self?.telemetryTimer?.invalidate()
            self?.telemetryTimer = nil
        }
    }

    public var active: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    /// Processes an incoming audio buffer through the full dynaQ DSP chain.
    public func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return }

        let left = floatData[0]
        let right = channelCount > 1 ? floatData[1] : floatData[0]

        // 1. Process Multi-band Parametric & Dynamic EQ
        eqEngine.processStereo(left: left, right: right, count: frameLength)

        // 2. Process True Peak Limiter / Clip Guard
        limiter.processStereo(left: left, right: right, count: frameLength)

        // 3. Feed Spectrum Analyzer (Mono downmix for visualizer)
        var mono = [Float](repeating: 0.0, count: frameLength)
        for i in 0..<frameLength {
            mono[i] = (left[i] + right[i]) * 0.5
        }
        mono.withUnsafeBufferPointer { ptr in
            analyzer.feed(samples: ptr.baseAddress!, count: frameLength)
        }

        // 4. Update Loudness Meter
        let meter = loudnessMeter.processStereo(left: left, right: right, count: frameLength)
        onMeterUpdate?(meter)
    }

    /// Generates synthetic test tone (pink noise + harmonic chord) to exercise DSP and spectrum visualization in demo mode.
    public func processSimulatedBuffer(frequency: Float = 440.0) {
        let frameCount = 512
        var left = [Float](repeating: 0.0, count: frameCount)
        var right = [Float](repeating: 0.0, count: frameCount)

        for i in 0..<frameCount {
            let t = Float(i) / 48000.0
            // Rich fundamental + harmonics + low-level noise
            let tone = sin(2.0 * .pi * frequency * t) * 0.3
                     + sin(2.0 * .pi * (frequency * 2.0) * t) * 0.15
                     + sin(2.0 * .pi * 80.0 * t) * 0.25
                     + Float.random(in: -0.02...0.02)
            left[i] = tone
            right[i] = tone
        }

        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                eqEngine.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)
                limiter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)

                var mono = [Float](repeating: 0.0, count: frameCount)
                for i in 0..<frameCount {
                    mono[i] = (lPtr[i] + rPtr[i]) * 0.5
                }
                mono.withUnsafeBufferPointer { mPtr in
                    analyzer.feed(samples: mPtr.baseAddress!, count: frameCount)
                }

                let meter = loudnessMeter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)
                onMeterUpdate?(meter)
            }
        }
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        // 60 fps telemetry dispatch
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let spectrum = self.analyzer.getSpectrumDB()
            self.onSpectrumUpdate?(spectrum)
        }
    }
}
