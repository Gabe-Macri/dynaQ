import Foundation

/// Comprehensive, actionable error descriptions for digital signal processing failures.
public enum DSPError: LocalizedError, Equatable, Sendable {
    case unstableFilterPoles(band: Int)
    case frequencyOutOfBounds(Float, min: Float, max: Float)
    case invalidQualityFactor(Float)
    case invalidGain(Float)
    case invalidSampleRate(Float)
    case channelCountMismatch(expected: Int, actual: Int)
    case pipelineNotConfigured

    public var errorDescription: String? {
        switch self {
        case .unstableFilterPoles(let b):
            return "DSP Error: Filter band \(b) produced unstable poles (|z| >= 1.0) and was safely bypassed to prevent runaway feedback."
        case .frequencyOutOfBounds(let f, let min, let max):
            return "DSP Error: Filter center frequency \(String(format: "%.1f", f)) Hz is out of safe range [\(Int(min)) Hz - \(Int(max)) Hz]."
        case .invalidQualityFactor(let q):
            return "DSP Error: Quality factor Q=\(String(format: "%.2f", q)) must be strictly greater than 0.01."
        case .invalidGain(let g):
            return "DSP Error: Filter gain \(String(format: "%.1f", g)) dB exceeds safe hardware limits (-36 dB to +36 dB)."
        case .invalidSampleRate(let sr):
            return "DSP Error: DSP sample rate \(Int(sr)) Hz is invalid. Minimum rate is 8000 Hz."
        case .channelCountMismatch(let exp, let act):
            return "DSP Error: Audio channel count mismatch (expected \(exp), got \(act))."
        case .pipelineNotConfigured:
            return "DSP Error: Audio processing pipeline has not been initialized."
        }
    }
}

