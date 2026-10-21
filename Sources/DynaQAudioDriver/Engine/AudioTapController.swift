import Foundation
import CoreAudio
import DynaQCore

/// Manages system-wide audio tapping via modern macOS CoreAudio Process Tap (macOS 14.2+).
@available(macOS 14.2, *)
public final class SystemAudioTap: @unchecked Sendable {
    public static let shared = SystemAudioTap()

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var tapIOProcID: AudioDeviceIOProcID? = nil
    private var isRunning: Bool = false
    private let lock = NSLock()

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

    /// Creates and starts the global macOS system audio tap.
    public func start(muteSystemOutput: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        // 1. Identify our process AudioObjectID to exclude dynaQ from its own tap (feedback prevention)
        let myProcessObjectID = getMyProcessObjectID()
        let excluded: [AudioObjectID] = myProcessObjectID != nil ? [myProcessObjectID!] : []

        // 2. Build CATapDescription
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        tapDesc.name = "dynaQ System Audio Tap"
        tapDesc.muteBehavior = muteSystemOutput ? CATapMuteBehavior.mutedWhenTapped : CATapMuteBehavior.unmuted

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

        // 5. Install IOProc on the Aggregate Tap Device
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
                    var left = [Float](repeating: 0.0, count: frameCount)
                    var right = [Float](repeating: 0.0, count: frameCount)
                    for i in 0..<frameCount {
                        left[i] = ptr[i * 2]
                        right[i] = ptr[i * 2 + 1]
                    }
                    left.withUnsafeBufferPointer { lPtr in
                        right.withUnsafeBufferPointer { rPtr in
                            tapSelf.onAudioFrames?(lPtr.baseAddress!, rPtr.baseAddress!, frameCount)
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

    private func getMyProcessObjectID() -> AudioObjectID? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processIDs)

        for objID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var procPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let s = AudioObjectGetPropertyData(objID, &pidAddress, 0, nil, &pidSize, &procPID)
            if s == noErr && procPID == currentPID {
                return objID
            }
        }
        return nil
    }
}
