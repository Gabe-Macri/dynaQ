import Foundation

/// Real-time audio metering telemetry.
public struct AudioMeter: Codable, Sendable {
    public var peakLeft: Float       // -80.0 to 0.0 dBFS
    public var peakRight: Float      // -80.0 to 0.0 dBFS
    public var rmsLeft: Float        // -80.0 to 0.0 dBFS
    public var rmsRight: Float       // -80.0 to 0.0 dBFS
    public var lufsMomentary: Float  // EBU R128 / ITU-R BS.1770 LUFS
    public var lufsIntegrated: Float // Integrated LUFS
    public var isClippingLeft: Bool
    public var isClippingRight: Bool

    public init(
        peakLeft: Float = -80.0,
        peakRight: Float = -80.0,
        rmsLeft: Float = -80.0,
        rmsRight: Float = -80.0,
        lufsMomentary: Float = -80.0,
        lufsIntegrated: Float = -80.0,
        isClippingLeft: Bool = false,
        isClippingRight: Bool = false
    ) {
        self.peakLeft = peakLeft
        self.peakRight = peakRight
        self.rmsLeft = rmsLeft
        self.rmsRight = rmsRight
        self.lufsMomentary = lufsMomentary
        self.lufsIntegrated = lufsIntegrated
        self.isClippingLeft = isClippingLeft
        self.isClippingRight = isClippingRight
    }

    public static let silent = AudioMeter()
}
