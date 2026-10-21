import Foundation
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

    public init(capacity: Int = 65536) {
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

/// Capture source for dynaQ.
public enum AudioCaptureSource: String, CaseIterable, Sendable {
    case systemAudio = "System Audio (All Apps)"
    case hardwareInput = "Hardware Input (Mic/Interface)"
}

/// Fully integrated system I/O audio engine routing live audio directly through CoreAudio HAL & dynaQ DSP.
public final class AudioEngineManager: @unchecked Sendable {
    public static let shared = AudioEngineManager()

    public let eqEngine: ParametricEQEngine
    public let limiter: TruePeakLimiter
    public let analyzer: SpectrumAnalyzer
    public let loudnessMeter: LoudnessMeter

    private var outputIOProcID: AudioDeviceIOProcID? = nil
    private var inputHardwareIOProcID: AudioDeviceIOProcID? = nil
    private let ringBuffer = AudioRingBuffer(capacity: 65536)

    private var isRunning = false
    private let lock = NSLock()

    // Configured Hardware I/O & Routing Mode
    public var captureSource: AudioCaptureSource = .systemAudio
    public private(set) var activeInputID: AudioDeviceID?
    public private(set) var activeOutputID: AudioDeviceID?
    public var selectedTargetProcessID: AudioObjectID? = nil
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
        let initialProfile = DefaultPresets.harmanHeadphoneTarget
        self.eqEngine = ParametricEQEngine(profile: initialProfile, sampleRate: 48000.0)
        self.limiter = TruePeakLimiter(ceilingDB: initialProfile.limiterCeiling, isEnabled: initialProfile.isLimiterEnabled)
        self.analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: 48000.0)
        self.loudnessMeter = LoudnessMeter()
    }

    /// Configures and starts live system I/O routing.
    public func start(
        captureSource: AudioCaptureSource = .systemAudio,
        inputDeviceID: AudioDeviceID? = nil,
        outputDeviceID: AudioDeviceID? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if isRunning {
            stopInternal()
        }

        self.captureSource = captureSource
        let outputID = outputDeviceID ?? CoreAudioManager.shared.getDefaultOutputDeviceID()
        let inputID = inputDeviceID ?? CoreAudioManager.shared.getDefaultInputDeviceID()
        self.activeOutputID = outputID
        self.activeInputID = inputID

        // 1. Query hardware format & buffer sizes
        self.currentSampleRate = CoreAudioManager.shared.fetchAllDevices().first(where: { $0.id == outputID })?.currentSampleRate ?? 48000.0
        self.currentBufferFrames = CoreAudioManager.shared.getBufferFrameSize(deviceID: outputID)
        eqEngine.setSampleRate(Float(currentSampleRate))
        ringBuffer.reset()

        // 2. Connect Capture Source (System Audio Tap or Hardware Mic)
        if captureSource == .systemAudio {
            if #available(macOS 14.2, *) {
                let tap = SystemAudioTap.shared
                tap.onAudioFrames = { [weak self] left, right, count in
                    self?.ringBuffer.write(left: left, right: right, count: count)
                }
                let targets = selectedTargetProcessID != nil ? [selectedTargetProcessID!] : []
                try tap.start(targetIDs: targets, muteTargetOutput: true)
            } else {
                throw NSError(domain: "dynaQ.AudioEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "System Audio Tapping requires macOS 14.2 or later."])
            }
        } else {
            // Hardware Input mode via CoreAudio HAL IOProc
            var procID: AudioDeviceIOProcID? = nil
            let inStatus = AudioDeviceCreateIOProcID(inputID, { (_, _, inputData, _, _, _, clientData) -> OSStatus in
                guard let clientData = clientData else { return noErr }
                let manager = Unmanaged<AudioEngineManager>.fromOpaque(clientData).takeUnretainedValue()
                let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
                guard let buf = abl.first, let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                let frameCount = Int(buf.mDataByteSize) / (Int(buf.mNumberChannels) * MemoryLayout<Float>.size)

                if abl.count >= 2, let rPtr = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                    manager.ringBuffer.write(left: ptr, right: rPtr, count: frameCount)
                } else if buf.mNumberChannels >= 2 {
                    var l = [Float](repeating: 0.0, count: frameCount)
                    var r = [Float](repeating: 0.0, count: frameCount)
                    for i in 0..<frameCount {
                        l[i] = ptr[i * 2]
                        r[i] = ptr[i * 2 + 1]
                    }
                    l.withUnsafeBufferPointer { lPtr in
                        r.withUnsafeBufferPointer { rPtr in
                            manager.ringBuffer.write(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)
                        }
                    }
                } else {
                    manager.ringBuffer.write(left: ptr, right: ptr, count: frameCount)
                }
                return noErr
            }, Unmanaged.passUnretained(self).toOpaque(), &procID)

            guard inStatus == noErr, let validInProc = procID else {
                throw NSError(domain: "dynaQ.AudioEngine", code: Int(inStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to connect input hardware IOProc."])
            }
            self.inputHardwareIOProcID = validInProc
            AudioDeviceStart(inputID, validInProc)
        }

        // 3. Attach Real-Time Output IOProc directly to the physical hardware device (AirPods, Speakers, DAC)
        var outProcID: AudioDeviceIOProcID? = nil
        let outStatus = AudioDeviceCreateIOProcID(outputID, { (_, _, _, _, outputData, _, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<AudioEngineManager>.fromOpaque(clientData).takeUnretainedValue()
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            guard let buf = abl.first, let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frameCount = Int(buf.mDataByteSize) / (Int(buf.mNumberChannels) * MemoryLayout<Float>.size)

            // Feedback guard check
            let isSpeaker = manager.isBuiltInSpeaker(deviceID: manager.activeOutputID)
            let isMic = manager.isBuiltInMic(deviceID: manager.activeInputID)
            let muteFeedback = manager.captureSource == .hardwareInput && manager.feedbackProtectionEnabled && isSpeaker && isMic

            if manager.isMuted || muteFeedback {
                for i in 0..<(frameCount * Int(buf.mNumberChannels)) {
                    ptr[i] = 0.0
                }
                return noErr
            }

            if abl.count >= 2, let rPtr = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                // Non-interleaved (Stereo)
                _ = manager.ringBuffer.read(left: ptr, right: rPtr, count: frameCount)
                manager.eqEngine.processStereo(left: ptr, right: rPtr, count: frameCount)
                manager.limiter.processStereo(left: ptr, right: rPtr, count: frameCount)

                // Telemetry
                var mono = [Float](repeating: 0.0, count: frameCount)
                for i in 0..<frameCount { mono[i] = (ptr[i] + rPtr[i]) * 0.5 }
                mono.withUnsafeBufferPointer { mPtr in manager.analyzer.feed(samples: mPtr.baseAddress!, count: frameCount) }
                let meter = manager.loudnessMeter.processStereo(left: ptr, right: rPtr, count: frameCount)
                manager.onMeterUpdate?(meter)

            } else if buf.mNumberChannels >= 2 {
                // Interleaved (Stereo)
                var left = [Float](repeating: 0.0, count: frameCount)
                var right = [Float](repeating: 0.0, count: frameCount)
                _ = manager.ringBuffer.read(left: &left, right: &right, count: frameCount)

                left.withUnsafeMutableBufferPointer { lPtr in
                    right.withUnsafeMutableBufferPointer { rPtr in
                        manager.eqEngine.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)
                        manager.limiter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)

                        for i in 0..<frameCount {
                            ptr[i * 2] = lPtr[i]
                            ptr[i * 2 + 1] = rPtr[i]
                        }

                        var mono = [Float](repeating: 0.0, count: frameCount)
                        for i in 0..<frameCount { mono[i] = (lPtr[i] + rPtr[i]) * 0.5 }
                        mono.withUnsafeBufferPointer { mPtr in manager.analyzer.feed(samples: mPtr.baseAddress!, count: frameCount) }
                        let meter = manager.loudnessMeter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: frameCount)
                        manager.onMeterUpdate?(meter)
                    }
                }
            }

            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &outProcID)

        guard outStatus == noErr, let validOutProc = outProcID else {
            throw NSError(domain: "dynaQ.AudioEngine", code: Int(outStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to create hardware output IOProc (OSStatus \(outStatus))"])
        }
        self.outputIOProcID = validOutProc
        AudioDeviceStart(outputID, validOutProc)

        self.isRunning = true

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

        if #available(macOS 14.2, *) {
            SystemAudioTap.shared.stop()
        }

        if let inProc = inputHardwareIOProcID, let inID = activeInputID {
            AudioDeviceStop(inID, inProc)
            AudioDeviceDestroyIOProcID(inID, inProc)
            inputHardwareIOProcID = nil
        }

        if let outProc = outputIOProcID, let outID = activeOutputID {
            AudioDeviceStop(outID, outProc)
            AudioDeviceDestroyIOProcID(outID, outProc)
            outputIOProcID = nil
        }

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

    public func setCaptureSource(_ source: AudioCaptureSource) throws {
        try start(captureSource: source, inputDeviceID: activeInputID, outputDeviceID: activeOutputID)
    }

    public func setTargetProcess(id: AudioObjectID?) throws {
        self.selectedTargetProcessID = id
        try start(captureSource: captureSource, inputDeviceID: activeInputID, outputDeviceID: activeOutputID)
    }

    public func switchInputDevice(id: AudioDeviceID) throws {
        try start(captureSource: captureSource, inputDeviceID: id, outputDeviceID: activeOutputID)
    }

    public func switchOutputDevice(id: AudioDeviceID) throws {
        try start(captureSource: captureSource, inputDeviceID: activeInputID, outputDeviceID: id)
    }

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

    public func updateLatency() {
        guard currentSampleRate > 0 else { return }
        let outID = activeOutputID ?? CoreAudioManager.shared.getDefaultOutputDeviceID()
        let outLat = CoreAudioManager.shared.getDeviceLatency(id: outID, isInput: false)
        let outSafety = CoreAudioManager.shared.getDeviceSafetyOffset(id: outID, isInput: false)

        let totalFrames = Double(currentBufferFrames + outLat + outSafety)
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
