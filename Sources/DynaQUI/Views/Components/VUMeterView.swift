import SwiftUI
import DynaQCore

/// Terminal Segmented Stereo VU / Peak / RMS Hardware Meter.
/// Brutalist studio console: discrete LED segments drawn with zero-allocation Canvas,
/// clip indicators, and monospace dB telemetry.
public struct VUMeterView: View {
    public let meter: AudioMeter
    public let onResetClip: () -> Void

    public init(meter: AudioMeter, onResetClip: @escaping () -> Void = {}) {
        self.meter = meter
        self.onResetClip = onResetClip
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Decibel Scale Markers
            VStack(alignment: .trailing, spacing: 0) {
                Text("0").font(.system(size: 7, weight: .bold, design: .monospaced))
                Spacer()
                Text("-6").font(.system(size: 7, weight: .bold, design: .monospaced))
                Spacer()
                Text("-12").font(.system(size: 7, weight: .bold, design: .monospaced))
                Spacer()
                Text("-24").font(.system(size: 7, weight: .bold, design: .monospaced))
                Spacer()
                Text("-48").font(.system(size: 7, weight: .bold, design: .monospaced))
            }
            .foregroundColor(DynaQTheme.textMuted)
            .frame(height: 72)

            // Stereo Segmented Columns
            VStack(spacing: 2) {
                // Top Clip Indicator Block
                Button(action: onResetClip) {
                    HStack(spacing: 3) {
                        Rectangle()
                            .fill(meter.isClippingLeft ? DynaQTheme.terminalRed : DynaQTheme.surfaceElevated)
                            .frame(width: 8, height: 5)
                        Rectangle()
                            .fill(meter.isClippingRight ? DynaQTheme.terminalRed : DynaQTheme.surfaceElevated)
                            .frame(width: 8, height: 5)
                    }
                    .overlay(
                        Rectangle().stroke(meter.isClippingLeft || meter.isClippingRight ? DynaQTheme.terminalRed : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // High Performance Zero-Allocation Canvas Meters
                HStack(spacing: 3) {
                    SegmentedMeterCanvas(peakDB: meter.peakLeft, rmsDB: meter.rmsLeft)
                    SegmentedMeterCanvas(peakDB: meter.peakRight, rmsDB: meter.rmsRight)
                }
                .frame(width: 19, height: 72)

                // Channel Labels
                HStack(spacing: 7) {
                    Text("L").font(.system(size: 7, weight: .bold, design: .monospaced))
                    Text("R").font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundColor(DynaQTheme.textMuted)
            }

            // Numeric Telemetry Readouts
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PEAK")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    let maxPeak = max(meter.peakLeft, meter.peakRight)
                    Text(String(format: "%@%.1f", maxPeak > 0 ? "+" : "", maxPeak))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(maxPeak > -0.5 ? DynaQTheme.terminalRed : (maxPeak > -6 ? DynaQTheme.phosphorAmber : DynaQTheme.phosphorGreen))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("RMS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    let maxRMS = max(meter.rmsLeft, meter.rmsRight)
                    Text(String(format: "%.1f", maxRMS))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("LUFS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    Text(String(format: "%.1f", meter.lufsMomentary))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.terminalCyan)
                }
            }
            .frame(width: 38, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

/// Zero-allocation Canvas drawing 24 hardware LED meter segments.
private struct SegmentedMeterCanvas: View {
    let peakDB: Float
    let rmsDB: Float

    private let segmentCount = 20

    var body: some View {
        Canvas { context, size in
            let segHeight: CGFloat = max((size.height - CGFloat(segmentCount - 1)) / CGFloat(segmentCount), 1.5)
            let spacing: CGFloat = 1.0

            for seg in 0..<segmentCount {
                let segNorm = Float(seg) / Float(segmentCount - 1)
                let segDB = -48.0 + segNorm * 48.0

                let isRMSActive = rmsDB >= segDB
                let isPeakActive = abs(peakDB - segDB) < 2.5 || (peakDB >= segDB && peakDB < segDB + 2.5)

                let y = CGFloat(segmentCount - 1 - seg) * (segHeight + spacing)
                let rect = CGRect(x: 0, y: y, width: size.width, height: segHeight)

                let color: Color
                if isPeakActive {
                    color = Color.white
                } else if isRMSActive {
                    if segDB >= -2.0 {
                        color = DynaQTheme.terminalRed
                    } else if segDB >= -8.0 {
                        color = DynaQTheme.phosphorAmber
                    } else {
                        color = DynaQTheme.phosphorGreen
                    }
                } else {
                    color = DynaQTheme.surfaceElevated.opacity(0.35)
                }

                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}
