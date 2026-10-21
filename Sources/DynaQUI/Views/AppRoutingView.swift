import SwiftUI
import DynaQCore

/// Per-application routing and volume control panel.
public struct AppRoutingView: View {
    @Binding public var routes: [AppAudioRoute]
    public let availableProfiles: [EQProfile]

    public init(routes: Binding<[AppAudioRoute]>, availableProfiles: [EQProfile]) {
        self._routes = routes
        self.availableProfiles = availableProfiles
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.stack.3d.forward.dottedline")
                    .foregroundColor(DynaQTheme.cyan)
                Text("APP-SPECIFIC ROUTING & EQUALIZATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textSecondary)
                Spacer()
                Text("\(routes.count) Active Streams")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted)
            }

            ForEach(routes.indices, id: \.self) { idx in
                let route = routes[idx]
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .foregroundColor(DynaQTheme.cyan)
                        .frame(width: 20)

                    Text(route.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DynaQTheme.textPrimary)
                        .frame(width: 140, alignment: .leading)

                    // Volume slider
                    Slider(value: $routes[idx].volume, in: 0.0...1.5)
                        .tint(DynaQTheme.cyan)
                        .frame(width: 120)

                    Text("\(Int(routes[idx].volume * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DynaQTheme.textSecondary)
                        .frame(width: 40)

                    // Profile assignment menu
                    Menu {
                        Button("Global System EQ") {
                            routes[idx].assignedProfileId = nil
                        }
                        Divider()
                        ForEach(availableProfiles) { prof in
                            Button(prof.name) {
                                routes[idx].assignedProfileId = prof.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(assignedProfileName(for: route))
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DynaQTheme.surfaceElevated)
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 150)

                    // Mute Button
                    Button(action: {
                        routes[idx].isMuted.toggle()
                    }) {
                        Image(systemName: routes[idx].isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundColor(routes[idx].isMuted ? DynaQTheme.red : DynaQTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DynaQTheme.surfaceElevated.opacity(0.4))
                .cornerRadius(6)
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

    private func assignedProfileName(for route: AppAudioRoute) -> String {
        guard let id = route.assignedProfileId,
              let found = availableProfiles.first(where: { $0.id == id }) else {
            return "System Curve"
        }
        return found.name
    }
}
