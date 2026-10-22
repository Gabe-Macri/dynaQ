import Foundation
import CoreAudio
import DynaQCore
import CDspKernel

/// Discovered macOS audio application available for equalization.
public struct AudioAppProcess: Identifiable, Hashable, Sendable {
    public var id: AudioObjectID
    public var pid: pid_t
    public var bundleID: String
    public var name: String

    public init(id: AudioObjectID, pid: pid_t, bundleID: String, name: String) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// Manages system-wide audio tapping via modern macOS CoreAudio Process Tap (macOS 14.2+).
@available(macOS 14.2, *)
public final class SystemAudioTap: @unchecked Sendable {
    public static let shared = SystemAudioTap()

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var tapIOProcID: AudioDeviceIOProcID? = nil
    private var isRunning: Bool = false
    public private(set) var isWaitingForProcesses: Bool = false
    private var lastTargetIDs: [AudioObjectID] = []
    private var lastMute: Bool = true
    private var lastSampleRate: Double? = nil
    private var lastBufferSize: UInt32? = nil
    private let lock = NSLock()

    // Pre-allocated scratch buffers for zero-allocation real-time deinterleaving
    private var deinterleaveLeft = [Float](repeating: 0.0, count: 16384)
    private var deinterleaveRight = [Float](repeating: 0.0, count: 16384)

    public var onAudioFrames: ((UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public var active: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    /// Enumerate all running applications registered with CoreAudio.
    public func fetchAudioProcesses() -> [AudioAppProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processIDs)

        let myPID = ProcessInfo.processInfo.processIdentifier
        var results: [AudioAppProcess] = []

        for objID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var procPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let s1 = AudioObjectGetPropertyData(objID, &pidAddress, 0, nil, &pidSize, &procPID)
            guard s1 == noErr, procPID > 0, procPID != myPID else { continue }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleCF: Unmanaged<CFString>?
            var bSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(objID, &bundleAddress, 0, nil, &bSize, &bundleCF)
            let bundle = bundleCF?.takeRetainedValue() as String? ?? ""

            // Clean display name
            var name = bundle
            if let last = bundle.split(separator: ".").last {
                name = String(last)
            }
            if name.isEmpty { name = "Process \(procPID)" }

            results.append(AudioAppProcess(id: objID, pid: procPID, bundleID: bundle, name: name))
        }

        return results
    }

    /// Creates and starts tapping target processes. If targetIDs is empty, captures all active audio processes.
    public func start(
        targetIDs: [AudioObjectID] = [],
        muteTargetOutput: Bool = true,
        targetSampleRate: Double? = nil,
        targetBufferSize: UInt32? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        self.lastTargetIDs = targetIDs
        self.lastMute = muteTargetOutput
        self.lastSampleRate = targetSampleRate
        self.lastBufferSize = targetBufferSize

        // 1. Determine processes to tap
        var processList = targetIDs
        if processList.isEmpty {
            let apps = fetchAudioProcesses()
            processList = apps.map { $0.id }
        }

        // Auto-route resilience: If no active audio processes exist on startup, enter standby listening mode
        guard !processList.isEmpty else {
            self.isWaitingForProcesses = true
            return
        }

        self.isWaitingForProcesses = false
        try startTapInternal(
            processList: processList,
            muteTargetOutput: muteTargetOutput,
            targetSampleRate: targetSampleRate,
            targetBufferSize: targetBufferSize
        )
    }

    /// Automatically attaches to audio processes when they appear (auto-route on startup / playback).
    public func checkAndAttachPendingProcesses() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning, isWaitingForProcesses else { return }
        var processList = lastTargetIDs
        if processList.isEmpty {
            let apps = fetchAudioProcesses()
            processList = apps.map { $0.id }
        }

        guard !processList.isEmpty else { return }
        self.isWaitingForProcesses = false
        try? startTapInternal(
            processList: processList,
            muteTargetOutput: lastMute,
            targetSampleRate: lastSampleRate,
            targetBufferSize: lastBufferSize
        )
    }

