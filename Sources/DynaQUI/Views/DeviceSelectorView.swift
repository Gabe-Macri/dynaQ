import SwiftUI
import DynaQCore

/// Pro Audio Hardware I/O selector bar showing Input, Output, Buffer Size, and Live Latency.
public struct DeviceSelectorView: View {
    public let devices: [AudioDevice]
    public let currentInput: AudioDevice?
    public let currentOutput: AudioDevice?
    public let bufferSize: UInt32
    public let latencyMs: Double
    public let feedbackGuard: Bool
    public let onSelectInput: (AudioDevice) -> Void
    public let onSelectOutput: (AudioDevice) -> Void
    public let onSelectBufferSize: (UInt32) -> Void
    public let onToggleFeedbackGuard: () -> Void

    public init(
        devices: [AudioDevice],
        currentInput: AudioDevice?,
        currentOutput: AudioDevice?,
        bufferSize: UInt32,
        latencyMs: Double,
        feedbackGuard: Bool,
        onSelectInput: @escaping (AudioDevice) -> Void,
        onSelectOutput: @escaping (AudioDevice) -> Void,
        onSelectBufferSize: @escaping (UInt32) -> Void,
        onToggleFeedbackGuard: @escaping () -> Void
    ) {
        self.devices = devices
        self.currentInput = currentInput
        self.currentOutput = currentOutput
        self.bufferSize = bufferSize
        self.latencyMs = latencyMs
        self.feedbackGuard = feedbackGuard
        self.onSelectInput = onSelectInput
        self.onSelectOutput = onSelectOutput
        self.onSelectBufferSize = onSelectBufferSize
        self.onToggleFeedbackGuard = onToggleFeedbackGuard
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Input Device Selector
            Menu {
                Section(header: Text("HARDWARE INPUT")) {
                    ForEach(devices.filter { $0.isInput }) { dev in
                        Button(action: { onSelectInput(dev) }) {
                            HStack {
                                Image(systemName: dev.transportType.sfSymbol)
                                Text(dev.name)
                                if dev.id == currentInput?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(DynaQTheme.blue)
                        .font(.system(size: 10))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("IN")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                        Text(currentInput?.name ?? "No Input")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DynaQTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(DynaQTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DynaQTheme.surfaceElevated)
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)

            // Output Device Selector
            Menu {
                Section(header: Text("HARDWARE OUTPUT")) {
                    ForEach(devices.filter { $0.isOutput }) { dev in
                        Button(action: { onSelectOutput(dev) }) {
                            HStack {
                                Image(systemName: dev.transportType.sfSymbol)
                                Text(dev.name)
                                if dev.id == currentOutput?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(DynaQTheme.cyan)
                        .font(.system(size: 10))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("OUT")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                        Text(currentOutput?.name ?? "No Output")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DynaQTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(DynaQTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DynaQTheme.surfaceElevated)
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)

            // Buffer Size Picker
            Menu {
                Section(header: Text("BUFFER FRAME SIZE")) {
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BUFFER")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                        Text("\(bufferSize) spls")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DynaQTheme.textPrimary)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(DynaQTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DynaQTheme.surfaceElevated)
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)

            // Latency Readout Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(latencyMs < 5.0 ? DynaQTheme.green : (latencyMs < 12.0 ? DynaQTheme.amber : DynaQTheme.red))
                    .frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LATENCY")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                    Text(String(format: "%.1f ms", latencyMs))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DynaQTheme.surfaceElevated.opacity(0.8))
            .cornerRadius(5)

            // Feedback Guard Safety Indicator
            Button(action: onToggleFeedbackGuard) {
                HStack(spacing: 4) {
                    Image(systemName: feedbackGuard ? "shield.fill" : "shield.slash")
                        .font(.system(size: 9))
                        .foregroundColor(feedbackGuard ? DynaQTheme.green : DynaQTheme.red)
                    Text("GUARD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(feedbackGuard ? DynaQTheme.textSecondary : DynaQTheme.red)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(feedbackGuard ? DynaQTheme.surfaceElevated.opacity(0.5) : DynaQTheme.red.opacity(0.2))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help(feedbackGuard ? "Feedback Guard Active: Prevents acoustic howl when using built-in mic and speakers." : "Feedback Guard Disabled.")
        }
    }
}
