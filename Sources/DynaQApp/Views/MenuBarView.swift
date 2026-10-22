import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQUI

/// Compact Menu Bar view for quick status and preset switching.
/// Minimal Terminal Style: monospace typography, sharp 1px borders, compact rack telemetry.
public struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    public let onOpenMainWindow: () -> Void

    public init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal Header
            HStack {
                Text("// DYNAQ DSP")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(DynaQTheme.terminalCyan)
                Spacer()
                Text(state.currentProfile.isBypassed ? "[ BYPASSED ]" : "[ ONLINE ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(state.currentProfile.isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen.opacity(0.2))
                    .foregroundColor(state.currentProfile.isBypassed ? .white : DynaQTheme.phosphorGreen)
                    .overlay(
                        Rectangle().stroke(state.currentProfile.isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen, lineWidth: 1)
                    )
            }

            Rectangle().fill(DynaQTheme.surfaceBorder).frame(height: 1)

            // Current Hardware I/O Summary
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUTE:")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
                Text("\(state.selectedAudioApp?.name ?? "System Audio") ➔ \(state.selectedOutputDevice?.name ?? "Default Output")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textPrimary)
                    .lineLimit(1)

                Text(String(format: "%.0f Hz • %d spls • %.1f ms latency",
                            state.selectedOutputDevice?.currentSampleRate ?? 48000.0,
                            state.selectedBufferSize,
                            state.roundtripLatencyMs))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
                    .padding(.top, 1)
            }

            Rectangle().fill(DynaQTheme.surfaceBorder).frame(height: 1)

            // Quick Preset Selection
            VStack(alignment: .leading, spacing: 3) {
                Text("// PRESETS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)

                ForEach(state.presets.prefix(5)) { preset in
                    Button(action: {
                        state.selectPreset(preset)
                    }) {
                        HStack {
                            Text(preset.name.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Spacer()
                            if preset.id == state.currentProfile.id {
                                Text("[ACTIVE]")
                                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                                    .foregroundColor(DynaQTheme.phosphorGreen)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 5)
                        .background(preset.id == state.currentProfile.id ? DynaQTheme.surfaceElevated : Color.clear)
                        .foregroundColor(preset.id == state.currentProfile.id ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(preset.id == state.currentProfile.id ? DynaQTheme.surfaceBorderActive : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(DynaQTheme.surfaceBorder).frame(height: 1)

            // Active Error Warning Banner if routing failed
            if let errorMsg = state.activeErrorMessage {
                HStack(spacing: 4) {
                    Text("ERR: \(errorMsg.uppercased())")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.terminalRed)
                        .lineLimit(1)
                    Spacer()
                    Button("[RESET]") {
                        state.resetAudioEngine()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.terminalRed)
                }
                .padding(4)
                .background(DynaQTheme.terminalRed.opacity(0.12))
                .overlay(
                    Rectangle().stroke(DynaQTheme.terminalRed.opacity(0.5), lineWidth: 1)
                )

                Rectangle().fill(DynaQTheme.surfaceBorder).frame(height: 1)
            }

            // Actions
            HStack(spacing: 6) {
                Button(action: onOpenMainWindow) {
                    Text("[ STUDIO ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.terminalCyan)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.terminalCyan, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    state.showSettingsModal = true
                    onOpenMainWindow()
                }) {
                    Text("[ CONFIG ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button("[ QUIT ]") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(DynaQTheme.bg)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
