import SwiftUI
import DynaQCore
import DynaQDSP

/// Detailed inspector and editor for the selected equalizer band.
public struct EQBandInspectorView: View {
    @Binding public var profile: EQProfile
    @Binding public var selectedBandID: UUID?

    public init(profile: Binding<EQProfile>, selectedBandID: Binding<UUID?>) {
        self._profile = profile
        self._selectedBandID = selectedBandID
    }

    private var selectedIndex: Int? {
        profile.bands.firstIndex(where: { $0.id == selectedBandID })
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Band Selection Strip
            HStack(spacing: 6) {
                ForEach(profile.bands.indices, id: \.self) { idx in
                    let band = profile.bands[idx]
                    let isSelected = (band.id == selectedBandID)
                    let bandColor = DynaQTheme.bandColors[idx % DynaQTheme.bandColors.count]

                    Button(action: {
                        selectedBandID = band.id
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(band.isEnabled ? bandColor : DynaQTheme.textMuted)
                                .frame(width: 6, height: 6)
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(band.routing.shortBadge)
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(bandColor.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? DynaQTheme.surfaceElevated : DynaQTheme.surface)
                        .foregroundColor(isSelected ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? bandColor : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Add Band button
                Button(action: addBand) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("BAND")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DynaQTheme.surface)
                    .foregroundColor(DynaQTheme.textSecondary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider().background(DynaQTheme.surfaceBorder)

            // Inspector Controls for Selected Band
            if let idx = selectedIndex {
                let bandBinding = $profile.bands[idx]
                let band = profile.bands[idx]
                let color = DynaQTheme.bandColors[idx % DynaQTheme.bandColors.count]

                HStack(alignment: .top, spacing: 18) {
                    // Left Column: Filter Shape & Channel Routing
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            // Filter Type Menu
                            Menu {
                                ForEach(FilterType.allCases) { type in
                                    Button(action: { bandBinding.wrappedValue.filterType = type }) {
                                        Label(type.rawValue, systemImage: type.sfSymbol)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: band.filterType.sfSymbol)
                                        .foregroundColor(color)
                                    Text(band.filterType.shortName)
                                        .font(.system(size: 11, weight: .semibold))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(DynaQTheme.surface)
                                .cornerRadius(5)
                            }
                            .menuStyle(.borderlessButton)

                            // Channel Routing (M/S) Menu
                            Menu {
                                ForEach(BandRouting.allCases) { route in
                                    Button(action: { bandBinding.wrappedValue.routing = route }) {
                                        Text(route.rawValue)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(band.routing.rawValue)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(DynaQTheme.cyan)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(DynaQTheme.surface)
                                .cornerRadius(5)
                            }
                            .menuStyle(.borderlessButton)

                            Spacer()

                            // Solo Toggle
                            Button(action: {
                                bandBinding.wrappedValue.isSolo.toggle()
                            }) {
                                Text("SOLO")
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(band.isSolo ? DynaQTheme.amber : DynaQTheme.surface)
                                    .foregroundColor(band.isSolo ? .black : DynaQTheme.textSecondary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)

                            // Power Toggle
                            Toggle("", isOn: bandBinding.isEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: color))
                                .labelsHidden()

                            // Delete Band
                            if profile.bands.count > 1 {
                                Button(action: { removeBand(at: idx) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(DynaQTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Knobs with numeric readouts
                        HStack(spacing: 16) {
                            RotaryKnob(
                                title: "Freq",
                                value: bandBinding.frequency,
                                range: 20...20000,
                                defaultValue: 1000.0,
                                unit: "Hz",
                                tintColor: color
                            )

                            if band.filterType.supportsGain {
                                RotaryKnob(
                                    title: "Gain",
                                    value: bandBinding.gain,
                                    range: -24...24,
                                    defaultValue: 0.0,
                                    unit: "dB",
                                    tintColor: color
                                )
                            }

                            RotaryKnob(
                                title: "Q Factor",
                                value: bandBinding.q,
                                range: 0.1...18.0,
                                defaultValue: 1.414,
                                unit: "",
                                tintColor: color
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Column: Dynamic EQ Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .foregroundColor(band.isDynamic ? DynaQTheme.amber : DynaQTheme.textMuted)
                                .font(.system(size: 10))
                            Text("DYNAMIC EQ")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(band.isDynamic ? DynaQTheme.textPrimary : DynaQTheme.textMuted)
                            Spacer()
                            Toggle("", isOn: bandBinding.isDynamic)
                                .toggleStyle(SwitchToggleStyle(tint: DynaQTheme.amber))
                                .labelsHidden()
                        }

                        if band.isDynamic {
                            HStack(spacing: 10) {
                                RotaryKnob(
                                    title: "Thresh",
                                    value: bandBinding.dynamicThreshold,
                                    range: -60...0,
                                    defaultValue: -18.0,
                                    unit: "dB",
                                    tintColor: DynaQTheme.amber
                                )
                                RotaryKnob(
                                    title: "Range",
                                    value: bandBinding.dynamicRange,
                                    range: -18...18,
                                    defaultValue: -6.0,
                                    unit: "dB",
                                    tintColor: DynaQTheme.amber
                                )
                                RotaryKnob(
                                    title: "Ratio",
                                    value: bandBinding.dynamicRatio,
                                    range: 1.0...10.0,
                                    defaultValue: 2.0,
                                    unit: ":1",
                                    tintColor: DynaQTheme.amber
                                )
                            }
                        } else {
                            Text("Automatic gain modulation reacting to audio transients above threshold.")
                                .font(.system(size: 10))
                                .foregroundColor(DynaQTheme.textMuted)
                                .padding(.top, 4)
                        }
                    }
                    .padding(8)
                    .background(DynaQTheme.surfaceElevated.opacity(0.6))
                    .cornerRadius(7)
                    .frame(width: 240)
                }
            }
        }
        .padding(12)
        .background(DynaQTheme.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func addBand() {
        let newIndex = profile.bands.count
        let newBand = EQBand(
            index: newIndex,
            frequency: 1000.0,
            gain: 0.0,
            q: 1.414,
            filterType: .bell,
            routing: .stereo
        )
        profile.bands.append(newBand)
        selectedBandID = newBand.id
    }

    private func removeBand(at index: Int) {
        guard profile.bands.count > 1 else { return }
        profile.bands.remove(at: index)
        for i in 0..<profile.bands.count {
            profile.bands[i].index = i
        }
        selectedBandID = profile.bands.first?.id
    }
}
