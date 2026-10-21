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
        VStack(spacing: 12) {
            // Header Bar
            HStack(spacing: 14) {
                // Logo & Engine Indicator
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DynaQTheme.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("dynaQ")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(DynaQTheme.textPrimary)
                        Text("PRO AUDIO SUITE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.cyan)
                    }
                }

                Divider().background(DynaQTheme.surfaceBorder).frame(height: 24)

                // Preset Picker
                PresetPickerView(
                    currentProfile: $state.currentProfile,
                    presets: state.presets,
                    onSelectPreset: { state.selectPreset($0) },
                    onSaveCustom: { state.saveCustomPreset(name: $0) }
                )

                // Output Device Selector
                DeviceSelectorView(
                    devices: state.devices,
                    currentDevice: state.currentDevice,
                    onSelectDevice: { state.currentDevice = $0 }
                )

                Spacer()

                // Test Tone Generator Button (Instant audio/spectrum simulation)
                Button(action: {
                    state.toggleDemoAudio()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: state.isDemoAudioRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text(state.isDemoAudioRunning ? "STOP TEST TONE" : "TEST TONE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(state.isDemoAudioRunning ? DynaQTheme.amber.opacity(0.8) : DynaQTheme.surfaceElevated)
                    .foregroundColor(state.isDemoAudioRunning ? .black : DynaQTheme.textSecondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // App Routing Toggle
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
                    .padding(.vertical, 6)
                    .background(showAppRouting ? DynaQTheme.cyan.opacity(0.2) : DynaQTheme.surfaceElevated)
                    .foregroundColor(showAppRouting ? DynaQTheme.cyan : DynaQTheme.textSecondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Primary Interactive Parametric EQ Curve & Spectrum Visualizer
            EQCurveView(
                profile: $state.currentProfile,
                selectedBandID: $state.selectedBandID,
                spectrumDB: state.spectrumDB,
                sampleRate: Float(state.currentDevice?.currentSampleRate ?? 48000.0)
            )
            .frame(minHeight: 260)
            .padding(.horizontal, 16)

            // Selected Band Parameter Inspector & Dynamic EQ
            EQBandInspectorView(
                profile: $state.currentProfile,
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

            // Master Section (Preamp, Master, Limiter, Meters)
            MasterSectionView(
                profile: $state.currentProfile,
                meter: state.currentMeter,
                onResetClip: { state.resetClip() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(minWidth: 840, minHeight: 640)
        .background(DynaQTheme.bg)
    }
}

