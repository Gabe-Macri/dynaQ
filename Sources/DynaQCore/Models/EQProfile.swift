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
    public var isLiveMode: Bool         // Zero-latency mode (bypasses lookahead delay line for DAW tracking)
    public var phaseInvert: Bool        // 180° polarity flip
    public var monitorMode: MonitorMode
    public var stereoWidth: Float       // Stereo width (0.0 = Mono, 1.0 = Normal, 2.0 = 200% Wide)
    public var monoBassCutoff: Float    // Mono Sub-Bass cutoff in Hz (0.0 = Off, 20.0 to 300.0 Hz)
    public var analogDrive: Float       // Analog warmth/tape soft-saturation (0.0 = Clean, 1.0 = Max Saturation)
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
        isLiveMode: Bool = false,
        phaseInvert: Bool = false,
        monitorMode: MonitorMode = .stereo,
        stereoWidth: Float = 1.0,
        monoBassCutoff: Float = 0.0,
        analogDrive: Float = 0.0,
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
        self.isLiveMode = isLiveMode
        self.phaseInvert = phaseInvert
        self.monitorMode = monitorMode
        self.stereoWidth = stereoWidth
        self.monoBassCutoff = monoBassCutoff
        self.analogDrive = analogDrive
        self.isFactory = isFactory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Custom"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        bands = try container.decode([EQBand].self, forKey: .bands)
        preampGain = try container.decodeIfPresent(Float.self, forKey: .preampGain) ?? 0.0
        masterGain = try container.decodeIfPresent(Float.self, forKey: .masterGain) ?? 0.0
        isBypassed = try container.decodeIfPresent(Bool.self, forKey: .isBypassed) ?? false
        isLimiterEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLimiterEnabled) ?? true
        limiterCeiling = try container.decodeIfPresent(Float.self, forKey: .limiterCeiling) ?? -0.2
        isLiveMode = try container.decodeIfPresent(Bool.self, forKey: .isLiveMode) ?? false
        phaseInvert = try container.decodeIfPresent(Bool.self, forKey: .phaseInvert) ?? false
        monitorMode = try container.decodeIfPresent(MonitorMode.self, forKey: .monitorMode) ?? .stereo
        stereoWidth = try container.decodeIfPresent(Float.self, forKey: .stereoWidth) ?? 1.0
        monoBassCutoff = try container.decodeIfPresent(Float.self, forKey: .monoBassCutoff) ?? 0.0
        analogDrive = try container.decodeIfPresent(Float.self, forKey: .analogDrive) ?? 0.0
        isFactory = try container.decodeIfPresent(Bool.self, forKey: .isFactory) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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

    /// Sanitizes all profile parameters, clamping out-of-range gains, frequencies, and Q factors,
    /// and safely recovering from NaN or Infinite floating-point values.
    public func sanitized() -> EQProfile {
        var copy = self
        copy.preampGain = preampGain.isFinite ? max(-36.0, min(36.0, preampGain)) : 0.0
        copy.masterGain = masterGain.isFinite ? max(-36.0, min(36.0, masterGain)) : 0.0
        copy.limiterCeiling = limiterCeiling.isFinite ? max(-24.0, min(0.0, limiterCeiling)) : -0.2
        copy.stereoWidth = stereoWidth.isFinite ? max(0.0, min(2.0, stereoWidth)) : 1.0
        copy.monoBassCutoff = monoBassCutoff.isFinite ? max(0.0, min(300.0, monoBassCutoff)) : 0.0
        copy.analogDrive = analogDrive.isFinite ? max(0.0, min(1.0, analogDrive)) : 0.0
        copy.bands = bands.map { band in
            var b = band
            b.frequency = (band.frequency.isFinite && band.frequency >= 10.0 && band.frequency <= 24000.0)
                ? band.frequency
                : 1000.0
            b.gain = band.gain.isFinite ? max(-36.0, min(36.0, band.gain)) : 0.0
            b.q = (band.q.isFinite && band.q >= 0.05 && band.q <= 30.0) ? band.q : 1.0
            b.dynamicThreshold = band.dynamicThreshold.isFinite ? max(-96.0, min(0.0, band.dynamicThreshold)) : -24.0
            b.dynamicRange = band.dynamicRange.isFinite ? max(-36.0, min(36.0, band.dynamicRange)) : 0.0
            b.dynamicRatio = (band.dynamicRatio.isFinite && band.dynamicRatio >= 1.0) ? min(20.0, band.dynamicRatio) : 2.0
            b.attackMs = (band.attackMs.isFinite && band.attackMs >= 0.1) ? min(1000.0, band.attackMs) : 10.0
            b.releaseMs = (band.releaseMs.isFinite && band.releaseMs >= 1.0) ? min(5000.0, band.releaseMs) : 100.0
            b.fmRate = (band.fmRate.isFinite && band.fmRate >= 0.05) ? min(50.0, band.fmRate) : 1.0
            b.fmDepth = (band.fmDepth.isFinite && band.fmDepth >= 0.0) ? min(4.0, band.fmDepth) : 1.0
            return b
        }
        return copy
    }
}
