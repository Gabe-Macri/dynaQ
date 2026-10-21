import Foundation
import CoreAudio
import os.lock
import DynaQCore
import DynaQDSP
import CDspKernel

/// High-performance lock-free atomic single-producer single-consumer stereo ring buffer.
/// Completely eliminates thread locks and mutexes from the real-time audio thread using C atomic memory fences.
public final class AudioRingBuffer: @unchecked Sendable {
    private var cBuffer: OpaquePointer?

    public init(capacity: Int = 65536) {
        self.cBuffer = c_ringbuffer_create(capacity)
    }

    deinit {
        if let buf = cBuffer {
            c_ringbuffer_destroy(buf)
        }
    }

    @inline(__always)
    public func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) {
        guard let buf = cBuffer else { return }
        _ = c_ringbuffer_write_stereo(buf, left, right, count)
    }

    @inline(__always)
    public func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) -> Int {
        guard let buf = cBuffer else { return 0 }
        return Int(c_ringbuffer_read_stereo(buf, left, right, count))
    }

    public func reset() {
        guard let buf = cBuffer else { return }
        c_ringbuffer_reset(buf)
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
    private let ringBuffer = AudioRingBuffer()

    private var isRunning = false
    private let lock = NSLock()

    // Configured Hardware I/O & Routing Mode
    public var captureSource: AudioCaptureSource = .systemAudio
    public private(set) var activeInputID: AudioDeviceID?
    public private(set) var activeOutputID: AudioDeviceID?
    public var selectedTargetProcessID: AudioObjectID? = nil
    public var feedbackProtectionEnabled: Bool = true
    public var isMuted: Bool = false

    // Real-time telemetry: buffered for low-overhead display timer
    private var latestMeter: AudioMeter = .silent
    private var meterLock = os_unfair_lock_s()

    // Pre-allocated real-time scratch buffers (zero heap alloc on audio thread)
    private var monoScratch = [Float](repeating: 0.0, count: 8192)
    private var leftScratch = [Float](repeating: 0.0, count: 8192)
    private var rightScratch = [Float](repeating: 0.0, count: 8192)

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

        self.currentSampleRate = CoreAudioManager.shared.fetchAllDevices().first(where: { $0.id == outputID })?.currentSampleRate ?? 48000.0
        self.currentBufferFrames = CoreAudioManager.shared.getBufferFrameSize(deviceID: outputID)
        eqEngine.setSampleRate(Float(currentSampleRate))
        ringBuffer.reset()

        // 1. Connect Capture Source (System Audio Tap or Hardware Mic)
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
                    let count = min(frameCount, 8192)
                    manager.leftScratch.withUnsafeMutableBufferPointer { lPtr in
                        manager.rightScratch.withUnsafeMutableBufferPointer { rPtr in
                            c_dsp_deinterleave_stereo(ptr, lPtr.baseAddress!, rPtr.baseAddress!, count)
                            manager.ringBuffer.write(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: count)
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

        // 2. Attach Real-Time Output IOProc directly to the physical hardware device
        var outProcID: AudioDeviceIOProcID? = nil
        let outStatus = AudioDeviceCreateIOProcID(outputID, { (_, _, _, _, outputData, _, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<AudioEngineManager>.fromOpaque(clientData).takeUnretainedValue()
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            guard let buf = abl.first, let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frameCount = Int(buf.mDataByteSize) / (Int(buf.mNumberChannels) * MemoryLayout<Float>.size)

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
                _ = manager.ringBuffer.read(left: ptr, right: rPtr, count: frameCount)
                manager.eqEngine.processStereo(left: ptr, right: rPtr, count: frameCount)
                manager.limiter.processStereo(left: ptr, right: rPtr, count: frameCount)

                // Fast analyzer feed (downmix using C vector helper)
                let countToProcess = min(frameCount, 8192)
                manager.monoScratch.withUnsafeMutableBufferPointer { mPtr in
                    c_dsp_downmix_stereo_to_mono(ptr, rPtr, mPtr.baseAddress!, countToProcess)
                    manager.analyzer.feed(samples: mPtr.baseAddress!, count: countToProcess)
                }

                // Measure loudness into local state (NO main-thread dispatch from audio thread!)
                let meter = manager.loudnessMeter.processStereo(left: ptr, right: rPtr, count: frameCount)
                os_unfair_lock_lock(&manager.meterLock)
                manager.latestMeter = meter
                os_unfair_lock_unlock(&manager.meterLock)

            } else if buf.mNumberChannels >= 2 {
                let countToProcess = min(frameCount, 8192)
                manager.leftScratch.withUnsafeMutableBufferPointer { lPtr in
                    manager.rightScratch.withUnsafeMutableBufferPointer { rPtr in
                        _ = manager.ringBuffer.read(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: countToProcess)

                        manager.eqEngine.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: countToProcess)
                        manager.limiter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: countToProcess)

                        // Vectorized interleaving using C backend
                        c_dsp_interleave_stereo(lPtr.baseAddress!, rPtr.baseAddress!, ptr, countToProcess)

                        manager.monoScratch.withUnsafeMutableBufferPointer { mPtr in
                            c_dsp_downmix_stereo_to_mono(lPtr.baseAddress!, rPtr.baseAddress!, mPtr.baseAddress!, countToProcess)
                            manager.analyzer.feed(samples: mPtr.baseAddress!, count: countToProcess)
                        }

                        let meter = manager.loudnessMeter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: countToProcess)
                        os_unfair_lock_lock(&manager.meterLock)
                        manager.latestMeter = meter
                        os_unfair_lock_unlock(&manager.meterLock)
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

    /// Smooth, optimized 30fps display refresh timer (batches metering + spectrum to main thread).
    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
