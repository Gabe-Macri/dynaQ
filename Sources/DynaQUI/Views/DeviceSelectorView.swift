import SwiftUI
import DynaQCore

/// Audio device selection and telemetry header.
public struct DeviceSelectorView: View {
    public let devices: [AudioDevice]
    public let currentDevice: AudioDevice?
    public let onSelectDevice: (AudioDevice) -> Void

    public init(
        devices: [AudioDevice],
        currentDevice: AudioDevice?,
        onSelectDevice: @escaping (AudioDevice) -> Void
    ) {
        self.devices = devices
        self.currentDevice = currentDevice
        self.onSelectDevice = onSelectDevice
    }

    public var body: some View {
        Menu {
            ForEach(devices.filter { $0.isOutput }) { dev in
                Button(action: { onSelectDevice(dev) }) {
                    HStack {
                        Image(systemName: dev.transportType.sfSymbol)
                        Text(dev.name)
                        if dev.id == currentDevice?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: currentDevice?.transportType.sfSymbol ?? "speaker.wave.2")
                    .foregroundColor(DynaQTheme.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentDevice?.name ?? "Default Output")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DynaQTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(Int((currentDevice?.currentSampleRate ?? 48000.0) / 1000.0)) kHz • 24-bit")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(DynaQTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DynaQTheme.surfaceElevated)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

