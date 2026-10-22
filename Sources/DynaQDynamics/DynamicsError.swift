import Foundation

/// Comprehensive, actionable error descriptions for audio dynamics operations.
public enum DynamicsError: LocalizedError, Equatable, Sendable {
    case invalidCeiling(Float)
    case invalidLookahead(Int)
    case invalidSampleRate(Float)
    case bufferAllocationFailed
    case thresholdOutOfBounds(Float)
    case ratioOutOfBounds(Float)

    public var errorDescription: String? {
        switch self {
        case .invalidCeiling(let c):
            return "Dynamics Error: Limiter ceiling \(String(format: "%.2f", c)) dBFS is out of valid range (-24.0 dBFS to 0.0 dBFS)."
        case .invalidLookahead(let l):
            return "Dynamics Error: Lookahead samples (\(l)) out of valid bounds (0 to 1024 samples)."
        case .invalidSampleRate(let sr):
            return "Dynamics Error: Sample rate \(Int(sr)) Hz is unsupported. Minimum supported rate is 8000 Hz."
        case .bufferAllocationFailed:
            return "Dynamics Error: Failed to allocate aligned circular delay buffer for true-peak limiter."
        case .thresholdOutOfBounds(let t):
            return "Dynamics Error: Dynamics threshold \(String(format: "%.1f", t)) dBFS must be within [-60.0, 0.0] dBFS."
        case .ratioOutOfBounds(let r):
            return "Dynamics Error: Compression ratio \(String(format: "%.1f", r)):1 must be between 1.0:1 and 20.0:1."
        }
    }
}

