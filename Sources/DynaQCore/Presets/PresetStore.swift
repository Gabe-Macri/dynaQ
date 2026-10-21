import Foundation

/// Manages loading and saving EQ presets to disk.
public final class PresetStore: @unchecked Sendable {
    public static let shared = PresetStore()

    private let fileManager = FileManager.default
    private let presetsDirectory: URL

    public init() {
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.presetsDirectory = appSupport.appendingPathComponent("dynaQ/Presets", isDirectory: true)
        } else {
            self.presetsDirectory = fileManager.temporaryDirectory.appendingPathComponent("dynaQ/Presets", isDirectory: true)
        }
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        try? fileManager.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
    }

    /// Returns all available presets (factory + user saved).
    public func loadAllProfiles() -> [EQProfile] {
        var profiles = DefaultPresets.all

        guard let files = try? fileManager.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil) else {
            return profiles
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? decoder.decode(EQProfile.self, from: data) {
                // Do not override factory presets with the same ID
                if !profiles.contains(where: { $0.id == profile.id }) {
                    profiles.append(profile)
                }
            }
        }

        return profiles
    }

    /// Saves a custom preset to disk.
    public func saveProfile(_ profile: EQProfile) throws {
        createDirectoryIfNeeded()
        let fileURL = presetsDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        try data.write(to: fileURL)
    }

    /// Deletes a custom preset from disk.
    public func deleteProfile(id: UUID) throws {
        let fileURL = presetsDirectory.appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}

