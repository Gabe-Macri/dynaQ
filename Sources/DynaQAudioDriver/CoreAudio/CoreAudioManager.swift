import Foundation
import CoreAudio
import DynaQCore

/// Interacts with CoreAudio HAL to enumerate, monitor, and configure audio hardware devices.
public final class CoreAudioManager: @unchecked Sendable {
    public static let shared = CoreAudioManager()

    private let lock = NSLock()
    public var onDevicesChanged: (([AudioDevice]) -> Void)?
    public var onDefaultOutputChanged: ((AudioDevice?) -> Void)?

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

    private func buildAudioDevice(id: AudioDeviceID, defaultOut: AudioDeviceID, defaultIn: AudioDeviceID) -> AudioDevice? {
        let name = getDeviceName(id: id)
        let uid = getDeviceUID(id: id)
        let (inChannels, outChannels) = getChannelCounts(id: id)

        guard inChannels > 0 || outChannels > 0 else { return nil }

        let sampleRate = getDeviceSampleRate(id: id)
        let transport = getDeviceTransportType(id: id)

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
            mScope: kAudioDevicePropertyScopeOutput,
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
    }
}
