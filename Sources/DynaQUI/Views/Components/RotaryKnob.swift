import SwiftUI

/// Minimal Terminal Parameter Controller.
/// Brutalist studio design: monospace typography, numeric precision readout, center-zero or linear indicator bar,
/// drag scrubbing with fine adjustments, and double-click reset. Zero bubbles or AI neon slop.
public struct RotaryKnob: View {
    public let title: String
    @Binding public var value: Float
    public let range: ClosedRange<Float>
    public let defaultValue: Float
    public let unit: String
    public let tintColor: Color

    @State private var dragStartValue: Float? = nil
    @State private var isHovered: Bool = false

    public init(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultValue: Float = 0.0,
        unit: String = "dB",
        tintColor: Color = DynaQTheme.terminalCyan
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.unit = unit
        self.tintColor = tintColor
    }

    private var normalizedProgress: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0.5 }
        return Double(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
    }

    private var isBipolar: Bool {
        return range.lowerBound < 0 && range.upperBound > 0
    }

    public var body: some View {
        VStack(spacing: 3) {
            // Parameter Title
            Text("[ \(title.uppercased()) ]")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
                .lineLimit(1)

            // Parameter Value Box
            VStack(spacing: 4) {
                // Numeric Readout
                Text(formattedValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isHovered ? tintColor : DynaQTheme.textPrimary)
                    .lineLimit(1)
                    .frame(height: 14)

                // Precision Terminal Indicator Bar
                GeometryReader { geo in
                    ZStack(alignment: isBipolar ? .center : .leading) {
                        // Track background
                        Rectangle()
                            .fill(DynaQTheme.surface)
                            .frame(height: 3)

                        // Center tick for bipolar controls
                        if isBipolar {
                            Rectangle()
                                .fill(DynaQTheme.textMuted.opacity(0.6))
                                .frame(width: 1, height: 5)
                        }

                        // Active Bar
                        if isBipolar {
                            let halfW = geo.size.width / 2.0
                            let centerVal = (range.lowerBound + range.upperBound) / 2.0
                            let span = Double(range.upperBound - centerVal)
                            let offset = Double(value - centerVal) / span
                            let barW = CGFloat(abs(offset)) * halfW

                            Rectangle()
                                .fill(tintColor)
                                .frame(width: max(barW, 2), height: 3)
                                .offset(x: offset < 0 ? -barW / 2.0 : barW / 2.0)
                        } else {
                            Rectangle()
                                .fill(tintColor)
                                .frame(width: max(geo.size.width * CGFloat(normalizedProgress), 2), height: 3)
                        }
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(DynaQTheme.surfaceElevated)
            .overlay(
                Rectangle()
                    .stroke(isHovered ? tintColor.opacity(0.8) : DynaQTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .frame(width: 68)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if dragStartValue == nil {
                        dragStartValue = value
                    }
                    let start = dragStartValue ?? defaultValue
                    let span = range.upperBound - range.lowerBound

                    // Drag up or right = increase, drag down or left = decrease
                    let delta = Float(-gesture.translation.height + gesture.translation.width * 0.5) * (span / 220.0)
                    let newValue = min(max(start + delta, range.lowerBound), range.upperBound)

                    // Step frequency logarithmically, gain in 0.5 steps
                    if unit == "Hz" {
                        value = round(newValue)
                    } else if unit == "dB" {
                        value = (newValue * 2.0).rounded() / 2.0
                    } else {
                        value = (newValue * 100.0).rounded() / 100.0
                    }
                }
                .onEnded { _ in
                    dragStartValue = nil
                }
        )
        .onTapGesture(count: 2) {
            value = defaultValue
        }
    }

    private var formattedValue: String {
        if unit == "Hz" {
            if value >= 1000 {
                return String(format: "%.1fkHz", value / 1000.0)
            } else {
                return String(format: "%.0fHz", value)
            }
        } else if unit == "dB" {
            let sign = value > 0 ? "+" : ""
            return String(format: "%@%.1fdB", sign, value)
        } else if unit == ":1" {
            return String(format: "%.1f:1", value)
        } else if unit.isEmpty {
            return String(format: "Q %.2f", value)
        } else {
            return String(format: "%.1f %@", value, unit)
        }
    }
}
