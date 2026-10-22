import Foundation
import CoreAudio
import DynaQCore
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

/// Capture source for dynaQ routing backend.
public enum AudioCaptureSource: String, CaseIterable, Sendable {
    case systemAudio = "System Audio (Tap)"
    case hardwareInput = "Hardware Microphone / Interface"
}

/// Comprehensive, actionable error descriptions for audio routing failures.
public enum AudioRouterError: LocalizedError, Equatable {
    case systemTapUnavailable(String)
    case processNotFound(String)
    case deviceNotFound(AudioDeviceID)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case sampleRateMismatch(expected: Double, actual: Double)
    case deviceDisconnected(AudioDeviceID)
    case permissionDenied(String)

    public var errorDescription: String? {
        switch self {
        case .systemTapUnavailable(let msg): return "CoreAudio System Tap Unavailable: \(msg)"
        case .processNotFound(let name): return "Audio Process Not Found: \(name)"
        case .deviceNotFound(let id): return "Audio Hardware Device #\(id) Not Found"
        case .ioProcCreationFailed(let status): return "Hardware IOProc Creation Failed (OSStatus \(status))"
        case .deviceStartFailed(let status): return "Hardware Device Start Failed (OSStatus \(status))"
        case .aggregateDeviceCreationFailed(let status): return "Tap Aggregate Device Failed (OSStatus \(status))"
        case .sampleRateMismatch(let exp, let act): return "Sample Rate Mismatch (Expected \(Int(exp)) Hz, Device is \(Int(act)) Hz)"
        case .deviceDisconnected(let id): return "Audio Device #\(id) was disconnected"
        case .permissionDenied(let msg): return "Audio Permission Denied: \(msg)"
        }
    }
}

/// Dedicated, Ultra-Lightweight Audio Routing Backend.
/// Explicitly captures audio streams (via macOS 14.2+ Process Tap or Hardware Input) and routes them directly
/// to physical output devices via low-level CoreAudio HAL.
///
/// Designed with zero DSP overhead: heavy manipulation (parametric EQ, dynamic EQ, FFT, limiting, metering)
/// is delegated entirely to the client via `AudioProcessingClient`. If no client is connected, the router
/// operates in 100% transparent zero-overhead passthrough mode (~0.0% CPU).
public final class AudioEngineManager: @unchecked Sendable {
    public static let shared = AudioEngineManager()

    private var outputIOProcID: AudioDeviceIOProcID? = nil
    private var inputHardwareIOProcID: AudioDeviceIOProcID? = nil
    public let ringBuffer = AudioRingBuffer()

    private var isRunning = false
    private let lock = NSLock()

    // Configured Hardware I/O & Routing Mode
    public var captureSource: AudioCaptureSource = .systemAudio
    public private(set) var activeInputID: AudioDeviceID?
    public private(set) var activeOutputID: AudioDeviceID?
    public var selectedTargetProcessID: AudioObjectID? = nil
    public var feedbackProtectionEnabled: Bool = true
    public var isMuted: Bool = false

    // Real-Time Buffer Diagnostic Telemetry
    public var underrunCount: Int = 0
    public func resetUnderrunCount() {
        underrunCount = 0
    }

    // Explicit Client Hook for DSP Audio Manipulation
    public weak var client: AudioProcessingClient?

    // Telemetry & Error Callbacks
    public var onLatencyUpdate: ((Double) -> Void)?
    public var onError: ((AudioRouterError) -> Void)?

    public private(set) var currentSampleRate: Double = 48000.0
    public private(set) var currentBufferFrames: UInt32 = 256

    // Pre-allocated scratch buffers for interleaved microphone/device streams (zero-allocation IOProc)
    private var leftScratch = [Float](repeating: 0.0, count: 16384)
    private var rightScratch = [Float](repeating: 0.0, count: 16384)

    public init() {}

    /// Configures and starts live system I/O routing with comprehensive error handling.
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

        guard outputID != 0 else {
            let err = AudioRouterError.deviceNotFound(0)
            onError?(err)
            throw err
        }

        self.activeOutputID = outputID
        self.activeInputID = inputID

        self.currentSampleRate = CoreAudioManager.shared.fetchAllDevices().first(where: { $0.id == outputID })?.currentSampleRate ?? 48000.0
        self.currentBufferFrames = CoreAudioManager.shared.getBufferFrameSize(deviceID: outputID)
        ringBuffer.reset()
        resetUnderrunCount()

