import Foundation

/// Represents an audio hardware or virtual device discovered via CoreAudio.
public struct AudioDevice: Identifiable, Codable, Equatable, Sendable {
    public var id: UInt32            // CoreAudio AudioDeviceID / AudioObjectID
    public var uid: String           // Persistent unique identifier
    public var name: String
    public var manufacturer: String
    public var isInput: Bool
    public var isOutput: Bool
    public var isDefaultOutput: Bool
    public var isDefaultInput: Bool
    public var sampleRates: [Double]
    public var currentSampleRate: Double
    public var channelCount: Int
    public var transportType: TransportType

    public enum TransportType: String, Codable, Sendable {
        case builtIn = "Built-in"
        case usb = "USB"
        case bluetooth = "Bluetooth"
        case thunderbolt = "Thunderbolt"
        case displayPort = "DisplayPort / HDMI"
        case virtualDevice = "Virtual / Loopback"
        case aggregate = "Aggregate"
        case unknown = "Other"

        public var sfSymbol: String {
            switch self {
            case .builtIn: return "laptopcomputer"
            case .usb: return "cable.connector"
            case .bluetooth: return "airpodspro"
            case .thunderbolt: return "bolt.fill"
            case .displayPort: return "display"
            case .virtualDevice: return "arrow.triangle.2.circlepath"
            case .aggregate: return "square.stack.3d.down.right"
            case .unknown: return "speaker.wave.2"
            }
        }
    }

    public init(
        id: UInt32,
        uid: String,
        name: String,
        manufacturer: String = "Apple Inc.",
        isInput: Bool = false,
        isOutput: Bool = true,
        isDefaultOutput: Bool = false,
        isDefaultInput: Bool = false,
        sampleRates: [Double] = [44100.0, 48000.0, 96000.0],
        currentSampleRate: Double = 48000.0,
        channelCount: Int = 2,
        transportType: TransportType = .builtIn
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.isInput = isInput
        self.isOutput = isOutput
        self.isDefaultOutput = isDefaultOutput
        self.isDefaultInput = isDefaultInput
        self.sampleRates = sampleRates
        self.currentSampleRate = currentSampleRate
        self.channelCount = channelCount
        self.transportType = transportType
    }
}

