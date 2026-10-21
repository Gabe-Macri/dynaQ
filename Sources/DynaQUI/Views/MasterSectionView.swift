import SwiftUI
import DynaQCore
import DynaQDSP

/// Master output section with gain staging, limiter, bypass, and metering.
public struct MasterSectionView: View {
    @Binding public var profile: EQProfile
    public let meter: AudioMeter
    public let onResetClip: () -> Void

    public init(
        profile: Binding<EQProfile>,
        meter: AudioMeter,
        onResetClip: @escaping () -> Void = {}
    ) {
        self._profile = profile
        self.meter = meter
        self.onResetClip = onResetClip
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Preamp Gain
            RotaryKnob(
                title: "Preamp",
                value: $profile.preampGain,
                range: -18...18,
                defaultValue: 0.0,
                unit: "dB",
                tintColor: DynaQTheme.blue
            )

            // Master Gain
            RotaryKnob(
                title: "Master",
                value: $profile.masterGain,
                range: -18...18,
                defaultValue: 0.0,
                unit: "dB",
                tintColor: DynaQTheme.cyan
            )

            Divider().background(DynaQTheme.surfaceBorder)

            // Limiter Control
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(profile.isLimiterEnabled ? DynaQTheme.green : DynaQTheme.textMuted)
                        .frame(width: 6, height: 6)
                    Text("LIMITER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(profile.isLimiterEnabled ? DynaQTheme.textPrimary : DynaQTheme.textMuted)
                }

                Toggle("", isOn: $profile.isLimiterEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: DynaQTheme.green))
                    .labelsHidden()

                RotaryKnob(
                    title: "Ceil",
                    value: $profile.limiterCeiling,
                    range: -6.0...0.0,
                    defaultValue: -0.2,
                    unit: "dB",
                    tintColor: DynaQTheme.green
                )
            }
            .frame(width: 64)

            Divider().background(DynaQTheme.surfaceBorder)

            // Global Bypass & A/B Status
            VStack(spacing: 8) {
                Button(action: {
                    profile.isBypassed.toggle()
                }) {
                    Text(profile.isBypassed ? "BYPASSED" : "ACTIVE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .frame(width: 72, height: 26)
                        .background(profile.isBypassed ? DynaQTheme.red.opacity(0.8) : DynaQTheme.surfaceElevated)
                        .foregroundColor(profile.isBypassed ? .white : DynaQTheme.cyan)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(profile.isBypassed ? DynaQTheme.red : DynaQTheme.cyan.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(profile.isBypassed ? "EQ Offline" : "DSP Engaged")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(DynaQTheme.textMuted)
            }

            // Real-time VU / Peak Meter
            VUMeterView(meter: meter, onResetClip: onResetClip)
        }
        .padding(10)
        .background(DynaQTheme.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

