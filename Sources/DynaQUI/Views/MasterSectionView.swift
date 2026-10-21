import SwiftUI
import DynaQCore
import DynaQDSP

/// Master output section with gain staging, limiter, phase invert, auditioning, and segmented VU metering.
/// Brutalist Terminal Hardware Aesthetic: sharp 1px borders, monospace typography, zero neon glow.
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
        HStack(spacing: 10) {
            // A / B State Comparison
            VStack(spacing: 4) {
                Text("[ A/B COMPARE ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)

                HStack(spacing: 3) {
                    Button(action: { onSwitchSlot("A") }) {
                        Text("A")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .frame(width: 24, height: 22)
                            .background(activeSlot == "A" ? DynaQTheme.terminalCyan : DynaQTheme.surfaceElevated)
                            .foregroundColor(activeSlot == "A" ? .black : DynaQTheme.textPrimary)
                            .overlay(
                                Rectangle().stroke(activeSlot == "A" ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: { onSwitchSlot("B") }) {
                        Text("B")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .frame(width: 24, height: 22)
                            .background(activeSlot == "B" ? DynaQTheme.terminalCyan : DynaQTheme.surfaceElevated)
                            .foregroundColor(activeSlot == "B" ? .black : DynaQTheme.textPrimary)
                            .overlay(
                                Rectangle().stroke(activeSlot == "B" ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCopySlot) {
                    Text("[ A → B ]")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            Rectangle()
                .fill(DynaQTheme.surfaceBorder)
                .frame(width: 1, height: 50)

            // Preamp Gain
            RotaryKnob(
                title: "Preamp",
                value: $profile.preampGain,
                range: -18...18,
                defaultValue: 0.0,
                unit: "dB",
                tintColor: DynaQTheme.terminalBlue
            )

            // Master Gain
            RotaryKnob(
                title: "Master",
                value: $profile.masterGain,
                range: -18...18,
                defaultValue: 0.0,
                unit: "dB",
                tintColor: DynaQTheme.terminalCyan
            )

            Rectangle()
                .fill(DynaQTheme.surfaceBorder)
                .frame(width: 1, height: 50)

            // Audition & Polarity Flip
            VStack(spacing: 5) {
                // Phase Invert Button
                Button(action: {
                    profile.phaseInvert.toggle()
                }) {
                    Text(profile.phaseInvert ? "[ Ø INVERT: ON ]" : "[ Ø PHASE: NORMAL ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .frame(width: 110, height: 22)
                        .background(profile.phaseInvert ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceElevated)
                        .foregroundColor(profile.phaseInvert ? .black : DynaQTheme.textMuted)
                        .overlay(
                            Rectangle().stroke(profile.phaseInvert ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // Monitor Mode Menu
                Menu {
                    ForEach(MonitorMode.allCases) { mode in
                        Button(action: { profile.monitorMode = mode }) {
                            Text(mode.rawValue.uppercased())
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("MONITOR: [ \(profile.monitorMode.rawValue.uppercased()) ]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.terminalCyan)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(DynaQTheme.textMuted)
                    }
                    .frame(width: 110, height: 22)
                    .background(DynaQTheme.surfaceElevated)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            Rectangle()
                .fill(DynaQTheme.surfaceBorder)
                .frame(width: 1, height: 50)

            // Limiter Control
            VStack(spacing: 3) {
                Button(action: {
                    profile.isLimiterEnabled.toggle()
                }) {
                    Text(profile.isLimiterEnabled ? "[ LIMITER: ON ]" : "[ LIMITER: OFF ]")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(profile.isLimiterEnabled ? DynaQTheme.phosphorGreen.opacity(0.15) : DynaQTheme.surfaceElevated)
                        .foregroundColor(profile.isLimiterEnabled ? DynaQTheme.phosphorGreen : DynaQTheme.textMuted)
                        .overlay(
                            Rectangle().stroke(profile.isLimiterEnabled ? DynaQTheme.phosphorGreen : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                RotaryKnob(
                    title: "Ceil",
                    value: $profile.limiterCeiling,
                    range: -6.0...0.0,
                    defaultValue: -0.2,
                    unit: "dB",
                    tintColor: DynaQTheme.phosphorGreen
                )
            }
            .frame(width: 72)

            Rectangle()
                .fill(DynaQTheme.surfaceBorder)
                .frame(width: 1, height: 50)

            // Global Bypass
            VStack(spacing: 3) {
                Button(action: {
                    profile.isBypassed.toggle()
                }) {
                    Text(profile.isBypassed ? "[ DSP: BYPASSED ]" : "[ DSP: ACTIVE ]")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .frame(width: 100, height: 24)
                        .background(profile.isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen.opacity(0.15))
                        .foregroundColor(profile.isBypassed ? .white : DynaQTheme.phosphorGreen)
                        .overlay(
                            Rectangle().stroke(profile.isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(profile.isBypassed ? "// RAW AUDIO PASS" : "// REAL-TIME FILTERING")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }

            Spacer()

            // Real-time Segmented Hardware VU / Peak / RMS Meter
            VUMeterView(meter: meter, onResetClip: onResetClip)
        }
        .padding(8)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
