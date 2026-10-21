import Foundation

/// Represents a single equalizer band with static and dynamic capabilities.
public struct EQBand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var index: Int
    public var frequency: Float     // 20.0 to 20_000.0 Hz
    public var gain: Float          // -24.0 to +24.0 dB
    public var q: Float             // 0.1 to 18.0 (resonance / quality factor)
    public var filterType: FilterType
    public var isEnabled: Bool
    public var isSolo: Bool

    // MARK: - Dynamic EQ Parameters
    public var isDynamic: Bool
    public var dynamicThreshold: Float    // dBFS threshold (-60.0 to 0.0)
    public var dynamicRange: Float        // Maximum dynamic gain change in dB (-18.0 to +18.0)
    public var dynamicRatio: Float        // Compression/Expansion ratio (1.0 to 10.0)
    public var attackMs: Float            // Envelope attack time in ms
    public var releaseMs: Float           // Envelope release time in ms

    public init(
        id: UUID = UUID(),
        index: Int,
        frequency: Float,
        gain: Float = 0.0,
        q: Float = 1.414,
        filterType: FilterType = .bell,
        isEnabled: Bool = true,
        isSolo: Bool = false,
        isDynamic: Bool = false,
        dynamicThreshold: Float = -18.0,
        dynamicRange: Float = -6.0,
        dynamicRatio: Float = 2.0,
        attackMs: Float = 10.0,
        releaseMs: Float = 100.0
    ) {
        self.id = id
        self.index = index
        self.frequency = min(max(frequency, 20.0), 20_000.0)
        self.gain = min(max(gain, -24.0), 24.0)
        self.q = min(max(q, 0.1), 18.0)
        self.filterType = filterType
        self.isEnabled = isEnabled
        self.isSolo = isSolo
        self.isDynamic = isDynamic
        self.dynamicThreshold = dynamicThreshold
        self.dynamicRange = dynamicRange
        self.dynamicRatio = dynamicRatio
        self.attackMs = attackMs
        self.releaseMs = releaseMs
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
