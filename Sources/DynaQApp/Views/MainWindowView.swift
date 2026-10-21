import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQUI
import DynaQAudioDriver

/// Main Studio Window interface for dynaQ.
public struct MainWindowView: View {
    @ObservedObject var state = AppState.shared
    @State private var showAppRouting = false

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            // Header Bar: Studio Branding, Preset, and Hardware I/O
            HStack(spacing: 12) {
                // Logo & Engine Power Switch
                HStack(spacing: 8) {
                    Button(action: {
                        state.toggleEnginePower()
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(state.isEngineOnline ? DynaQTheme.green : DynaQTheme.red)
                                .frame(width: 8, height: 8)
                                .shadow(color: state.isEngineOnline ? DynaQTheme.green : .clear, radius: 4)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("dynaQ")
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundColor(DynaQTheme.textPrimary)
                                Text(state.isEngineOnline ? "LIVE I/O" : "STANDBY")
                                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                                    .foregroundColor(state.isEngineOnline ? DynaQTheme.green : DynaQTheme.textMuted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(DynaQTheme.surfaceBorder).frame(height: 22)

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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAppRouting.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.forward.dottedline")
                        Text("APPS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(showAppRouting ? DynaQTheme.cyan.opacity(0.2) : DynaQTheme.surfaceElevated)
                    .foregroundColor(showAppRouting ? DynaQTheme.cyan : DynaQTheme.textSecondary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

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
            .frame(minHeight: 270)
            .padding(.horizontal, 16)

            // Selected Band Parameter Inspector, M/S Routing & Dynamic EQ
            EQBandInspectorView(
                profile: Binding(
                    get: { state.currentProfile },
                    set: { state.currentProfile = $0 }
                ),
                selectedBandID: $state.selectedBandID
            )
            .padding(.horizontal, 16)

            // Per-App Routing Drawer (Collapsible)
            if showAppRouting {
                AppRoutingView(
                    routes: $state.appRoutes,
                    availableProfiles: state.presets
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Master Section (Preamp, Master, Phase Invert, Limiter, A/B Compare, VU Meters)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 920, minHeight: 680)
        .background(DynaQTheme.bg)
    }
}
