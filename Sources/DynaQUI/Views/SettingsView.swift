import SwiftUI
import CoreAudio
import DynaQCore
import DynaQAudioDriver

/// Pro-Audio Terminal Settings Interface for dynaQ.
/// Strict brutalist monospace studio console: zero emojis, sharp 1px borders, phosphor telemetry.
public struct SettingsView: View {
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case audioIO = "AUDIO I/O & ROUTING"
        case dspLimiter = "DSP & LIMITING"
        case safety = "SAFETY & GUARDS"
        case diagnostics = "DIAGNOSTICS & LOGS"
        case about = "SYSTEM INFO"

        public var id: String { rawValue }
    }

    @State private var selectedTab: SettingsTab = .audioIO

    // Hardware & Routing Props
    public let captureSource: AudioCaptureSource
    public let availableApps: [AudioAppProcess]
    public let selectedApp: AudioAppProcess?
    public let tapAllProcesses: Bool
    public let devices: [AudioDevice]
    public let currentInput: AudioDevice?
    public let currentOutput: AudioDevice?
    public let bufferSize: UInt32
    public let latencyMs: Double
    public let feedbackProtection: Bool

    // DSP & Limiter Props
    public let isLimiterEnabled: Bool
    public let limiterCeiling: Float
    public let isLiveMode: Bool
    public let isBypassed: Bool

    // Telemetry & Diagnostics Props
    public let underrunCount: Int
    public let isEngineOnline: Bool
    public let diagnosticLogs: [(timestamp: String, level: String, message: String)]
    public let isDriverInstalled: Bool

    // Callbacks
    public let onSelectCaptureSource: (AudioCaptureSource) -> Void
    public let onSelectApp: (AudioAppProcess) -> Void
    public let onToggleTapAllProcesses: (Bool) -> Void
    public let onSelectInput: (AudioDevice) -> Void
    public let onSelectOutput: (AudioDevice) -> Void
    public let onSelectBufferSize: (UInt32) -> Void
    public let onToggleFeedbackProtection: () -> Void
    public let onToggleLimiter: () -> Void
    public let onToggleLiveMode: () -> Void
    public let onSelectLimiterCeiling: (Float) -> Void
    public let onToggleBypass: () -> Void
    public let onResetEngine: () -> Void
    public let onRefreshDevices: () -> Void
    public let onClearLogs: () -> Void
    public let onInstallDriver: () -> Void
    public let onClose: () -> Void

    public init(
        captureSource: AudioCaptureSource,
        availableApps: [AudioAppProcess],
        selectedApp: AudioAppProcess?,
        tapAllProcesses: Bool,
        devices: [AudioDevice],
        currentInput: AudioDevice?,
        currentOutput: AudioDevice?,
        bufferSize: UInt32,
        latencyMs: Double,
        feedbackProtection: Bool,
        isLimiterEnabled: Bool,
        limiterCeiling: Float,
        isLiveMode: Bool = false,
        isBypassed: Bool,
        underrunCount: Int,
        isEngineOnline: Bool,
        diagnosticLogs: [(timestamp: String, level: String, message: String)],
        isDriverInstalled: Bool = FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver"),
        onSelectCaptureSource: @escaping (AudioCaptureSource) -> Void,
        onSelectApp: @escaping (AudioAppProcess) -> Void,
        onToggleTapAllProcesses: @escaping (Bool) -> Void,
        onSelectInput: @escaping (AudioDevice) -> Void,
        onSelectOutput: @escaping (AudioDevice) -> Void,
        onSelectBufferSize: @escaping (UInt32) -> Void,
        onToggleFeedbackProtection: @escaping () -> Void,
        onToggleLimiter: @escaping () -> Void,
        onToggleLiveMode: @escaping () -> Void = {},
        onSelectLimiterCeiling: @escaping (Float) -> Void,
        onToggleBypass: @escaping () -> Void,
        onResetEngine: @escaping () -> Void,
        onRefreshDevices: @escaping () -> Void,
        onClearLogs: @escaping () -> Void,
        onInstallDriver: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self.captureSource = captureSource
        self.availableApps = availableApps
        self.selectedApp = selectedApp
        self.tapAllProcesses = tapAllProcesses
        self.devices = devices
        self.currentInput = currentInput
        self.currentOutput = currentOutput
        self.bufferSize = bufferSize
        self.latencyMs = latencyMs
        self.feedbackProtection = feedbackProtection
        self.isLimiterEnabled = isLimiterEnabled
        self.limiterCeiling = limiterCeiling
        self.isLiveMode = isLiveMode
        self.isBypassed = isBypassed
        self.underrunCount = underrunCount
        self.isEngineOnline = isEngineOnline
        self.diagnosticLogs = diagnosticLogs
        self.isDriverInstalled = isDriverInstalled
        self.onSelectCaptureSource = onSelectCaptureSource
        self.onSelectApp = onSelectApp
        self.onToggleTapAllProcesses = onToggleTapAllProcesses
        self.onSelectInput = onSelectInput
        self.onSelectOutput = onSelectOutput
        self.onSelectBufferSize = onSelectBufferSize
        self.onToggleFeedbackProtection = onToggleFeedbackProtection
        self.onToggleLimiter = onToggleLimiter
        self.onToggleLiveMode = onToggleLiveMode
        self.onSelectLimiterCeiling = onSelectLimiterCeiling
        self.onToggleBypass = onToggleBypass
        self.onResetEngine = onResetEngine
        self.onRefreshDevices = onRefreshDevices
        self.onClearLogs = onClearLogs
        self.onInstallDriver = onInstallDriver
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(DynaQTheme.terminalCyan)
                        .frame(width: 4, height: 16)
                    Text("// DYNAQ SYSTEM CONFIGURATION & HARDWARE SETTINGS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                }

                Spacer()

                Button(action: onClose) {
                    Text("[ CLOSE ESC ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DynaQTheme.surfaceElevated)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DynaQTheme.surfaceBorder),
                alignment: .bottom
            )

            // Tab Selector Strip
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: selectedTab == tab ? .heavy : .medium, design: .monospaced))
                            .foregroundColor(selectedTab == tab ? DynaQTheme.terminalCyan : DynaQTheme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? DynaQTheme.bg : DynaQTheme.surface)
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(selectedTab == tab ? DynaQTheme.terminalCyan : Color.clear),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DynaQTheme.surfaceBorder),
                alignment: .bottom
            )

            // Tab Content Pane
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .audioIO:
                        audioIOTabView
                    case .dspLimiter:
                        dspLimiterTabView
                    case .safety:
                        safetyTabView
                    case .diagnostics:
                        diagnosticsTabView
                    case .about:
                        aboutTabView
                    }
                }
                .padding(20)
            }
            .background(DynaQTheme.bg)

            // Footer Status Bar
            HStack(spacing: 12) {
                Text(isEngineOnline ? "// COREAUDIO HAL: ONLINE" : "// COREAUDIO HAL: STANDBY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isEngineOnline ? DynaQTheme.phosphorGreen : DynaQTheme.terminalRed)

                Spacer()

                Text("UNDERRUNS: \(underrunCount)  |  BUFFER: \(bufferSize) SPLS  |  LATENCY: \(String(format: "%.1f", latencyMs))ms")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DynaQTheme.surfaceBorder),
                alignment: .top
            )
        }
        .frame(width: 720, height: 520)
        .background(DynaQTheme.bg)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Tab 1: Audio I/O & Routing

    private var audioIOTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("AUDIO CAPTURE SOURCE")

            HStack(spacing: 12) {
                ForEach(AudioCaptureSource.allCases, id: \.self) { source in
                    Button(action: { onSelectCaptureSource(source) }) {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(captureSource == source ? DynaQTheme.phosphorGreen : DynaQTheme.surfaceBorder)
                                .frame(width: 6, height: 6)
                            Text(source.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(captureSource == source ? DynaQTheme.surfaceElevated : DynaQTheme.surface)
                        .foregroundColor(captureSource == source ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(captureSource == source ? DynaQTheme.phosphorGreen : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if captureSource == .systemAudio {
                sectionHeader("PROCESS CAPTURE TARGET")

                HStack(spacing: 12) {
                    Button(action: { onToggleTapAllProcesses(true) }) {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(tapAllProcesses ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder)
                                .frame(width: 6, height: 6)
                            Text("ALL ACTIVE AUDIO PROCESSES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tapAllProcesses ? DynaQTheme.surfaceElevated : DynaQTheme.surface)
                        .foregroundColor(tapAllProcesses ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(tapAllProcesses ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { onToggleTapAllProcesses(false) }) {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(!tapAllProcesses ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder)
                                .frame(width: 6, height: 6)
                            Text("SINGLE APPLICATION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(!tapAllProcesses ? DynaQTheme.surfaceElevated : DynaQTheme.surface)
                        .foregroundColor(!tapAllProcesses ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle().stroke(!tapAllProcesses ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !tapAllProcesses {
                    Menu {
                        ForEach(availableApps) { app in
                            Button(action: { onSelectApp(app) }) {
                                HStack {
                                    Text(app.name)
                                    if app.id == selectedApp?.id {
                                        Text("[ACTIVE]")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("APP: \(selectedApp?.name ?? "NONE SELECTED")")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Spacer()
                            Text("▼")
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DynaQTheme.surface)
                        .foregroundColor(DynaQTheme.textPrimary)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 320)
                }
            }

            sectionHeader("PHYSICAL HARDWARE ROUTING")

            VStack(alignment: .leading, spacing: 8) {
                // Output Hardware
                HStack {
                    Text("OUTPUT DEVICE:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                        .frame(width: 120, alignment: .leading)

                    Menu {
                        ForEach(devices.filter { $0.isOutput }) { dev in
                            Button(action: { onSelectOutput(dev) }) {
                                Text("\(dev.name) [\(Int(dev.currentSampleRate)) Hz]")
                            }
                        }
                    } label: {
                        HStack {
                            Text(currentOutput?.name ?? "DEFAULT OUTPUT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Spacer()
                            Text("▼")
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DynaQTheme.surface)
                        .foregroundColor(DynaQTheme.textPrimary)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                }

                // Input Hardware
                if captureSource == .hardwareInput {
                    HStack {
                        Text("INPUT DEVICE:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                            .frame(width: 120, alignment: .leading)

                        Menu {
                            ForEach(devices.filter { $0.isInput }) { dev in
                                Button(action: { onSelectInput(dev) }) {
                                    Text("\(dev.name) [\(Int(dev.currentSampleRate)) Hz]")
                                }
                            }
                        } label: {
                            HStack {
                                Text(currentInput?.name ?? "DEFAULT INPUT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                Spacer()
                                Text("▼")
                                    .font(.system(size: 8, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(DynaQTheme.surface)
                            .foregroundColor(DynaQTheme.textPrimary)
                            .overlay(
                                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            sectionHeader("COREAUDIO BUFFER FRAME SIZE")

            HStack(spacing: 8) {
                ForEach([UInt32(64), UInt32(128), UInt32(256), UInt32(512), UInt32(1024)], id: \.self) { size in
                    Button(action: { onSelectBufferSize(size) }) {
                        Text("\(size) SPLS")
                            .font(.system(size: 9, weight: bufferSize == size ? .heavy : .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(bufferSize == size ? DynaQTheme.terminalCyan.opacity(0.2) : DynaQTheme.surface)
                            .foregroundColor(bufferSize == size ? DynaQTheme.terminalCyan : DynaQTheme.textSecondary)
                            .overlay(
                                Rectangle().stroke(bufferSize == size ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("// LOWER BUFFER REDUCES LATENCY; HIGHER BUFFER PREVENTS UNDERRUNS ON HEAVY DSP LOADS")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
        }
    }

    // MARK: - Tab 2: DSP & Limiting

    private var dspLimiterTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("PARAMETRIC EQUALIZATION ENGINE")

            HStack(spacing: 12) {
                Button(action: onToggleBypass) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen)
                            .frame(width: 8, height: 8)
                        Text(isBypassed ? "DSP STATUS: BYPASSED" : "DSP STATUS: ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DynaQTheme.surface)
                    .foregroundColor(isBypassed ? DynaQTheme.terminalRed : DynaQTheme.phosphorGreen)
                    .overlay(
                        Rectangle().stroke(isBypassed ? DynaQTheme.terminalRed : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            sectionHeader("TRUE PEAK BRICKWALL LIMITER")

            HStack(spacing: 12) {
                Button(action: onToggleLimiter) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(isLimiterEnabled ? DynaQTheme.phosphorGreen : DynaQTheme.textMuted)
                            .frame(width: 6, height: 6)
                        Text(isLimiterEnabled ? "LIMITER: ENABLED" : "LIMITER: BYPASSED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DynaQTheme.surface)
                    .foregroundColor(isLimiterEnabled ? DynaQTheme.textPrimary : DynaQTheme.textMuted)
                    .overlay(
                        Rectangle().stroke(isLimiterEnabled ? DynaQTheme.phosphorGreen : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Text("LIMITER CEILING:")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)

            HStack(spacing: 8) {
                ForEach([Float(-0.1), Float(-0.2), Float(-0.5), Float(-1.0), Float(-2.0)], id: \.self) { ceil in
                    let isSelected = abs(limiterCeiling - ceil) < 0.05
                    Button(action: { onSelectLimiterCeiling(ceil) }) {
                        Text(String(format: "%.1f dBFS", ceil))
                            .font(.system(size: 9, weight: isSelected ? .heavy : .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? DynaQTheme.terminalCyan.opacity(0.2) : DynaQTheme.surface)
                            .foregroundColor(isSelected ? DynaQTheme.terminalCyan : DynaQTheme.textSecondary)
                            .overlay(
                                Rectangle().stroke(isSelected ? DynaQTheme.terminalCyan : DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("// SOFT-KNEE VECTORIZED STEREO-LINKED GAIN COMPRESSION ELIMINATES TRANSIENT FUZZ")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)

            sectionHeader("LATENCY ARCHITECTURE / LIVE TRACKING")

            HStack(spacing: 8) {
                Button(action: onToggleLiveMode) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(isLiveMode ? DynaQTheme.phosphorAmber : DynaQTheme.phosphorGreen)
                            .frame(width: 6, height: 6)
                        Text(isLiveMode ? "MODE: ZERO-LATENCY / LIVE (DAW)" : "MODE: MASTERING (TRUE PEAK)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DynaQTheme.surface)
                    .foregroundColor(isLiveMode ? DynaQTheme.phosphorAmber : DynaQTheme.phosphorGreen)
                    .overlay(
                        Rectangle().stroke(isLiveMode ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Text(isLiveMode ? "// ZERO LATENCY (0 SAMPLES LOOKAHEAD): INSTANTANEOUS PEAK CLAMPING FOR LOGIC PRO / DAW TRACKING" : "// STUDIO MASTERING: 32-SAMPLE CIRCULAR DELAY LINE WITH 4X OVERSAMPLED TRUE PEAK GUARD")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
        }
    }

    // MARK: - Tab 3: Safety & Guards

    private var safetyTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("ACOUSTIC FEEDBACK SUPPRESSION")

            Toggle(isOn: Binding(
                get: { feedbackProtection },
                set: { _ in onToggleFeedbackProtection() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPEAKER / MIC FEEDBACK GUARD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                    Text("Automatically mutes speaker output when built-in mic and speakers are active together")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                }
            }
            .toggleStyle(.checkbox)

            sectionHeader("REAL-TIME DSP SAFETY GUARDS")

            VStack(alignment: .leading, spacing: 8) {
                safetyFeatureRow(
                    title: "DENORMAL NUMBER FLUSHING",
                    description: "Forces float values smaller than 1e-15 to absolute 0.0, preventing CPU penalty spikes on biquad tails.",
                    status: "ACTIVE"
                )

                safetyFeatureRow(
                    title: "NAN & INFINITY VALUE CONTAINMENT",
                    description: "Detects numerical overflow in recursive filter states and resets delay memories to prevent loud DC bursts.",
                    status: "ACTIVE"
                )

                safetyFeatureRow(
                    title: "SPSC LOCK-FREE REAL-TIME THREAD BUFFERING",
                    description: "Zero memory allocations (swift_allocObject) and zero locks on high-priority CoreAudio HAL threads.",
                    status: "ACTIVE"
                )
            }
        }
    }

    private func safetyFeatureRow(title: String, description: String, status: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(DynaQTheme.phosphorGreen)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                    Spacer()
                    Text("[\(status)]")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(DynaQTheme.phosphorGreen)
                }
                Text(description)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }
        }
        .padding(8)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Tab 4: Diagnostics & Logs

    private var diagnosticsTabView: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("AUDIO ENGINE TELEMETRY & HEALTH")

            HStack(spacing: 12) {
                metricBox(label: "ENGINE STATE", value: isEngineOnline ? "ONLINE" : "STANDBY", color: isEngineOnline ? DynaQTheme.phosphorGreen : DynaQTheme.terminalRed)
                metricBox(label: "RING BUFFER UNDERRUNS", value: "\(underrunCount)", color: underrunCount > 0 ? DynaQTheme.phosphorAmber : DynaQTheme.phosphorGreen)
                metricBox(label: "TOTAL LATENCY", value: String(format: "%.1f ms", latencyMs), color: DynaQTheme.terminalCyan)
                metricBox(label: "ACTIVE SAMPLE RATE", value: "\(Int(currentOutput?.currentSampleRate ?? 48000)) Hz", color: DynaQTheme.textPrimary)
            }

            sectionHeader("ENGINE CONTROLS & RECOVERY")

            HStack(spacing: 10) {
                Button(action: onResetEngine) {
                    Text("[ RESET AUDIO ENGINE & BUFFER ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.phosphorAmber)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.phosphorAmber.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onRefreshDevices) {
                    Text("[ RE-ENUMERATE HARDWARE ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.terminalCyan)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onClearLogs) {
                    Text("[ CLEAR LOGS ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(DynaQTheme.textMuted)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            sectionHeader("DIAGNOSTIC LOG STREAM")

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if diagnosticLogs.isEmpty {
                        Text("// NO RECENT DIAGNOSTIC EVENTS RECORDED")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                            .padding(8)
                    } else {
                        ForEach(Array(diagnosticLogs.enumerated()), id: \.offset) { _, log in
                            HStack(spacing: 6) {
                                Text(log.timestamp)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(DynaQTheme.textMuted)

                                Text("[\(log.level)]")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(levelColor(log.level))

                                Text(log.message)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(DynaQTheme.textPrimary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 140)
            .background(Color.black)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func metricBox(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "ERR": return DynaQTheme.terminalRed
        case "WARN": return DynaQTheme.phosphorAmber
        case "DSP": return DynaQTheme.terminalCyan
        default: return DynaQTheme.phosphorGreen
        }
    }

    // MARK: - Tab 5: About & Architecture

    private var aboutTabView: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DYNAQ AUDIO PLATFORM ARCHITECTURE")

            VStack(alignment: .leading, spacing: 6) {
                Text("DYNAQ COREAUDIO ENGINE // VERSION 1.0.0-BETA.1")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(DynaQTheme.textPrimary)

                Text("A high-precision, low-overhead parametric equalization and dynamics processing system engineered for macOS.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DynaQTheme.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )

            sectionHeader("COREAUDIO VIRTUAL HAL DRIVER")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HAL PLUGIN: \(isDriverInstalled ? "INSTALLED & ACTIVE" : "NOT DEPLOYED IN SYSTEM")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isDriverInstalled ? DynaQTheme.phosphorGreen : DynaQTheme.phosphorAmber)
                    Text(isDriverInstalled ? "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver" : "Install virtual driver to enable aggregate DAW routing and system loopback")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                }

                Spacer()

                Button(action: onInstallDriver) {
                    Text(isDriverInstalled ? "[ REINSTALL / UPDATE ]" : "[ INSTALL DRIVER ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DynaQTheme.surfaceElevated)
                        .foregroundColor(isDriverInstalled ? DynaQTheme.textMuted : DynaQTheme.terminalCyan)
                        .overlay(
                            Rectangle().stroke(isDriverInstalled ? DynaQTheme.surfaceBorder : DynaQTheme.terminalCyan, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )

            sectionHeader("TECHNICAL SPECIFICATIONS")

            VStack(alignment: .leading, spacing: 4) {
                specRow("AUDIO BACKEND", "Direct CoreAudio HAL IOProc + macOS 14.2+ System Tap")
                specRow("DSP KERNEL", "Apple Accelerate Framework (vDSP) + SIMD C Kernel")
                specRow("RING BUFFER", "Lock-Free SPSC Atomic Ring Buffer with 64-bit Monotonic Counters")
                specRow("LIMITER", "Rational Soft-Knee Stereo-Linked Peak Limiter with Brickwall Ceiling")
                specRow("NUMERICAL PRECISION", "32-bit Floating Point with Denormal Flushing & Inf/NaN Guards")
                specRow("INTERRUPT LATENCY", "Real-Time CoreAudio Thread (Zero Allocations, Zero Locks)")
            }
            .padding(10)
            .background(DynaQTheme.surface)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func specRow(_ key: String, _ val: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(DynaQTheme.textMuted)
                .frame(width: 140, alignment: .leading)
            Text(val)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DynaQTheme.terminalCyan)
            Spacer()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text("// \(title)")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(DynaQTheme.textMuted)
    }
}

