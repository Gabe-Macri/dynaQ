import Foundation

/// Per-application audio routing configuration.
public struct AppAudioRoute: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var appName: String
    public var processIdentifier: Int32?
    public var volume: Float             // 0.0 to 1.5 (0% to 150%)
    public var isMuted: Bool
    public var isBypassed: Bool
    public var assignedProfileId: UUID?   // Custom EQ preset for this specific app

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        processIdentifier: Int32? = nil,
        volume: Float = 1.0,
        isMuted: Bool = false,
        isBypassed: Bool = false,
        assignedProfileId: UUID? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.processIdentifier = processIdentifier
        self.volume = volume
        self.isMuted = isMuted
        self.isBypassed = isBypassed
        self.assignedProfileId = assignedProfileId
    }
}
