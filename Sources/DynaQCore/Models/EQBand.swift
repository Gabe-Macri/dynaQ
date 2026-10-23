import Foundation

/// Stereo channel routing per equalizer band (Pro M/S processing).
public enum BandRouting: String, Codable, CaseIterable, Sendable, Identifiable {
    case stereo = "Stereo"
    case mid = "Mid (M)"
    case side = "Side (S)"
    case left = "Left (L)"
    case right = "Right (R)"

    public var id: String { rawValue }

    public var shortBadge: String {
        switch self {
        case .stereo: return "ST"
        case .mid: return "M"
        case .side: return "S"
        case .left: return "L"
        case .right: return "R"
        }
    }
}

/// Mode of Frequency Modulation applied to the equalizer band.
public enum FMMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case envelope = "Envelope Follower"
    case lfo = "LFO Sweep"

    public var id: String { rawValue }

    public var shortBadge: String {
        switch self {
        case .envelope: return "ENV"
        case .lfo: return "LFO"
        }
    }
}

/// Represents a single equalizer band with static, dynamic gain, and frequency modulation capabilities.
public struct EQBand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var index: Int
    public var frequency: Float     // 20.0 to 20_000.0 Hz
    public var gain: Float          // -24.0 to +24.0 dB
    public var q: Float             // 0.1 to 18.0 (resonance / quality factor)
    public var filterType: FilterType
    public var routing: BandRouting
    public var isEnabled: Bool
    public var isSolo: Bool

    // MARK: - Dynamic EQ Parameters
    public var isDynamic: Bool
    public var dynamicThreshold: Float    // dBFS threshold (-60.0 to 0.0)
    public var dynamicRange: Float        // Maximum dynamic gain change in dB (-18.0 to +18.0)
    public var dynamicRatio: Float        // Compression/Expansion ratio (1.0 to 10.0)
    public var attackMs: Float            // Envelope attack time in ms
    public var releaseMs: Float           // Envelope release time in ms
    public var useSidechainFilter: Bool   // Frequency-selective sidechain bandpass detection

    // MARK: - Frequency Modulation (FM EQ) Parameters
    public var isFMEnabled: Bool          // True when dynamic frequency modulation is active
    public var fmMode: FMMode             // .envelope for transient-tracking FM; .lfo for periodic sweep
    public var fmDepth: Float             // Modulation depth in octaves (-3.0 to +3.0)
    public var fmRate: Float              // LFO frequency in Hz (0.1 to 20.0 Hz) or sensitivity

    public init(
        id: UUID = UUID(),
        index: Int,
        frequency: Float,
        gain: Float = 0.0,
        q: Float = 1.414,
        filterType: FilterType = .bell,
        routing: BandRouting = .stereo,
        isEnabled: Bool = true,
        isSolo: Bool = false,
        isDynamic: Bool = false,
        dynamicThreshold: Float = -18.0,
        dynamicRange: Float = -6.0,
        dynamicRatio: Float = 2.0,
        attackMs: Float = 10.0,
        releaseMs: Float = 100.0,
        useSidechainFilter: Bool = false,
        isFMEnabled: Bool = false,
        fmMode: FMMode = .envelope,
        fmDepth: Float = 0.5,
        fmRate: Float = 1.0
    ) {
        self.id = id
        self.index = index
        self.frequency = min(max(frequency, 20.0), 20_000.0)
        self.gain = min(max(gain, -24.0), 24.0)
        self.q = min(max(q, 0.1), 18.0)
        self.filterType = filterType
        self.routing = routing
        self.isEnabled = isEnabled
        self.isSolo = isSolo
        self.isDynamic = isDynamic
        self.dynamicThreshold = dynamicThreshold
        self.dynamicRange = dynamicRange
        self.dynamicRatio = dynamicRatio
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.useSidechainFilter = useSidechainFilter
        self.isFMEnabled = isFMEnabled
        self.fmMode = fmMode
        self.fmDepth = min(max(fmDepth, -3.0), 3.0)
        self.fmRate = min(max(fmRate, 0.1), 20.0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, index, frequency, gain, q, filterType, routing, isEnabled, isSolo
        case isDynamic, dynamicThreshold, dynamicRange, dynamicRatio, attackMs, releaseMs, useSidechainFilter
        case isFMEnabled, fmMode, fmDepth, fmRate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.index = try c.decode(Int.self, forKey: .index)
        self.frequency = try c.decode(Float.self, forKey: .frequency)
        self.gain = try c.decodeIfPresent(Float.self, forKey: .gain) ?? 0.0
        self.q = try c.decodeIfPresent(Float.self, forKey: .q) ?? 1.414
        self.filterType = try c.decodeIfPresent(FilterType.self, forKey: .filterType) ?? .bell
        self.routing = try c.decodeIfPresent(BandRouting.self, forKey: .routing) ?? .stereo
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isSolo = try c.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        self.isDynamic = try c.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? false
        self.dynamicThreshold = try c.decodeIfPresent(Float.self, forKey: .dynamicThreshold) ?? -18.0
        self.dynamicRange = try c.decodeIfPresent(Float.self, forKey: .dynamicRange) ?? -6.0
        self.dynamicRatio = try c.decodeIfPresent(Float.self, forKey: .dynamicRatio) ?? 2.0
        self.attackMs = try c.decodeIfPresent(Float.self, forKey: .attackMs) ?? 10.0
        self.releaseMs = try c.decodeIfPresent(Float.self, forKey: .releaseMs) ?? 100.0
        self.useSidechainFilter = try c.decodeIfPresent(Bool.self, forKey: .useSidechainFilter) ?? false
        self.isFMEnabled = try c.decodeIfPresent(Bool.self, forKey: .isFMEnabled) ?? false
        self.fmMode = try c.decodeIfPresent(FMMode.self, forKey: .fmMode) ?? .envelope
        self.fmDepth = try c.decodeIfPresent(Float.self, forKey: .fmDepth) ?? 0.5
        self.fmRate = try c.decodeIfPresent(Float.self, forKey: .fmRate) ?? 1.0
    }

    // MARK: - Formatting Helpers

    public var formattedFrequency: String {
        if frequency >= 1000.0 {
            return String(format: "%.1f kHz", frequency / 1000.0)
        } else {
            return String(format: "%.0f Hz", frequency)
        }
    }

    public var formattedGain: String {
        if abs(gain) < 0.05 {
            return "0.0 dB"
        }
        let sign = gain > 0 ? "+" : ""
        return String(format: "%@%.1f dB", sign, gain)
    }

    public var formattedQ: String {
        return String(format: "Q %.2f", q)
    }
}
