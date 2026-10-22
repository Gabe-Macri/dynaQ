import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQUI
import DynaQAudioDriver

/// Main Studio Window interface for dynaQ.
/// Minimal Brutalist Terminal Aesthetic: monospace typography, sharp 1px borders, zero neon glow or bubbles.
public struct MainWindowView: View {
    @ObservedObject var state = AppState.shared

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
                            Text(state.isEngineOnline ? "ONLINE // AUTO-ROUTE" : "STANDBY")
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

                // Complete Hardware I/O & Unified Target Selector
                DeviceSelectorView(
                    captureSource: state.captureSource,
                    tapAllProcesses: state.tapAllProcesses,
                    availableApps: state.availableAudioApps,
                    selectedApp: state.selectedAudioApp,
                    devices: state.devices,
                    currentInput: state.selectedInputDevice,
                    currentOutput: state.selectedOutputDevice,
                    bufferSize: state.selectedBufferSize,
                    latencyMs: state.roundtripLatencyMs,
                    feedbackGuard: state.feedbackProtection,
                    onSelectCaptureSource: { state.setCaptureSource($0) },
                    onToggleTapAllProcesses: { state.setTapAllProcesses($0) },
                    onSelectApp: { state.selectAudioApp($0) },
                    onSelectInput: { state.setInputDevice($0) },
                    onSelectOutput: { state.setOutputDevice($0) },
                    onSelectBufferSize: { state.setBufferSize($0) },
                    onToggleFeedbackGuard: { state.feedbackProtection.toggle() }
                )

                // Comprehensive System Settings Modal Toggle
                Button(action: {
                    state.showSettingsModal.toggle()
                }) {
                    Text(state.showSettingsModal ? "[ CONFIG: OPEN ]" : "[ CONFIG ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(state.showSettingsModal ? DynaQTheme.terminalCyan.opacity(0.15) : DynaQTheme.surfaceElevated)
                        .foregroundColor(state.showSettingsModal ? DynaQTheme.terminalCyan : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(state.showSettingsModal ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Real-Time Audio Error Alert Banner (Monospace Brutalist)
            if let errorMsg = state.activeErrorMessage {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(DynaQTheme.terminalRed)
                        .frame(width: 4, height: 18)

                    Text("ERROR: \(errorMsg.uppercased())")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.terminalRed)
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        state.resetAudioEngine()
                    }) {
                        Text("[ RETRY / RESET ENGINE ]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DynaQTheme.terminalRed.opacity(0.15))
                            .foregroundColor(DynaQTheme.terminalRed)
                            .overlay(
                                Rectangle().stroke(DynaQTheme.terminalRed, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        state.dismissError()
                    }) {
                        Text("[ DISMISS X ]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DynaQTheme.surfaceElevated)
                            .foregroundColor(DynaQTheme.textMuted)
                            .overlay(
                                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DynaQTheme.surface)
                .overlay(
                    Rectangle().stroke(DynaQTheme.terminalRed.opacity(0.6), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .transition(.opacity)
            }

            // Safe Recovery Mode Banner
            if state.isSafeMode {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(DynaQTheme.amber)
                        .frame(width: 4, height: 18)

                    Text("// SAFE RECOVERY MODE ENGAGED // DSP BYPASSED // FACTORY FLAT ACTIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.amber)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DynaQTheme.surface)
                .overlay(
                    Rectangle().stroke(DynaQTheme.amber.opacity(0.6), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .transition(.opacity)
            }

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
                let sourceStr = routeSourceString
                let outStr = state.selectedOutputDevice?.name ?? "Default Output"
                let srStr = String(format: "%.0f Hz", state.selectedOutputDevice?.currentSampleRate ?? 48000.0)

                Text("// ROUTE: [ \(sourceStr) ] ➔ [ \(outStr.uppercased()) (\(srStr)) ]")
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
        .frame(minWidth: 1040, minHeight: 660)
        .background(DynaQTheme.bg)
        .sheet(isPresented: $state.showSettingsModal) {
            SettingsView(
                captureSource: state.captureSource,
                availableApps: state.availableAudioApps,
                selectedApp: state.selectedAudioApp,
                tapAllProcesses: state.tapAllProcesses,
                devices: state.devices,
                currentInput: state.selectedInputDevice,
                currentOutput: state.selectedOutputDevice,
                bufferSize: state.selectedBufferSize,
                latencyMs: state.roundtripLatencyMs,
                feedbackProtection: state.feedbackProtection,
                isLimiterEnabled: state.currentProfile.isLimiterEnabled,
                limiterCeiling: state.currentProfile.limiterCeiling,
                isLiveMode: state.isLiveMode,
                isBypassed: state.currentProfile.isBypassed,
                underrunCount: state.underrunCount,
                isEngineOnline: state.isEngineOnline,
                diagnosticLogs: state.diagnosticLogs.map { ($0.timestamp, $0.level, $0.message) },
                isDriverInstalled: state.isHalDriverInstalled,
                onSelectCaptureSource: { state.setCaptureSource($0) },
                onSelectApp: { state.selectAudioApp($0) },
                onToggleTapAllProcesses: { state.setTapAllProcesses($0) },
                onSelectInput: { state.setInputDevice($0) },
                onSelectOutput: { state.setOutputDevice($0) },
                onSelectBufferSize: { state.setBufferSize($0) },
                onToggleFeedbackProtection: { state.feedbackProtection.toggle() },
                onToggleLimiter: { state.toggleLimiter() },
                onToggleLiveMode: { state.isLiveMode.toggle() },
                onSelectLimiterCeiling: { state.setLimiterCeiling($0) },
                onToggleBypass: { state.toggleMasterBypass() },
                onResetEngine: { state.resetAudioEngine() },
                onRefreshDevices: { state.refreshHardwareDevices() },
                onClearLogs: { state.clearDiagnosticLogs() },
                onInstallDriver: { state.installHalDriver() },
                onClose: { state.showSettingsModal = false }
            )
        }
    }

    private var routeSourceString: String {
        if state.captureSource == .systemAudio {
            return state.tapAllProcesses ? "ALL SYSTEM AUDIO" : (state.selectedAudioApp?.name.uppercased() ?? "SYSTEM AUDIO")
        } else {
            return state.selectedInputDevice?.name.uppercased() ?? "MIC IN"
        }
    }
}
