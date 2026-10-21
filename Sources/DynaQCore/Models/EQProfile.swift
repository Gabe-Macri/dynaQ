import Foundation

/// Master monitor audition mode.
public enum MonitorMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case stereo = "Stereo"
    case mono = "Mono"
    case sides = "Sides"
    case leftOnly = "Left"
    case rightOnly = "Right"

    public var id: String { rawValue }
}

/// Represents a full equalizer preset or profile configuration.
public struct EQProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String
    public var notes: String
    public var bands: [EQBand]
    public var preampGain: Float        // Preamp gain in dB (-18.0 to +18.0)
    public var masterGain: Float        // Master output gain in dB (-18.0 to +18.0)
    public var isBypassed: Bool
    public var isLimiterEnabled: Bool
    public var limiterCeiling: Float    // Ceiling in dBFS (e.g. -0.2 dBFS)
    public var phaseInvert: Bool        // 180° polarity flip
    public var monitorMode: MonitorMode
    public var isFactory: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "Custom",
        notes: String = "",
        bands: [EQBand],
        preampGain: Float = 0.0,
        masterGain: Float = 0.0,
        isBypassed: Bool = false,
        isLimiterEnabled: Bool = true,
        limiterCeiling: Float = -0.2,
        phaseInvert: Bool = false,
        monitorMode: MonitorMode = .stereo,
        isFactory: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.notes = notes
        self.bands = bands
        self.preampGain = preampGain
        self.masterGain = masterGain
        self.isBypassed = isBypassed
        self.isLimiterEnabled = isLimiterEnabled
        self.limiterCeiling = limiterCeiling
        self.phaseInvert = phaseInvert
        self.monitorMode = monitorMode
        self.isFactory = isFactory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Returns a deep copy suitable for A/B comparison or editing.
    public func duplicate(newName: String? = nil) -> EQProfile {
        var copy = self
        copy.id = UUID()
        copy.isFactory = false
        copy.name = newName ?? "\(name) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }
}
