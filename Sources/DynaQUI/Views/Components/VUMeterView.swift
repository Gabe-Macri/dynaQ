import SwiftUI
import DynaQCore

/// Terminal Segmented Stereo VU / Peak / RMS Hardware Meter.
/// Brutalist aesthetic: discrete LED segments, sharp clip indicator, monospace dB scale, zero neon gradients.
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
            .frame(height: 100)

            // Stereo Segmented Columns
            VStack(spacing: 3) {
                // Top Clip Indicator Block
                Button(action: onResetClip) {
                    HStack(spacing: 3) {
                        Rectangle()
                            .fill(meter.isClippingLeft ? DynaQTheme.terminalRed : DynaQTheme.surfaceElevated)
                            .frame(width: 8, height: 6)
                        Rectangle()
                            .fill(meter.isClippingRight ? DynaQTheme.terminalRed : DynaQTheme.surfaceElevated)
                            .frame(width: 8, height: 6)
                    }
                    .overlay(
                        Rectangle().stroke(meter.isClippingLeft || meter.isClippingRight ? DynaQTheme.terminalRed : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Stereo Bars
                HStack(spacing: 3) {
                    SegmentedMeterBar(peakDB: meter.peakLeft, rmsDB: meter.rmsLeft)
                    SegmentedMeterBar(peakDB: meter.peakRight, rmsDB: meter.rmsRight)
                }
                .frame(width: 19, height: 100)

                // Channel Labels
                HStack(spacing: 7) {
                    Text("L").font(.system(size: 7, weight: .bold, design: .monospaced))
                    Text("R").font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundColor(DynaQTheme.textMuted)
            }

            // Numeric Telemetry Readouts
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    let maxPeak = max(meter.peakLeft, meter.peakRight)
                    Text(String(format: "%@%.1f", maxPeak > 0 ? "+" : "", maxPeak))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(maxPeak > -0.5 ? DynaQTheme.terminalRed : (maxPeak > -6 ? DynaQTheme.phosphorAmber : DynaQTheme.phosphorGreen))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("RMS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    let maxRMS = max(meter.rmsLeft, meter.rmsRight)
                    Text(String(format: "%.1f", maxRMS))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("LUFS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    Text(String(format: "%.1f", meter.lufsMomentary))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.terminalCyan)
                }
            }
            .frame(width: 38, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

/// Discrete hardware LED segmented meter bar (24 segments).
private struct SegmentedMeterBar: View {
    let peakDB: Float
    let rmsDB: Float

    private let segmentCount = 24

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 1) {
                ForEach((0..<segmentCount).reversed(), id: \.self) { seg in
                    // Map segment index to dB: 0 = -60dB, 23 = 0dB
                    let segNorm = Float(seg) / Float(segmentCount - 1)
                    let segDB = -60.0 + segNorm * 60.0

                    let isRMSActive = rmsDB >= segDB
                    let isPeakActive = abs(peakDB - segDB) < 2.5 || (peakDB >= segDB && peakDB < segDB + 2.5)

                    Rectangle()
                        .fill(segmentColor(for: segDB, isActive: isRMSActive, isPeak: isPeakActive))
                        .frame(height: 3)
                }
            }
        }
    }

    private func segmentColor(for db: Float, isActive: Bool, isPeak: Bool) -> Color {
        if isPeak {
            return Color.white
        }
        guard isActive else {
            return DynaQTheme.surfaceElevated.opacity(0.4)
        }
        if db >= -2.0 {
            return DynaQTheme.terminalRed
        } else if db >= -12.0 {
            return DynaQTheme.phosphorAmber
        } else {
            return DynaQTheme.phosphorGreen
        }
    }
}
