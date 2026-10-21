import Foundation
import AVFoundation
import CoreAudio
import os.lock
import DynaQCore
import DynaQDSP

/// High-performance thread-safe stereo ring buffer for real-time audio sample streaming.
public final class AudioRingBuffer: @unchecked Sendable {
    private var leftBuffer: [Float]
    private var rightBuffer: [Float]
    private let capacity: Int
    private var writeHead: Int = 0
    private var readHead: Int = 0
    private var availableFrames: Int = 0
    private var lock = os_unfair_lock_s()

    public init(capacity: Int = 32768) {
        self.capacity = capacity
        self.leftBuffer = [Float](repeating: 0.0, count: capacity)
        self.rightBuffer = [Float](repeating: 0.0, count: capacity)
    }

    public func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let framesToWrite = min(count, capacity - availableFrames)
        for i in 0..<framesToWrite {
            leftBuffer[writeHead] = left[i]
            rightBuffer[writeHead] = right[i]
            writeHead = (writeHead + 1) % capacity
        }
        availableFrames = min(availableFrames + framesToWrite, capacity)
    }

    public func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let framesToRead = min(count, availableFrames)
        for i in 0..<framesToRead {
            left[i] = leftBuffer[readHead]
            right[i] = rightBuffer[readHead]
            readHead = (readHead + 1) % capacity
        }
        availableFrames -= framesToRead

        // Zero-fill remaining if buffer underrun
        if framesToRead < count {
            for i in framesToRead..<count {
                left[i] = 0.0
                right[i] = 0.0
            }
        }
        return framesToRead
    }

    public func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        writeHead = 0
        readHead = 0
        availableFrames = 0
        leftBuffer.fill(with: 0.0)
        rightBuffer.fill(with: 0.0)
    }
}

private extension Array where Element == Float {
    mutating func fill(with value: Float) {
        for i in 0..<count { self[i] = value }
    }
}

/// Fully integrated system I/O audio engine routing live CoreAudio hardware through dynaQ DSP.
public final class AudioEngineManager: @unchecked Sendable {
    public static let shared = AudioEngineManager()

    public let eqEngine: ParametricEQEngine
    public let limiter: TruePeakLimiter
    public let analyzer: SpectrumAnalyzer
    public let loudnessMeter: LoudnessMeter

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let ringBuffer = AudioRingBuffer(capacity: 32768)

    private var isRunning = false
    private let lock = NSLock()

    // Configured Hardware I/O
    public private(set) var activeInputID: AudioDeviceID?
    public private(set) var activeOutputID: AudioDeviceID?
    public var feedbackProtectionEnabled: Bool = true
    public var isMuted: Bool = false

    // Real-time telemetry callbacks
    public var onMeterUpdate: ((AudioMeter) -> Void)?
    public var onSpectrumUpdate: (([Float]) -> Void)?
    public var onLatencyUpdate: ((Double) -> Void)?

    private var telemetryTimer: Timer?
    private var currentSampleRate: Double = 48000.0
    private var currentBufferFrames: UInt32 = 256

