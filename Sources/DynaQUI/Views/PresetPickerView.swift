import SwiftUI
import DynaQCore

/// Terminal Preset Browser and Manager.
/// Brutalist aesthetic: monospace typography, sharp 1px borders, compact preset navigation.
public struct PresetPickerView: View {
    @Binding public var currentProfile: EQProfile
    public let presets: [EQProfile]
    public let onSelectPreset: (EQProfile) -> Void
    public let onSaveCustom: (String) -> Void

    @State private var showingSaveSheet = false
    @State private var customPresetName = ""

    public init(
        currentProfile: Binding<EQProfile>,
        presets: [EQProfile],
        onSelectPreset: @escaping (EQProfile) -> Void,
        onSaveCustom: @escaping (String) -> Void
    ) {
        self._currentProfile = currentProfile
        self.presets = presets
        self.onSelectPreset = onSelectPreset
        self.onSaveCustom = onSaveCustom
    }

    public var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(Dictionary(grouping: presets, by: { $0.category }).sorted(by: { $0.key < $1.key }), id: \.key) { category, items in
                    Section(header: Text(category.uppercased())) {
                        ForEach(items) { preset in
                            Button(action: {
                                onSelectPreset(preset)
                            }) {
                                HStack {
                                    Text(preset.name)
                                    if preset.id == currentProfile.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("PRESET:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)

                    Text("[ \(currentProfile.name) ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)

                    Text(currentProfile.category.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.terminalCyan)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(DynaQTheme.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DynaQTheme.surfaceElevated)
                .overlay(
                    Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)

            // Save Preset Button
            Button(action: {
                customPresetName = "\(currentProfile.name) (Custom)"
                showingSaveSheet = true
            }) {
                Text("[ SAVE ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(DynaQTheme.surfaceElevated)
                    .foregroundColor(DynaQTheme.textSecondary)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSaveSheet) {
                VStack(spacing: 10) {
                    Text("// SAVE CUSTOM PRESET")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)

                    TextField("Preset Name", text: $customPresetName)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(DynaQTheme.surface)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 220)

                    HStack(spacing: 8) {
                        Button("[ CANCEL ]") {
                            showingSaveSheet = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textMuted)

                        Spacer()

                        Button("[ CONFIRM SAVE ]") {
                            onSaveCustom(customPresetName)
                            showingSaveSheet = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.phosphorGreen)
                    }
                }
                .padding(12)
                .background(DynaQTheme.surfaceElevated)
            }
        }
    }
}
