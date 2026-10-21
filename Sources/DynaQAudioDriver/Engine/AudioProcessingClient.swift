import Foundation

/// Explicit client protocol for real-time audio manipulation.
/// The dedicated audio routing backend streams raw audio frames to the client processor,
/// ensuring all heavy DSP manipulations remain strictly decoupled on the client side.
public protocol AudioProcessingClient: AnyObject, Sendable {
    /// Invoked on the high-priority real-time audio thread to process audio frames in-place.
    /// - Parameters:
    ///   - left: Pointer to the left audio channel PCM samples.
    ///   - right: Pointer to the right audio channel PCM samples.
    ///   - count: Number of frames in this audio block.
    ///   - sampleRate: Current hardware output sample rate in Hz.
    func processAudioBlock(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        count: Int,
        sampleRate: Float
    )
}
