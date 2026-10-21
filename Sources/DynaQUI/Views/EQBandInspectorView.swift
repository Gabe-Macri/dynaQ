import SwiftUI
import DynaQCore
import DynaQDSP

/// Detailed inspector and editor for the selected equalizer band.
/// Minimal Brutalist Terminal Aesthetic: monospace typography, sharp 1px borders, precision parameter scrubbing.
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
        VStack(spacing: 8) {
            // Band Selection Strip
            HStack(spacing: 4) {
                ForEach(profile.bands.indices, id: \.self) { idx in
                    let band = profile.bands[idx]
                    let isSelected = (band.id == selectedBandID)
                    let bandColor = DynaQTheme.bandColors[idx % DynaQTheme.bandColors.count]

                    Button(action: {
                        selectedBandID = band.id
                    }) {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(band.isEnabled ? bandColor : DynaQTheme.textMuted)
                                .frame(width: 4, height: 10)
                            Text(String(format: "%02d", idx + 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text(band.routing.shortBadge)
                                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                                .foregroundColor(bandColor)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSelected ? DynaQTheme.surfaceElevated : DynaQTheme.surface)
                        .foregroundColor(isSelected ? DynaQTheme.textPrimary : DynaQTheme.textSecondary)
                        .overlay(
                            Rectangle()
                                .stroke(isSelected ? bandColor : DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Add Band button
                Button(action: addBand) {
                    HStack(spacing: 4) {
                        Text("+")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text("BAND")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(DynaQTheme.surface)
                    .foregroundColor(DynaQTheme.textSecondary)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(DynaQTheme.surfaceBorder)
                .frame(height: 1)

            // Inspector Controls for Selected Band
            if let idx = selectedIndex {
                let bandBinding = $profile.bands[idx]
                let band = profile.bands[idx]
                let color = DynaQTheme.bandColors[idx % DynaQTheme.bandColors.count]

                HStack(alignment: .top, spacing: 14) {
                    // Left Column: Filter Shape, Channel Routing, Knobs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            // Filter Type Menu
                            Menu {
                                ForEach(FilterType.allCases) { type in
                                    Button(action: { bandBinding.wrappedValue.filterType = type }) {
                                        Text(type.rawValue.uppercased())
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("TYPE: [ \(band.filterType.shortName.uppercased()) ]")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(color)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 7))
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

                            // Channel Routing (M/S) Menu
                            Menu {
                                ForEach(BandRouting.allCases) { route in
                                    Button(action: { bandBinding.wrappedValue.routing = route }) {
                                        Text(route.rawValue.uppercased())
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("ROUTE: [ \(band.routing.rawValue.uppercased()) ]")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(DynaQTheme.terminalCyan)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 7))
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

                            Spacer()

                            // Solo Toggle
                            Button(action: {
                                bandBinding.wrappedValue.isSolo.toggle()
                            }) {
                                Text("[ SOLO ]")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(band.isSolo ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceElevated)
                                    .foregroundColor(band.isSolo ? .black : DynaQTheme.textMuted)
                                    .overlay(
                                        Rectangle().stroke(band.isSolo ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            // Power/Bypass Toggle
                            Button(action: {
                                bandBinding.wrappedValue.isEnabled.toggle()
                            }) {
                                Text(band.isEnabled ? "[ ON ]" : "[ BYPASS ]")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(band.isEnabled ? color.opacity(0.15) : DynaQTheme.surfaceElevated)
                                    .foregroundColor(band.isEnabled ? color : DynaQTheme.textMuted)
                                    .overlay(
                                        Rectangle().stroke(band.isEnabled ? color : DynaQTheme.surfaceBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            // Delete Band
                            if profile.bands.count > 1 {
                                Button(action: { removeBand(at: idx) }) {
                                    Text("[ DEL ]")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(DynaQTheme.textMuted)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 4)
                                        .background(DynaQTheme.surfaceElevated)
                                        .overlay(
                                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Terminal Precision Knobs
                        HStack(spacing: 8) {
                            RotaryKnob(
                                title: "Frequency",
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
                            Text("// DYNAMIC EQ MODULE")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(band.isDynamic ? DynaQTheme.phosphorAmber : DynaQTheme.textMuted)
                            Spacer()
                            Button(action: {
                                bandBinding.wrappedValue.isDynamic.toggle()
                            }) {
                                Text(band.isDynamic ? "[ ACTIVE ]" : "[ OFF ]")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(band.isDynamic ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceElevated)
                                    .foregroundColor(band.isDynamic ? .black : DynaQTheme.textMuted)
                                    .overlay(
                                        Rectangle().stroke(band.isDynamic ? DynaQTheme.phosphorAmber : DynaQTheme.surfaceBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if band.isDynamic {
                            HStack(spacing: 6) {
                                RotaryKnob(
                                    title: "Threshold",
                                    value: bandBinding.dynamicThreshold,
                                    range: -60...0,
                                    defaultValue: -18.0,
                                    unit: "dB",
                                    tintColor: DynaQTheme.phosphorAmber
                                )
                                RotaryKnob(
                                    title: "Dyn Range",
                                    value: bandBinding.dynamicRange,
                                    range: -18...18,
                                    defaultValue: -6.0,
                                    unit: "dB",
                                    tintColor: DynaQTheme.phosphorAmber
                                )
                                RotaryKnob(
                                    title: "Ratio",
                                    value: bandBinding.dynamicRatio,
                                    range: 1.0...10.0,
                                    defaultValue: 2.0,
                                    unit: ":1",
                                    tintColor: DynaQTheme.phosphorAmber
                                )
                            }
                        } else {
                            Text("Automatic transient gain modulation reacting in real time to peaks above threshold.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(DynaQTheme.textMuted)
                                .padding(.top, 6)
                        }
                    }
                    .padding(8)
                    .background(DynaQTheme.surfaceElevated)
                    .overlay(
                        Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                    )
                    .frame(width: 234)
                }
            }
        }
        .padding(8)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
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