    public init() {
        let initialProfile = DefaultPresets.studioFlat
        self.eqEngine = ParametricEQEngine(profile: initialProfile, sampleRate: 48000.0)
        self.limiter = TruePeakLimiter(ceilingDB: initialProfile.limiterCeiling, isEnabled: initialProfile.isLimiterEnabled)
        self.analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: 48000.0)
        self.loudnessMeter = LoudnessMeter()
    }

    /// Configures and starts live system I/O routing.
    public func start(inputDeviceID: AudioDeviceID? = nil, outputDeviceID: AudioDeviceID? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        if isRunning {
            stopInternal()
        }

        let inputID = inputDeviceID ?? CoreAudioManager.shared.getDefaultInputDeviceID()
        let outputID = outputDeviceID ?? CoreAudioManager.shared.getDefaultOutputDeviceID()
        self.activeInputID = inputID
        self.activeOutputID = outputID

        // 1. Assign hardware devices to AVAudioEngine AUHAL nodes
        if let inputAU = engine.inputNode.audioUnit {
            var inDev = inputID
            AudioUnitSetProperty(
                inputAU,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &inDev,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        if let outputAU = engine.outputNode.audioUnit {
            var outDev = outputID
            AudioUnitSetProperty(
                outputAU,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &outDev,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        // 2. Fetch negotiated format
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "dynaQ.AudioEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hardware sample rate invalid."])
        }

        self.currentSampleRate = inputFormat.sampleRate
        self.currentBufferFrames = CoreAudioManager.shared.getBufferFrameSize(deviceID: outputID)
        eqEngine.setSampleRate(Float(currentSampleRate))
        ringBuffer.reset()

        // 3. Install capture tap on Input Node
        let tapBufferSize: AVAudioFrameCount = max(currentBufferFrames, 128)
        engine.inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let floatData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            let left = floatData[0]
            let right = channels > 1 ? floatData[1] : floatData[0]
            self.ringBuffer.write(left: left, right: right, count: frames)
        }

        // 4. Create Source Node for live DSP output
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 2)!
        let newSourceNode = AVAudioSourceNode(format: stereoFormat) { [weak self] _, _, frameCount, outputData -> OSStatus in
            guard let self = self else { return noErr }
            let frames = Int(frameCount)
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            guard ablPointer.count >= 2,
                  let outLeft = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let outRight = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            // Check feedback protection (prevent mic howl when using built-in speakers)
            let isSpeaker = self.isBuiltInSpeaker(deviceID: self.activeOutputID)
            let isMic = self.isBuiltInMic(deviceID: self.activeInputID)
            let muteForFeedback = self.feedbackProtectionEnabled && isSpeaker && isMic

            if self.isMuted || muteForFeedback {
                for i in 0..<frames {
                    outLeft[i] = 0.0
                    outRight[i] = 0.0
                }
                return noErr
            }

            // Read live stream from ring buffer
            _ = self.ringBuffer.read(left: outLeft, right: outRight, count: frames)

            // Real-time DSP Processing Chain:
            // 1. Parametric & Dynamic EQ
            self.eqEngine.processStereo(left: outLeft, right: outRight, count: frames)

            // 2. True Peak Limiter / Clip Guard
            self.limiter.processStereo(left: outLeft, right: outRight, count: frames)

            // 3. Telemetry: FFT Spectrum Analyzer (downmix)
            var mono = [Float](repeating: 0.0, count: frames)
            for i in 0..<frames {
                mono[i] = (outLeft[i] + outRight[i]) * 0.5
            }
            mono.withUnsafeBufferPointer { mPtr in
                self.analyzer.feed(samples: mPtr.baseAddress!, count: frames)
            }

            // 4. Telemetry: Loudness Meter
            let meter = self.loudnessMeter.processStereo(left: outLeft, right: outRight, count: frames)
            self.onMeterUpdate?(meter)

            return noErr
        }

        self.sourceNode = newSourceNode
        engine.attach(newSourceNode)
        engine.connect(newSourceNode, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: stereoFormat)

        try engine.start()
        isRunning = true

        DispatchQueue.main.async { [weak self] in
            self?.startTelemetryTimer()
            self?.updateLatency()
        }
    }

    /// Stops the live I/O engine.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopInternal()
    }

    private func stopInternal() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        engine.stop()
        isRunning = false
        ringBuffer.reset()

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

    /// Switches the hardware input device.
    public func switchInputDevice(id: AudioDeviceID) throws {
        try start(inputDeviceID: id, outputDeviceID: activeOutputID)
    }

    /// Switches the hardware output device.
    public func switchOutputDevice(id: AudioDeviceID) throws {
        try start(inputDeviceID: activeInputID, outputDeviceID: id)
    }

    /// Sets the hardware buffer size on the active devices.
    public func setBufferFrameSize(_ frames: UInt32) {
        if let outID = activeOutputID {
            CoreAudioManager.shared.setBufferFrameSize(deviceID: outID, frameSize: frames)
        }
        if let inID = activeInputID {
            CoreAudioManager.shared.setBufferFrameSize(deviceID: inID, frameSize: frames)
        }
        self.currentBufferFrames = frames
        updateLatency()
    }

    /// Computes and dispatches real roundtrip hardware latency in milliseconds.
    public func updateLatency() {
        guard currentSampleRate > 0 else { return }
        let inID = activeInputID ?? CoreAudioManager.shared.getDefaultInputDeviceID()
        let outID = activeOutputID ?? CoreAudioManager.shared.getDefaultOutputDeviceID()

        let inLat = CoreAudioManager.shared.getDeviceLatency(id: inID, isInput: true)
        let inSafety = CoreAudioManager.shared.getDeviceSafetyOffset(id: inID, isInput: true)
        let outLat = CoreAudioManager.shared.getDeviceLatency(id: outID, isInput: false)
        let outSafety = CoreAudioManager.shared.getDeviceSafetyOffset(id: outID, isInput: false)

        let totalFrames = Double(currentBufferFrames * 2 + inLat + inSafety + outLat + outSafety)
        let roundtripMs = (totalFrames / currentSampleRate) * 1000.0
        onLatencyUpdate?(roundtripMs)
    }

    private func isBuiltInSpeaker(deviceID: AudioDeviceID?) -> Bool {
        guard let id = deviceID else { return false }
        let dev = CoreAudioManager.shared.fetchAllDevices().first(where: { $0.id == id })
        return dev?.transportType == .builtIn && dev?.isOutput == true
    }

    private func isBuiltInMic(deviceID: AudioDeviceID?) -> Bool {
        guard let id = deviceID else { return false }
        let dev = CoreAudioManager.shared.fetchAllDevices().first(where: { $0.id == id })
        return dev?.transportType == .builtIn && dev?.isInput == true
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let spectrum = self.analyzer.getSpectrumDB()
            self.onSpectrumUpdate?(spectrum)
        }
    }
}
