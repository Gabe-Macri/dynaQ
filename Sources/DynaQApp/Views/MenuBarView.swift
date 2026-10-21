import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQUI

/// Compact Menu Bar view for quick status and preset switching.
public struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    public let onOpenMainWindow: () -> Void

    public init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("dynaQ")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(DynaQTheme.cyan)
                Spacer()
                Text(state.currentProfile.isBypassed ? "BYPASS" : "ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.currentProfile.isBypassed ? DynaQTheme.red : DynaQTheme.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }

            Divider().background(DynaQTheme.surfaceBorder)

            // Current Device
            HStack {
                Image(systemName: state.currentDevice?.transportType.sfSymbol ?? "speaker.wave.2")
                    .foregroundColor(DynaQTheme.cyan)
                Text(state.currentDevice?.name ?? "Default Output")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }

            // Quick Preset Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVE PRESET")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)

                ForEach(state.presets.prefix(4)) { preset in
                    Button(action: {
                        state.selectPreset(preset)
                    }) {
                        HStack {
                            Text(preset.name)
                                .font(.system(size: 11))
                            Spacer()
                            if preset.id == state.currentProfile.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(DynaQTheme.cyan)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(preset.id == state.currentProfile.id ? DynaQTheme.surfaceElevated : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(DynaQTheme.surfaceBorder)

            // Actions
            HStack {
                Button("Open Studio UI") {
                    onOpenMainWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(DynaQTheme.textMuted)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(DynaQTheme.bg)
    }
}

