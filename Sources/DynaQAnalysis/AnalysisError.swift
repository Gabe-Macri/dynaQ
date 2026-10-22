import Foundation

/// Comprehensive, actionable error descriptions for audio analysis and metering.
public enum AnalysisError: LocalizedError, Equatable, Sendable {
    case unsupportedFFTSize(Int)
    case invalidBinCount(Int)
    case invalidSampleRate(Float)
    case nullBuffer
    case dftSetupFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedFFTSize(let s):
            return "Analysis Error: FFT size \(s) must be a power of two between 64 and 8192."
        case .invalidBinCount(let b):
            return "Analysis Error: Frequency bin count \(b) is out of range [16, 512]."
        case .invalidSampleRate(let sr):
            return "Analysis Error: Sample rate \(Int(sr)) Hz is invalid for FFT computation."
        case .nullBuffer:
            return "Analysis Error: Audio analysis buffer is null or empty."
        case .dftSetupFailed:
            return "Analysis Error: Apple Accelerate vDSP DFT setup initialization failed."
        }
    }
}

