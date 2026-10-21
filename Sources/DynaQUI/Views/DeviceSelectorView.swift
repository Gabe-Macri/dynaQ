import SwiftUI
import CoreAudio
import DynaQCore
import DynaQAudioDriver

/// Hardware I/O selector strip showing Target App, Capture Source, Input, Output, Buffer Size, and Live Latency.
/// Minimal Terminal Style: monospace typography, sharp 1px borders, command-line parameter styling.
public struct DeviceSelectorView: View {
    public let captureSource: AudioCaptureSource
    public let availableApps: [AudioAppProcess]
    public let selectedApp: AudioAppProcess?
    public let devices: [AudioDevice]
    public let currentInput: AudioDevice?
    public let currentOutput: AudioDevice?
    public let bufferSize: UInt32
    public let latencyMs: Double
    public let feedbackGuard: Bool
    public let onSelectCaptureSource: (AudioCaptureSource) -> Void
    public let onSelectApp: (AudioAppProcess) -> Void
    public let onSelectInput: (AudioDevice) -> Void
    public let onSelectOutput: (AudioDevice) -> Void
    public let onSelectBufferSize: (UInt32) -> Void
    public let onToggleFeedbackGuard: () -> Void

    public init(
        captureSource: AudioCaptureSource = .systemAudio,
        availableApps: [AudioAppProcess] = [],
        selectedApp: AudioAppProcess? = nil,
        devices: [AudioDevice],
        currentInput: AudioDevice?,
        currentOutput: AudioDevice?,
        bufferSize: UInt32,
        latencyMs: Double,
        feedbackGuard: Bool,
        onSelectCaptureSource: @escaping (AudioCaptureSource) -> Void = { _ in },
        onSelectApp: @escaping (AudioAppProcess) -> Void = { _ in },
        onSelectInput: @escaping (AudioDevice) -> Void,
        onSelectOutput: @escaping (AudioDevice) -> Void,
        onSelectBufferSize: @escaping (UInt32) -> Void,
        onToggleFeedbackGuard: @escaping () -> Void
    ) {
        self.captureSource = captureSource
        self.availableApps = availableApps
        self.selectedApp = selectedApp
        self.devices = devices
        self.currentInput = currentInput
        self.currentOutput = currentOutput
        self.bufferSize = bufferSize
        self.latencyMs = latencyMs
        self.feedbackGuard = feedbackGuard
        self.onSelectCaptureSource = onSelectCaptureSource
        self.onSelectApp = onSelectApp
        self.onSelectInput = onSelectInput
        self.onSelectOutput = onSelectOutput
        self.onSelectBufferSize = onSelectBufferSize
        self.onToggleFeedbackGuard = onToggleFeedbackGuard
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Target Application Selector (When in System Audio Mode)
            if captureSource == .systemAudio {
                Menu {
                    Section(header: Text("TARGET APPLICATION TO CAPTURE & EQUALIZE")) {
                        ForEach(availableApps) { app in
                            Button(action: { onSelectApp(app) }) {
                                HStack {
                                    Text(app.name)
                                    if app.id == selectedApp?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("APP:")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                        Text("[ \(selectedApp?.name ?? "Apple Music") ]")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.terminalCyan)
                            .lineLimit(1)
                            .frame(maxWidth: 120, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(DynaQTheme.textMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(DynaQTheme.surfaceElevated)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            // Hardware Input Device Selector (If Hardware Input Mode)
            if captureSource == .hardwareInput {
                Menu {
                    Section(header: Text("HARDWARE INPUT")) {
                        ForEach(devices.filter { $0.isInput }) { dev in
                            Button(action: { onSelectInput(dev) }) {
                                HStack {
                                    Text(dev.name)
                                    if dev.id == currentInput?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("IN:")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                        Text("[ \(currentInput?.name ?? "No Input") ]")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.terminalBlue)
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(DynaQTheme.textMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(DynaQTheme.surfaceElevated)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            // Output Device Selector
            Menu {
                Section(header: Text("HARDWARE OUTPUT DEVICE")) {
                    ForEach(devices.filter { $0.isOutput }) { dev in
                        Button(action: { onSelectOutput(dev) }) {
                            HStack {
                                Text(dev.name)
                                if dev.id == currentOutput?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("OUT:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    Text("[ \(currentOutput?.name ?? "No Output") ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.phosphorGreen)
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 6))
                        .foregroundColor(DynaQTheme.textMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(DynaQTheme.surfaceElevated)
                .overlay(
                    Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)

            // Buffer Size Picker
            Menu {
                Section(header: Text("COREAUDIO BUFFER FRAME SIZE")) {
                    ForEach([UInt32(64), UInt32(128), UInt32(256), UInt32(512), UInt32(1024)], id: \.self) { size in
                        Button(action: { onSelectBufferSize(size) }) {
                            HStack {
                                Text("\(size) Samples")
                                if size == bufferSize {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("BUF:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    Text("[ \(bufferSize) ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 6))
                        .foregroundColor(DynaQTheme.textMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(DynaQTheme.surfaceElevated)
                .overlay(
                    Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)

            // Latency Readout Badge
            HStack(spacing: 4) {
                Text("LAT:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
                Text(String(format: "%.1f ms", latencyMs))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(latencyMs < 5.0 ? DynaQTheme.phosphorGreen : (latencyMs < 12.0 ? DynaQTheme.phosphorAmber : DynaQTheme.terminalRed))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DynaQTheme.surfaceElevated)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }
}
