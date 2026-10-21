import SwiftUI
import DynaQCore

/// Preset browser and manager.
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
        HStack(spacing: 12) {
            Menu {
                ForEach(Dictionary(grouping: presets, by: { $0.category }).sorted(by: { $0.key < $1.key }), id: \.key) { category, items in
                    Section(header: Text(category)) {
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
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(DynaQTheme.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(currentProfile.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DynaQTheme.textPrimary)
                        Text(currentProfile.category.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(DynaQTheme.textMuted)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(DynaQTheme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DynaQTheme.surfaceElevated)
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)

            // Save Preset Button
            Button(action: {
                customPresetName = "\(currentProfile.name) (Custom)"
                showingSaveSheet = true
            }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
                    .padding(8)
                    .background(DynaQTheme.surfaceElevated)
                    .foregroundColor(DynaQTheme.textSecondary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSaveSheet) {
                VStack(spacing: 12) {
                    Text("Save Custom Preset")
                        .font(.headline)
                        .foregroundColor(DynaQTheme.textPrimary)

                    TextField("Preset Name", text: $customPresetName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 220)

                    HStack {
                        Button("Cancel") {
                            showingSaveSheet = false
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("Save") {
                            onSaveCustom(customPresetName)
                            showingSaveSheet = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
                .background(DynaQTheme.surface)
            }
        }
    }
}