        // 1. Connect Capture Source (System Audio Tap or Hardware Mic)
        if captureSource == .systemAudio {
            if #available(macOS 14.2, *) {
                let tap = SystemAudioTap.shared
                tap.onAudioFrames = { [weak self] left, right, count in
                    self?.ringBuffer.write(left: left, right: right, count: count)
                }
                let targets = selectedTargetProcessID != nil ? [selectedTargetProcessID!] : []
                do {
                    try tap.start(
                        targetIDs: targets,
                        muteTargetOutput: true,
                        targetSampleRate: self.currentSampleRate,
                        targetBufferSize: self.currentBufferFrames
                    )
                } catch {
                    let tapErr = AudioRouterError.systemTapUnavailable(error.localizedDescription)
                    onError?(tapErr)
                    throw tapErr
                }
            } else {
                let err = AudioRouterError.systemTapUnavailable("System Audio Tapping requires macOS 14.2 or later")
                onError?(err)
                throw err
            }
        } else {
            guard inputID != 0 else {
                let err = AudioRouterError.deviceNotFound(0)
                onError?(err)
                throw err
            }

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
                    let count = min(frameCount, 16384)
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
                let err = AudioRouterError.ioProcCreationFailed(inStatus)
                onError?(err)
                throw err
            }

            let startInStatus = AudioDeviceStart(inputID, validInProc)
            guard startInStatus == noErr else {
                AudioDeviceDestroyIOProcID(inputID, validInProc)
                let err = AudioRouterError.deviceStartFailed(startInStatus)
                onError?(err)
                throw err
            }
            self.inputHardwareIOProcID = validInProc
        }

        // 2. Attach Dedicated Output IOProc directly to physical hardware device
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

            // Split Stereo Channels (e.g. CoreAudio Standard Device)
            if abl.count >= 2, let rPtr = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                let framesRead = manager.ringBuffer.read(left: ptr, right: rPtr, count: frameCount)
                if framesRead < frameCount {
                    manager.underrunCount &+= 1
                    // Clear remainder of buffer to prevent static, buzzing, and old audio ghosting
                    let remaining = frameCount - framesRead
                    ptr.advanced(by: framesRead).update(repeating: 0.0, count: remaining)
                    rPtr.advanced(by: framesRead).update(repeating: 0.0, count: remaining)
                }

                // Explicit Routing: Hand off to client for heavy manipulation if registered; otherwise passthrough
                if let client = manager.client {
                    client.processAudioBlock(
                        left: ptr,
                        right: rPtr,
                        count: frameCount,
                        sampleRate: Float(manager.currentSampleRate)
                    )
                }

            } else if buf.mNumberChannels >= 2 {
                // Interleaved Stereo Channels (e.g. Built-in Speakers / Bluetooth AirPods)
                let countToProcess = min(frameCount, 16384)
                manager.leftScratch.withUnsafeMutableBufferPointer { lPtr in
                    manager.rightScratch.withUnsafeMutableBufferPointer { rPtr in
                        let framesRead = manager.ringBuffer.read(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: countToProcess)
                        if framesRead < countToProcess {
                            manager.underrunCount &+= 1
                            let remaining = countToProcess - framesRead
                            lPtr.baseAddress!.advanced(by: framesRead).update(repeating: 0.0, count: remaining)
                            rPtr.baseAddress!.advanced(by: framesRead).update(repeating: 0.0, count: remaining)
                        }

                        // Explicit Routing: Client DSP manipulation
                        if let client = manager.client {
                            client.processAudioBlock(
                                left: lPtr.baseAddress!,
                                right: rPtr.baseAddress!,
                                count: countToProcess,
                                sampleRate: Float(manager.currentSampleRate)
                            )
                        }

                        // Vectorized interleaving using C backend
                        c_dsp_interleave_stereo(lPtr.baseAddress!, rPtr.baseAddress!, ptr, countToProcess)
                    }
                }
            }

            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &outProcID)

        guard outStatus == noErr, let validOutProc = outProcID else {
            let err = AudioRouterError.ioProcCreationFailed(outStatus)
            onError?(err)
            throw err
        }

        let startOutStatus = AudioDeviceStart(outputID, validOutProc)
        guard startOutStatus == noErr else {
            AudioDeviceDestroyIOProcID(outputID, validOutProc)
            let err = AudioRouterError.deviceStartFailed(startOutStatus)
            onError?(err)
            throw err
        }

        self.outputIOProcID = validOutProc
        self.isRunning = true

        CoreAudioManager.shared.observeSampleRate(for: outputID)
        CoreAudioManager.shared.onSampleRateChanged = { [weak self] devID, newSR in
            self?.handleSampleRateChange(for: devID, newRate: newSR)
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateLatency()
        }
    }

    /// Explicitly handles nominal sample-rate transitions on the active audio hardware device
    /// (e.g. AirPods or external DAC shifting nominal clock between 96kHz, 48kHz, or 44.1kHz).
    public func handleSampleRateChange(for deviceID: AudioDeviceID, newRate: Double) {
        guard isRunning, let activeOut = activeOutputID, deviceID == activeOut else { return }
        guard newRate > 0 && abs(newRate - currentSampleRate) > 1.0 else { return }

        // 1. Immediately reset/flush lock-free ring buffer
        // Prevents ghost audio chunks, half-speed pitch drop, and underrun distortion
        ringBuffer.reset()

        // 2. Update internal sample rate
        self.currentSampleRate = newRate

        // 3. Inform client pipeline so all biquad filter coefficients and lookahead buffers adapt
        self.client?.sampleRateDidChange(to: Float(newRate))

        // 4. Re-calculate roundtrip latency telemetry
        DispatchQueue.main.async { [weak self] in
            self?.updateLatency()
        }
    }

    /// Stops live I/O routing.
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
        do {
            try start(captureSource: captureSource, inputDeviceID: id, outputDeviceID: activeOutputID)
        } catch {
            let defaultIn = CoreAudioManager.shared.getDefaultInputDeviceID()
            if defaultIn != id && defaultIn != 0 {
                try? start(captureSource: captureSource, inputDeviceID: defaultIn, outputDeviceID: activeOutputID)
            }
            throw error
        }
    }

    public func switchOutputDevice(id: AudioDeviceID) throws {
        do {
            try start(captureSource: captureSource, inputDeviceID: activeInputID, outputDeviceID: id)
        } catch {
            let defaultOut = CoreAudioManager.shared.getDefaultOutputDeviceID()
            if defaultOut != id && defaultOut != 0 {
                try? start(captureSource: captureSource, inputDeviceID: activeInputID, outputDeviceID: defaultOut)
            }
            throw error
        }
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
}

/// Typealias for clarity and backwards compatibility.
public typealias AudioRouterBackend = AudioEngineManager
