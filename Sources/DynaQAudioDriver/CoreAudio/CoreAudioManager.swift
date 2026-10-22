import Foundation
import CoreAudio
import DynaQCore

/// Interacts with CoreAudio HAL to enumerate, monitor, and configure audio hardware devices.
public final class CoreAudioManager: @unchecked Sendable {
    public static let shared = CoreAudioManager()

    private let lock = NSLock()
    public var onDevicesChanged: (([AudioDevice]) -> Void)?
    public var onDefaultOutputChanged: ((AudioDevice?) -> Void)?
    public var onDefaultInputChanged: ((AudioDevice?) -> Void)?
    public var onSampleRateChanged: ((AudioDeviceID, Double) -> Void)?
    public var onProcessesChanged: (() -> Void)?
    private var observedSampleRateDeviceID: AudioDeviceID? = nil

    public init() {
        registerPropertyListeners()
    }

    /// Enumerate all audio devices available on the system.
    public func fetchAllDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard getStatus == noErr else { return [] }

        let defaultOutID = getDefaultOutputDeviceID()
        let defaultInID = getDefaultInputDeviceID()

        var devices: [AudioDevice] = []
        for id in deviceIDs {
            if let dev = buildAudioDevice(id: id, defaultOut: defaultOutID, defaultIn: defaultInID) {
                devices.append(dev)
            }
        }
        return devices
    }

    /// Returns the system default output device ID.
    public func getDefaultOutputDeviceID() -> AudioDeviceID {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultOutputDeviceID
        )
        return defaultOutputDeviceID
    }

    /// Returns the system default input device ID.
    public func getDefaultInputDeviceID() -> AudioDeviceID {
        var defaultInputDeviceID = AudioDeviceID(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultInputDeviceID
        )
        return defaultInputDeviceID
    }

    /// Sets the macOS default system output device.
    @discardableResult
    public func setDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &devID
        )
        return status == noErr
    }

    /// Sets the macOS default system input device.
    @discardableResult
    public func setDefaultInputDevice(id: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &devID
        )
        return status == noErr
    }

    /// Sets the hardware buffer frame size (e.g. 64, 128, 256, 512, 1024 frames) on a device.
    @discardableResult
    public func setBufferFrameSize(deviceID: AudioDeviceID, frameSize: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = frameSize
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &size
        )
        return status == noErr
    }

    /// Queries the hardware buffer frame size for a device.
    public func getBufferFrameSize(deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 512
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &size)
        return size
    }

    public func getDeviceLatency(id: AudioDeviceID, isInput: Bool) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyLatency,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var latency: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &latency)
        return latency
    }

    public func getDeviceSafetyOffset(id: AudioDeviceID, isInput: Bool) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertySafetyOffset,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var offset: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &offset)
        return offset
    }

    private func buildAudioDevice(id: AudioDeviceID, defaultOut: AudioDeviceID, defaultIn: AudioDeviceID) -> AudioDevice? {
        let name = getDeviceName(id: id)
        let uid = getDeviceUID(id: id)
        let (inChannels, outChannels) = getChannelCounts(id: id)

        guard inChannels > 0 || outChannels > 0 else { return nil }

        let sampleRate = getDeviceSampleRate(id: id)
        let transport = getDeviceTransportType(id: id)
        let bufferFrames = getBufferFrameSize(deviceID: id)
        let isOut = outChannels > 0
        let latency = getDeviceLatency(id: id, isInput: !isOut)
        let safety = getDeviceSafetyOffset(id: id, isInput: !isOut)

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            isInput: inChannels > 0,
            isOutput: outChannels > 0,
            isDefaultOutput: id == defaultOut,
            isDefaultInput: id == defaultIn,
            sampleRates: [sampleRate],
            currentSampleRate: sampleRate,
            channelCount: max(inChannels, outChannels),
            bufferFrameSize: bufferFrames,
            latencyFrames: latency,
            safetyOffsetFrames: safety,
            transportType: transport
        )
    }

    private func getDeviceName(id: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameCF: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &nameCF)
        if status == noErr, let unmanaged = nameCF {
            return unmanaged.takeRetainedValue() as String
        }
        return "Audio Device \(id)"
    }

    private func getDeviceUID(id: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidCF: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &uidCF)
        if status == noErr, let unmanaged = uidCF {
            return unmanaged.takeRetainedValue() as String
        }
        return "\(id)"
    }

    private func getChannelCounts(id: AudioDeviceID) -> (inputs: Int, outputs: Int) {
        var inSize: UInt32 = 0
        var outSize: UInt32 = 0

        var inAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var outAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyDataSize(id, &inAddress, 0, nil, &inSize)
        AudioObjectGetPropertyDataSize(id, &outAddress, 0, nil, &outSize)

        let inChannels = countChannels(id: id, address: &inAddress, size: inSize)
        let outChannels = countChannels(id: id, address: &outAddress, size: outSize)

        return (inChannels, outChannels)
    }

    private func countChannels(id: AudioDeviceID, address: inout AudioObjectPropertyAddress, size: UInt32) -> Int {
        guard size > 0 else { return 0 }
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPtr.deallocate() }

        var actualSize = size
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &actualSize, bufferListPtr)
        guard status == noErr else { return 0 }

        let bufferList = bufferListPtr.pointee
        let numBuffers = Int(bufferList.mNumberBuffers)
        var totalChannels = 0

        withUnsafePointer(to: &bufferListPtr.pointee.mBuffers) { ptr in
            let buffers = UnsafeBufferPointer(start: ptr, count: numBuffers)
            for b in buffers {
                totalChannels += Int(b.mNumberChannels)
            }
        }
        return totalChannels
    }

    private func getDeviceSampleRate(id: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 48000.0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &sampleRate)
        return Double(sampleRate)
    }

    private func getDeviceTransportType(id: AudioDeviceID) -> AudioDevice.TransportType {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &transport)
        guard status == noErr else { return .builtIn }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return .displayPort
        case kAudioDeviceTransportTypeVirtual: return .virtualDevice
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        default: return .unknown
        }
    }

    /// Explicitly monitors nominal sample-rate transitions for the active physical audio device
    /// (e.g. AirPods or external DAC changing nominal clock between 96kHz, 48kHz, or 44.1kHz).
    public func observeSampleRate(for deviceID: AudioDeviceID) {
        guard deviceID != 0 else { return }
        observedSampleRateDeviceID = deviceID

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &propertyAddress, nil) { [weak self] _, _ in
            guard let self = self else { return }
            let sr = self.getDeviceSampleRate(id: deviceID)
            self.onSampleRateChanged?(deviceID, sr)
        }
    }

    private func registerPropertyListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, nil) { [weak self] _, _ in
            guard let self = self else { return }
            let devs = self.fetchAllDevices()
            self.onDevicesChanged?(devs)
        }

        var defaultOutAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutAddress, nil) { [weak self] _, _ in
            guard let self = self else { return }
            let defaultId = self.getDefaultOutputDeviceID()
            let devs = self.fetchAllDevices()
            let matched = devs.first(where: { $0.id == defaultId })
            self.onDefaultOutputChanged?(matched)
        }

        var defaultInAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInAddress, nil) { [weak self] _, _ in
            guard let self = self else { return }
            let defaultId = self.getDefaultInputDeviceID()
            let devs = self.fetchAllDevices()
            let matched = devs.first(where: { $0.id == defaultId })
            self.onDefaultInputChanged?(matched)
        }

        var processAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processAddress, nil) { [weak self] _, _ in
            self?.onProcessesChanged?()
        }
    }
}
