import SwiftUI
import DynaQCore

/// Per-application routing and volume control panel.
/// Minimal Terminal Style: monospace typography, sharp 1px borders, ASCII-like routing indicators.
public struct AppRoutingView: View {
    @Binding public var routes: [AppAudioRoute]
    public let availableProfiles: [EQProfile]

    public init(routes: Binding<[AppAudioRoute]>, availableProfiles: [EQProfile]) {
        self._routes = routes
        self.availableProfiles = availableProfiles
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("// APP-SPECIFIC STREAM ROUTING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textSecondary)
                Spacer()
                Text("[ \(routes.count) ACTIVE STREAMS ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }

            ForEach(routes.indices, id: \.self) { idx in
                let route = routes[idx]
                HStack(spacing: 8) {
                    Text(route.appName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)

                    // Volume level
                    Slider(value: $routes[idx].volume, in: 0.0...1.5)
                        .tint(DynaQTheme.terminalCyan)
                        .frame(width: 110)

                    Text(String(format: "%3d%%", Int(routes[idx].volume * 100)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textSecondary)
                        .frame(width: 36)

                    // Profile assignment menu
                    Menu {
                        Button("GLOBAL SYSTEM EQ") {
                            routes[idx].assignedProfileId = nil
                        }
                        Divider()
                        ForEach(availableProfiles) { prof in
                            Button(prof.name.uppercased()) {
                                routes[idx].assignedProfileId = prof.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("EQ: [ \(assignedProfileName(for: route)) ]")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(DynaQTheme.terminalCyan)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 6))
                                .foregroundColor(DynaQTheme.textMuted)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DynaQTheme.surfaceElevated)
                        .overlay(
                            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 160)

                    // Mute Button
                    Button(action: {
                        routes[idx].isMuted.toggle()
                    }) {
                        Text(routes[idx].isMuted ? "[ MUTED ]" : "[ MUTE ]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(routes[idx].isMuted ? DynaQTheme.terminalRed : DynaQTheme.surfaceElevated)
                            .foregroundColor(routes[idx].isMuted ? .white : DynaQTheme.textMuted)
                            .overlay(
                                Rectangle().stroke(routes[idx].isMuted ? DynaQTheme.terminalRed : DynaQTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(DynaQTheme.surfaceElevated.opacity(0.4))
                .overlay(
                    Rectangle().stroke(DynaQTheme.surfaceBorder.opacity(0.5), lineWidth: 1)
                )
            }
        }
        .padding(8)
        .background(DynaQTheme.surface)
        .overlay(
            Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func assignedProfileName(for route: AppAudioRoute) -> String {
        guard let id = route.assignedProfileId,
              let found = availableProfiles.first(where: { $0.id == id }) else {
            return "GLOBAL SYSTEM"
        }
        return found.name.uppercased()
    }
}
