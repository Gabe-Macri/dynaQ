import Foundation
import CoreAudio
import DynaQCore

/// Controller for macOS audio tapping (CATapDescription / CoreAudio HAL Loopback Driver).
public final class AudioTapController: @unchecked Sendable {
    public static let shared = AudioTapController()

    public enum CaptureMode: String, CaseIterable, Sendable {
        case virtualDriverLoopback = "Virtual Audio Device (HAL Driver)"
        case processTap = "System Process Tap (macOS 14.2+)"
        case standardInput = "CoreAudio Hardware Input"
    }

    public var currentMode: CaptureMode = .virtualDriverLoopback

    public init() {}

    /// Checks whether the dynaQ Virtual Audio Driver is installed in /Library/Audio/Plug-Ins/HAL.
    public func isVirtualDriverInstalled() -> Bool {
        let driverPath = "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver"
        return FileManager.default.fileExists(atPath: driverPath)
    }

    /// Returns recommended setup instructions depending on the detected environment.
    public func driverStatusMessage() -> String {
        if isVirtualDriverInstalled() {
            return "dynaQ Virtual Audio Driver is installed and active."
        } else {
            return "Virtual Driver not found. Using low-latency Hardware Tap mode. To enable transparent system-wide output interception, install the dynaQ HAL driver via 'scripts/install_driver.sh'."
        }
    }
}

