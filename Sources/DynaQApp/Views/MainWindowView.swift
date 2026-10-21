import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQUI
import DynaQAudioDriver

/// Main Studio Window interface for dynaQ.
/// Minimal Brutalist Terminal Aesthetic: monospace typography, sharp 1px borders, zero neon glow or bubbles.
public struct MainWindowView: View {
    @ObservedObject var state = AppState.shared
    @State private var showAppRouting = false

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // Header Bar: Studio Branding, Power Switch, Preset, and Hardware I/O
            HStack(spacing: 10) {
                // Engine Power Switch & System Status
                Button(action: {
                    state.toggleEnginePower()
                }) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(state.isEngineOnline ? DynaQTheme.phosphorGreen : DynaQTheme.terminalRed)
                            .frame(width: 6, height: 14)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("DYNAQ")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundColor(DynaQTheme.textPrimary)
                            Text(state.isEngineOnline ? "ONLINE // 48kHz" : "STANDBY")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(state.isEngineOnline ? DynaQTheme.phosphorGreen : DynaQTheme.textMuted)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(DynaQTheme.surfaceElevated)
                    .overlay(
                        Rectangle().stroke(state.isEngineOnline ? DynaQTheme.phosphorGreen.opacity(0.6) : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Preset Selector
                PresetPickerView(
                    currentProfile: Binding(
                        get: { state.currentProfile },
                        set: { state.currentProfile = $0 }
                    ),
                    presets: state.presets,
                    onSelectPreset: { state.selectPreset($0) },
                    onSaveCustom: { state.saveCustomPreset(name: $0) }
                )

                Spacer()

                // Complete Hardware I/O & Target App Selector
                DeviceSelectorView(
                    captureSource: state.captureSource,
                    availableApps: state.availableAudioApps,
                    selectedApp: state.selectedAudioApp,
                    devices: state.devices,
                    currentInput: state.selectedInputDevice,
                    currentOutput: state.selectedOutputDevice,
                    bufferSize: state.selectedBufferSize,
                    latencyMs: state.roundtripLatencyMs,
                    feedbackGuard: state.feedbackProtection,
                    onSelectCaptureSource: { state.setCaptureSource($0) },
                    onSelectApp: { state.selectAudioApp($0) },
                    onSelectInput: { state.setInputDevice($0) },
                    onSelectOutput: { state.setOutputDevice($0) },
                    onSelectBufferSize: { state.setBufferSize($0) },
                    onToggleFeedbackGuard: { state.feedbackProtection.toggle() }
                )

                // Per-App Routing Drawer Toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAppRouting.toggle()
                    }
                }) {
                    Text(showAppRouting ? "[ APPS: CLOSE ]" : "[ APPS ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(showAppRouting ? DynaQTheme.terminalCyan.opacity(0.15) : DynaQTheme.surfaceElevated)
                        .foregroundColor(showAppRouting ? DynaQTheme.terminalCyan : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(showAppRouting ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Primary Interactive Parametric EQ Curve & Live Spectrum Visualizer
            EQCurveView(
                profile: Binding(
                    get: { state.currentProfile },
                    set: { state.currentProfile = $0 }
                ),
                selectedBandID: $state.selectedBandID,
                spectrumDB: state.spectrumDB,
                sampleRate: Float(state.selectedOutputDevice?.currentSampleRate ?? 48000.0)
            )
            .frame(minHeight: 280)
            .padding(.horizontal, 12)

            // Selected Band Parameter Inspector, M/S Routing & Dynamic EQ
            EQBandInspectorView(
                profile: Binding(
                    get: { state.currentProfile },
                    set: { state.currentProfile = $0 }
                ),
                selectedBandID: $state.selectedBandID
            )
            .padding(.horizontal, 12)

            // Per-App Routing Drawer (Collapsible)
            if showAppRouting {
                AppRoutingView(
                    routes: $state.appRoutes,
                    availableProfiles: state.presets
                )
                .padding(.horizontal, 12)
                .transition(.opacity)
            }

            // Master Section (Preamp, Master, Phase Invert, Limiter, A/B Compare, Segmented VU Meters)
            MasterSectionView(
                profile: Binding(
                    get: { state.currentProfile },
                    set: { state.currentProfile = $0 }
                ),
                meter: state.currentMeter,
                activeSlot: state.activeSlot.rawValue,
                onSwitchSlot: { slot in
                    state.switchToSlot(slot == "A" ? .slotA : .slotB)
                },
                onCopySlot: {
                    state.copyActiveSlotToInactive()
                },
                onResetClip: {
                    state.resetClip()
                }
            )
            .padding(.horizontal, 12)

            // Terminal Status Bar
            HStack(spacing: 8) {
                let appStr = state.selectedAudioApp?.name ?? "System Audio"
                let outStr = state.selectedOutputDevice?.name ?? "Default Output"
                let srStr = String(format: "%.0f Hz", state.selectedOutputDevice?.currentSampleRate ?? 48000.0)

                Text("// ROUTE: [ \(appStr.uppercased()) ] ➔ [ \(outStr.uppercased()) (\(srStr)) ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)

                Spacer()

                Text("// BUFFER: \(state.selectedBufferSize) SPLS  |  LATENCY: \(String(format: "%.1f", state.roundtripLatencyMs))ms  |  DSP: \(state.currentProfile.isBypassed ? "BYPASSED" : "ACTIVE")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(DynaQTheme.bg)
    }
}