    private func startTapInternal(
        processList: [AudioObjectID],
        muteTargetOutput: Bool,
        targetSampleRate: Double?,
        targetBufferSize: UInt32?
    ) throws {

        // 2. Build CATapDescription with .mutedWhenTapped so raw audio is redirected ONLY through dynaQ
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: processList)
        tapDesc.name = "dynaQ Audio Stream Tap"
        tapDesc.muteBehavior = muteTargetOutput ? CATapMuteBehavior.mutedWhenTapped : CATapMuteBehavior.unmuted

        var newTapID = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            throw NSError(
                domain: "dynaQ.SystemAudioTap",
                code: Int(tapStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create CoreAudio Process Tap (OSStatus \(tapStatus))"]
            )
        }
        self.tapID = newTapID

        // 3. Query Tap UID
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidCF: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = AudioObjectGetPropertyData(newTapID, &uidAddress, 0, nil, &uidSize, &uidCF)
        guard uidStatus == noErr, let tapUID = uidCF?.takeRetainedValue() as String? else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw NSError(
                domain: "dynaQ.SystemAudioTap",
                code: Int(uidStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to get Tap UID."]
            )
        }

        // 4. Create an Aggregate Device wrapping the Tap
        let aggUID = "com.dynaq.audiotap.\(UUID().uuidString)"
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "dynaQ System Audio Capture",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ]
        ]

        var newAggregateID = AudioDeviceID(0)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &newAggregateID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw NSError(
                domain: "dynaQ.SystemAudioTap",
                code: Int(aggStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create Tap Aggregate Device (OSStatus \(aggStatus))"]
            )
        }
        self.aggregateID = newAggregateID

        // Synchronize nominal sample rate and buffer frame size with physical output device
        if let targetSR = targetSampleRate, targetSR > 8000.0 {
            var sr = Float64(targetSR)
            var srAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(newAggregateID, &srAddress, 0, nil, UInt32(MemoryLayout<Float64>.size), &sr)
        }

        if let bufSize = targetBufferSize, bufSize > 0 {
            var frames = bufSize
            var bufAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(newAggregateID, &bufAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        }

        // 5. Install IOProc on the Aggregate Tap Device (Zero-allocation path)
        var procID: AudioDeviceIOProcID? = nil
        let procStatus = AudioDeviceCreateIOProcID(newAggregateID, { (_, _, inputData, _, _, _, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let tapSelf = Unmanaged<SystemAudioTap>.fromOpaque(clientData).takeUnretainedValue()
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))

            guard abl.count >= 1, let buf = abl.first, let rawData = buf.mData else { return noErr }
            let frameCount = Int(buf.mDataByteSize) / (Int(buf.mNumberChannels) * MemoryLayout<Float>.size)
            let ptr = rawData.assumingMemoryBound(to: Float.self)

            if buf.mNumberChannels >= 2 {
                if abl.count >= 2, let rRaw = abl[1].mData {
                    let rPtr = rRaw.assumingMemoryBound(to: Float.self)
                    tapSelf.onAudioFrames?(ptr, rPtr, frameCount)
                } else {
                    let countToProcess = min(frameCount, 16384)
                    tapSelf.deinterleaveLeft.withUnsafeMutableBufferPointer { lPtr in
                        tapSelf.deinterleaveRight.withUnsafeMutableBufferPointer { rPtr in
                            c_dsp_deinterleave_stereo(ptr, lPtr.baseAddress!, rPtr.baseAddress!, countToProcess)
                            tapSelf.onAudioFrames?(lPtr.baseAddress!, rPtr.baseAddress!, countToProcess)
                        }
                    }
                }
            } else {
                tapSelf.onAudioFrames?(ptr, ptr, frameCount)
            }

            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &procID)

        guard procStatus == noErr, let validProcID = procID else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw NSError(
                domain: "dynaQ.SystemAudioTap",
                code: Int(procStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to attach IOProc to Tap Device."]
            )
        }
        self.tapIOProcID = validProcID

        let startStatus = AudioDeviceStart(newAggregateID, validProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newAggregateID, validProcID)
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw NSError(
                domain: "dynaQ.SystemAudioTap",
                code: Int(startStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to start Tap Device (OSStatus \(startStatus))"]
            )
        }

        self.isRunning = true
    }

    /// Stops the system audio tap and destroys temporary aggregate devices.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        isWaitingForProcesses = false
        guard isRunning else { return }

        if let proc = tapIOProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
            tapIOProcID = nil
        }

        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        isRunning = false
    }
}
