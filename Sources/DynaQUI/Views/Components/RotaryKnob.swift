import SwiftUI

/// Precision Brutalist Terminal Parameter Controller.
/// Monospace typography, logarithmic frequency dragging, precision numeric readout,
/// inline text entry on click, double-click reset, and sharp 1px borders. Zero tacky glow or bubbles.
public struct RotaryKnob: View {
    public let title: String
    @Binding public var value: Float
    public let range: ClosedRange<Float>
    public let defaultValue: Float
    public let unit: String
    public let tintColor: Color

    @State private var dragStartValue: Float? = nil
    @State private var isHovered: Bool = false
    @State private var isEditingText: Bool = false
    @State private var textInput: String = ""

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
        if unit == "Hz" {
            let logMin = log10(Double(max(range.lowerBound, 20.0)))
            let logMax = log10(Double(range.upperBound))
            let logVal = log10(Double(min(max(value, range.lowerBound), range.upperBound)))
            return (logVal - logMin) / (logMax - logMin)
        } else {
            let span = Double(range.upperBound - range.lowerBound)
            guard span > 0 else { return 0.5 }
            return Double(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
        }
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
                // Numeric Readout or Inline Text Input
                if isEditingText {
                    TextField("", text: $textInput, onCommit: commitTextInput)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(tintColor)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(height: 14)
                } else {
                    Text(formattedValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isHovered ? tintColor : DynaQTheme.textPrimary)
                        .lineLimit(1)
                        .frame(height: 14)
                        .onTapGesture {
                            textInput = String(format: "%.1f", value)
                            isEditingText = true
                        }
                }

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
        .frame(width: 80)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if isEditingText { isEditingText = false }
                    if dragStartValue == nil {
                        dragStartValue = value
                    }
                    let start = dragStartValue ?? defaultValue

                    if unit == "Hz" {
                        // Logarithmic frequency scrubbing: uniform sensitivity across all octaves
                        let logMin = log10(max(range.lowerBound, 20.0))
                        let logMax = log10(range.upperBound)
                        let logStart = log10(max(start, 20.0))
                        let delta = Float(-gesture.translation.height + gesture.translation.width * 0.4) / 220.0
                        let targetLog = logStart + delta * (logMax - logMin)
                        let targetFreq = pow(10.0, targetLog)
                        value = min(max(round(targetFreq), range.lowerBound), range.upperBound)
                    } else if unit == "dB" {
                        let span = range.upperBound - range.lowerBound
                        let delta = Float(-gesture.translation.height + gesture.translation.width * 0.4) * (span / 200.0)
                        let raw = start + delta
                        let stepped = (raw * 2.0).rounded() / 2.0
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    } else {
                        let span = range.upperBound - range.lowerBound
                        let delta = Float(-gesture.translation.height + gesture.translation.width * 0.4) * (span / 200.0)
                        let raw = start + delta
                        value = min(max((raw * 100.0).rounded() / 100.0, range.lowerBound), range.upperBound)
                    }
                }
                .onEnded { _ in
                    dragStartValue = nil
                }
        )
        .onTapGesture(count: 2) {
            value = defaultValue
            isEditingText = false
        }
    }

    private func commitTextInput() {
        isEditingText = false
        if let parsed = Float(textInput) {
            value = min(max(parsed, range.lowerBound), range.upperBound)
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
        } else if unit == "Oct" {
            let sign = value > 0 ? "+" : ""
            return String(format: "%@%.1fOct", sign, value)
        } else {
            return String(format: "%.1f %@", value, unit)
        }
    }
}
