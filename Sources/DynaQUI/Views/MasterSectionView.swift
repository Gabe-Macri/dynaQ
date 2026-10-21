import SwiftUI
import DynaQCore
import DynaQDSP

/// Master output section with gain staging, limiter, phase invert, auditioning, and metering.
public struct MasterSectionView: View {
    @Binding public var profile: EQProfile
    public let meter: AudioMeter
    public let activeSlot: String
    public let onSwitchSlot: (String) -> Void
    public let onCopySlot: () -> Void
    public let onResetClip: () -> Void

    public init(
        profile: Binding<EQProfile>,
        meter: AudioMeter,
        activeSlot: String = "A",
        onSwitchSlot: @escaping (String) -> Void = { _ in },
        onCopySlot: @escaping () -> Void = {},
        onResetClip: @escaping () -> Void = {}
    ) {
        self._profile = profile
        self.meter = meter
        self.activeSlot = activeSlot
        self.onSwitchSlot = onSwitchSlot
        self.onCopySlot = onCopySlot
        self.onResetClip = onResetClip
    }

    public var body: some View {
        HStack(spacing: 14) {
            // A / B State Comparison
            VStack(spacing: 5) {
                Text("A / B COMPARE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)

                HStack(spacing: 4) {
                    Button(action: { onSwitchSlot("A") }) {
                        Text("A")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .frame(width: 24, height: 22)
                            .background(activeSlot == "A" ? DynaQTheme.cyan : DynaQTheme.surfaceElevated)
                            .foregroundColor(activeSlot == "A" ? .black : DynaQTheme.textPrimary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onSwitchSlot("B") }) {
                        Text("B")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .frame(width: 24, height: 22)
                            .background(activeSlot == "B" ? DynaQTheme.cyan : DynaQTheme.surfaceElevated)
                            .foregroundColor(activeSlot == "B" ? .black : DynaQTheme.textPrimary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCopySlot) {
                    Text("COPY A → B")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .foregroundColor(DynaQTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            Divider().background(DynaQTheme.surfaceBorder)

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

            // Audition & Polarity Flip
            VStack(spacing: 6) {
                // Phase Invert Button
                Button(action: {
                    profile.phaseInvert.toggle()
                }) {
                    HStack(spacing: 4) {
                        Text("Ø")
                            .font(.system(size: 11, weight: .heavy))
                        Text("PHASE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .frame(width: 66, height: 22)
                    .background(profile.phaseInvert ? DynaQTheme.amber : DynaQTheme.surfaceElevated)
                    .foregroundColor(profile.phaseInvert ? .black : DynaQTheme.textSecondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // Monitor Mode Menu
                Menu {
                    ForEach(MonitorMode.allCases) { mode in
                        Button(action: { profile.monitorMode = mode }) {
                            Text(mode.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(profile.monitorMode.rawValue)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.cyan)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                    }
                    .frame(width: 66, height: 22)
                    .background(DynaQTheme.surfaceElevated)
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
            }

            Divider().background(DynaQTheme.surfaceBorder)

            // Limiter Control
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(profile.isLimiterEnabled ? DynaQTheme.green : DynaQTheme.textMuted)
                        .frame(width: 5, height: 5)
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
            .frame(width: 58)

            Divider().background(DynaQTheme.surfaceBorder)

            // Global Bypass
            VStack(spacing: 6) {
                Button(action: {
                    profile.isBypassed.toggle()
                }) {
                    Text(profile.isBypassed ? "BYPASS" : "ACTIVE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .frame(width: 68, height: 26)
                        .background(profile.isBypassed ? DynaQTheme.red : DynaQTheme.surfaceElevated)
                        .foregroundColor(profile.isBypassed ? .white : DynaQTheme.cyan)
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(profile.isBypassed ? DynaQTheme.red : DynaQTheme.cyan.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(profile.isBypassed ? "DSP Offline" : "Live Processing")
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
