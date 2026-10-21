import SwiftUI

/// Pro Audio Rotary Knob with logarithmic or linear response and fine drag control.
public struct RotaryKnob: View {
    public let title: String
    @Binding public var value: Float
    public let range: ClosedRange<Float>
    public let defaultValue: Float
    public let unit: String
    public let tintColor: Color

    @State private var dragStartValue: Float? = nil

    public init(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultValue: Float = 0.0,
        unit: String = "dB",
        tintColor: Color = DynaQTheme.cyan
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

    public var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textSecondary)

            ZStack {
                // Background Track
                Circle()
                    .stroke(DynaQTheme.surfaceElevated, lineWidth: 4)
                    .frame(width: 44, height: 44)

                // Active Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(normalizedProgress * 0.75))
                    .stroke(
                        tintColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .frame(width: 44, height: 44)

                // Indicator needle
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 10)
                    .offset(y: -12)
                    .rotationEffect(.degrees(135 + normalizedProgress * 270))

                // Center Knob Cap
                Circle()
                    .fill(DynaQTheme.surface)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                        }
                        let start = dragStartValue ?? defaultValue
                        let span = range.upperBound - range.lowerBound
                        // Drag up = increase, Drag down = decrease
                        let delta = Float(-gesture.translation.height) * (span / 200.0)
                        value = min(max(start + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                    }
            )
            .onTapGesture(count: 2) {
                value = defaultValue
            }

            Text(formattedValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DynaQTheme.textPrimary)
        }
        .frame(width: 60)
    }

    private var formattedValue: String {
        let sign = value > 0 && unit == "dB" ? "+" : ""
        return String(format: "%@%.1f %@", sign, value, unit)
    }
}
