import Foundation

/// Filter shapes supported by the dynaQ parametric equalizer.
public enum FilterType: String, Codable, CaseIterable, Sendable, Identifiable {
    case bell = "Bell / Peaking"
    case lowShelf = "Low Shelf"
    case highShelf = "High Shelf"
    case lowPass = "Low Pass (High Cut)"
    case highPass = "High Pass (Low Cut)"
    case notch = "Notch"
    case bandPass = "Band Pass"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .bell: return "Bell"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        case .notch: return "Notch"
        case .bandPass: return "Band Pass"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .bell: return "waveform.path.badge.plus"
        case .lowShelf: return "arrow.down.right.and.arrow.up.left"
        case .highShelf: return "arrow.up.right.and.arrow.down.left"
        case .lowPass: return "chart.line.downtrend.xyaxis"
        case .highPass: return "chart.line.uptrend.xyaxis"
        case .notch: return "arrow.down.to.line"
        case .bandPass: return "waveform"
        }
    }

    /// Whether this filter allows gain adjustment (cuts/passes typically don't take boost/cut gain, only Q).
    public var supportsGain: Bool {
        switch self {
        case .bell, .lowShelf, .highShelf:
            return true
        case .lowPass, .highPass, .notch, .bandPass:
            return false
        }
    }
}
