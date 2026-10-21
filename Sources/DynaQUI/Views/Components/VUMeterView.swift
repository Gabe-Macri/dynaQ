import SwiftUI
import DynaQCore

/// Stereo VU / Peak / RMS Meter with clip indicator.
public struct VUMeterView: View {
    public let meter: AudioMeter
    public let onResetClip: () -> Void

    public init(meter: AudioMeter, onResetClip: @escaping () -> Void = {}) {
        self.meter = meter
        self.onResetClip = onResetClip
    }

    public var body: some View {
        VStack(spacing: 4) {
            // Clip LEDs
            HStack(spacing: 4) {
                ClipLED(isClipping: meter.isClippingLeft)
                ClipLED(isClipping: meter.isClippingRight)
            }
            .onTapGesture {
                onResetClip()
            }

            // Stereo Bars
            HStack(spacing: 4) {
                MeterBar(peakDB: meter.peakLeft, rmsDB: meter.rmsLeft)
                MeterBar(peakDB: meter.peakRight, rmsDB: meter.rmsRight)
            }
            .frame(width: 24, height: 110)

            // LUFS readout
            Text(String(format: "%.1f", meter.lufsMomentary))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textSecondary)
            Text("LUFS")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(DynaQTheme.textMuted)
        }
        .padding(6)
        .background(DynaQTheme.surface)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

private struct ClipLED: View {
    let isClipping: Bool

    var body: some View {
        Circle()
            .fill(isClipping ? DynaQTheme.red : DynaQTheme.surfaceElevated)
            .frame(width: 8, height: 8)
            .shadow(color: isClipping ? DynaQTheme.red : .clear, radius: 4)
    }
}

private struct MeterBar: View {
    let peakDB: Float
    let rmsDB: Float

    private var peakProgress: CGFloat {
        // Map -60dB ... 0dB to 0 ... 1
        return CGFloat(min(max((peakDB + 60.0) / 60.0, 0.0), 1.0))
    }

    private var rmsProgress: CGFloat {
        return CGFloat(min(max((rmsDB + 60.0) / 60.0, 0.0), 1.0))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background Track
                Rectangle()
                    .fill(DynaQTheme.surfaceElevated)

                // RMS Level (Solid Gradient)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                DynaQTheme.green,
                                DynaQTheme.amber,
                                DynaQTheme.red
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geo.size.height * rmsProgress)
                    .opacity(0.85)

                // Peak Indicator Line
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 2)
                    .offset(y: -geo.size.height * peakProgress)
            }
            .cornerRadius(2)
        }
    }
}

