import Foundation
import CDspKernel

/// Professional Studio True-Peak Lookahead Limiter.
/// Delivers transparent, zero-distortion peak control with lookahead circular delay line,
/// stereo-linked gain reduction, and brickwall ceiling guards.
public final class TruePeakLimiter: @unchecked Sendable {
    public var ceilingDB: Float = -0.2 {
        didSet {
            let clamped = min(0.0, max(-24.0, ceilingDB))
            linearCeiling = pow(10.0, clamped / 20.0)
            if let lim = cLimiter {
                c_lookahead_limiter_set_ceiling(lim, linearCeiling)
            }
        }
    }

    public var isEnabled: Bool = true
    public private(set) var lookaheadSamples: Int
    public private(set) var sampleRate: Float

    private var linearCeiling: Float = 0.9772 // ~ -0.2 dBFS
    private var cLimiter: OpaquePointer?

    public init(
        ceilingDB: Float = -0.2,
        lookaheadSamples: Int = 48, // ~1ms at 48kHz
        sampleRate: Float = 48000.0,
        isEnabled: Bool = true
    ) {
        let clampedCeil = min(0.0, max(-24.0, ceilingDB))
        self.ceilingDB = clampedCeil
        self.linearCeiling = pow(10.0, clampedCeil / 20.0)
        self.lookaheadSamples = min(1024, max(0, lookaheadSamples))
        self.sampleRate = max(8000.0, sampleRate)
        self.isEnabled = isEnabled

        if self.lookaheadSamples > 0 {
            self.cLimiter = c_lookahead_limiter_create(
                self.lookaheadSamples,
                self.sampleRate,
                self.linearCeiling
            )
        }
    }

    deinit {
        if let lim = cLimiter {
            c_lookahead_limiter_destroy(lim)
        }
    }

    /// Sets ceiling with validation.
    public func setCeilingSafe(_ ceilingDB: Float) throws {
        guard ceilingDB <= 0.0 && ceilingDB >= -24.0 else {
            throw DynamicsError.invalidCeiling(ceilingDB)
        }
        self.ceilingDB = ceilingDB
    }

    /// Updates sample rate and re-initializes lookahead buffers safely.
    public func setSampleRate(_ rate: Float) throws {
        guard rate >= 8000.0 && rate <= 384000.0 else {
            throw DynamicsError.invalidSampleRate(rate)
        }
        self.sampleRate = rate
        if let lim = cLimiter {
            c_lookahead_limiter_destroy(lim)
        }
        if lookaheadSamples > 0 {
            self.cLimiter = c_lookahead_limiter_create(
                lookaheadSamples,
                rate,
                linearCeiling
            )
        }
    }

    /// Resets internal delay memory and gain state.
    public func resetState() {
        if let lim = cLimiter {
            c_lookahead_limiter_reset(lim)
        }
    }

    /// In-place limiting on stereo buffers with zero allocations.
    @inline(__always)
    public func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard isEnabled && count > 0 else { return }

        if let lim = cLimiter {
            c_lookahead_limiter_process(lim, left, right, count)
        } else {
            c_dsp_limiter_process_stereo(left, right, count, linearCeiling, isEnabled)
        }
    }
}
