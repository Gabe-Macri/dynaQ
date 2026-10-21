import SwiftUI
import Combine
import DynaQCore
import DynaQDSP
import DynaQAudioDriver

public enum ComparisonSlot: String, CaseIterable, Sendable {
    case slotA = "A"
    case slotB = "B"
}

/// Global Application State coordinating DSP Engine, UI, and System Audio I/O.
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // A/B Comparison States
    @Published public var activeSlot: ComparisonSlot = .slotA
    @Published public var profileA: EQProfile
    @Published public var profileB: EQProfile

    // Active Profile (reflects active slot A or B)
    public var currentProfile: EQProfile {
        get { activeSlot == .slotA ? profileA : profileB }
        set {
            if activeSlot == .slotA {
                profileA = newValue
            } else {
                profileB = newValue
            }
            syncProfileToEngine(newValue)
        }
    }

    @Published public var presets: [EQProfile] = []
    @Published public var selectedBandID: UUID?

    // Audio Hardware I/O & Latency
    @Published public var devices: [AudioDevice] = []
    @Published public var selectedInputDevice: AudioDevice?
    @Published public var selectedOutputDevice: AudioDevice?
    @Published public var selectedBufferSize: UInt32 = 256
    @Published public var roundtripLatencyMs: Double = 0.0
    @Published public var feedbackProtection: Bool = true {
        didSet {
            engineManager.feedbackProtectionEnabled = feedbackProtection
        }
    }

    // Per-App Routing
    @Published public var appRoutes: [AppAudioRoute] = []

    // Real-Time DSP Telemetry
    @Published public var currentMeter: AudioMeter = .silent
    @Published public var spectrumDB: [Float] = []

    // Engine status
    @Published public var isEngineOnline: Bool = false
    @Published public var statusMessage: String = "Initializing..."

    private let engineManager = AudioEngineManager.shared
    private let coreAudioManager = CoreAudioManager.shared
    private let presetStore = PresetStore.shared

    public init() {
        let loadedPresets = presetStore.loadAllProfiles()
        self.presets = loadedPresets
        let initial = loadedPresets.first ?? DefaultPresets.studioFlat

        self.profileA = initial
        self.profileB = initial.duplicate(newName: "\(initial.name) (B)")
        self.selectedBandID = initial.bands.first?.id

        self.appRoutes = [
            AppAudioRoute(bundleIdentifier: "com.spotify.client", appName: "Spotify", volume: 1.0),
            AppAudioRoute(bundleIdentifier: "com.apple.Music", appName: "Apple Music", volume: 1.0),
            AppAudioRoute(bundleIdentifier: "com.apple.logic10", appName: "Logic Pro", volume: 1.0),
            AppAudioRoute(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", volume: 0.85)
        ]

        setupAudioEngineBindings()
        refreshHardwareDevices()
        startLiveSystemAudio()
    }

    private func setupAudioEngineBindings() {
        engineManager.onMeterUpdate = { [weak self] meter in
            DispatchQueue.main.async {
                self?.currentMeter = meter
            }
        }

        engineManager.onSpectrumUpdate = { [weak self] spectrum in
            DispatchQueue.main.async {
                self?.spectrumDB = spectrum
            }
        }

        engineManager.onLatencyUpdate = { [weak self] lat in
            DispatchQueue.main.async {
                self?.roundtripLatencyMs = lat
            }
        }

        coreAudioManager.onDevicesChanged = { [weak self] devs in
            DispatchQueue.main.async {
                self?.devices = devs
            }
        }

        coreAudioManager.onDefaultOutputChanged = { [weak self] dev in
            DispatchQueue.main.async {
                guard let self = self, let d = dev else { return }
                if self.selectedOutputDevice == nil || self.selectedOutputDevice?.id != d.id {
                    self.selectedOutputDevice = d
                    try? self.engineManager.switchOutputDevice(id: d.id)
                }
            }
        }

        coreAudioManager.onDefaultInputChanged = { [weak self] dev in
            DispatchQueue.main.async {
                guard let self = self, let d = dev else { return }
                if self.selectedInputDevice == nil || self.selectedInputDevice?.id != d.id {
                    self.selectedInputDevice = d
                    try? self.engineManager.switchInputDevice(id: d.id)
                }
            }
        }
    }

    public func refreshHardwareDevices() {
        self.devices = coreAudioManager.fetchAllDevices()
        let defOutID = coreAudioManager.getDefaultOutputDeviceID()
        let defInID = coreAudioManager.getDefaultInputDeviceID()
        self.selectedOutputDevice = devices.first(where: { $0.id == defOutID })
        self.selectedInputDevice = devices.first(where: { $0.id == defInID })
    }

    public func startLiveSystemAudio() {
        do {
            let inID = selectedInputDevice?.id ?? coreAudioManager.getDefaultInputDeviceID()
            let outID = selectedOutputDevice?.id ?? coreAudioManager.getDefaultOutputDeviceID()
            try engineManager.start(inputDeviceID: inID, outputDeviceID: outID)
            isEngineOnline = true
            statusMessage = "DSP Engine Online"
        } catch {
            isEngineOnline = false
            statusMessage = "Audio I/O Error: \(error.localizedDescription)"
        }
    }

    public func stopLiveSystemAudio() {
        engineManager.stop()
        isEngineOnline = false
        statusMessage = "DSP Engine Standby"
    }

    public func toggleEnginePower() {
        if isEngineOnline {
            stopLiveSystemAudio()
        } else {
            startLiveSystemAudio()
        }
    }

    public func setInputDevice(_ device: AudioDevice) {
        self.selectedInputDevice = device
        try? engineManager.switchInputDevice(id: device.id)
    }

    public func setOutputDevice(_ device: AudioDevice) {
        self.selectedOutputDevice = device
        try? engineManager.switchOutputDevice(id: device.id)
    }

    public func setBufferSize(_ size: UInt32) {
        self.selectedBufferSize = size
        engineManager.setBufferFrameSize(size)
    }

    // MARK: - A / B Comparison

    public func switchToSlot(_ slot: ComparisonSlot) {
        activeSlot = slot
        syncProfileToEngine(currentProfile)
    }

    public func copyActiveSlotToInactive() {
        if activeSlot == .slotA {
            profileB = profileA.duplicate(newName: "\(profileA.name) (B)")
        } else {
            profileA = profileB.duplicate(newName: "\(profileB.name) (A)")
        }
    }

    public func selectPreset(_ preset: EQProfile) {
        if activeSlot == .slotA {
            profileA = preset
        } else {
            profileB = preset
        }
        selectedBandID = preset.bands.first?.id
        syncProfileToEngine(preset)
    }

    public func saveCustomPreset(name: String) {
        var copy = currentProfile.duplicate(newName: name)
        copy.isFactory = false
        try? presetStore.saveProfile(copy)
        presets.append(copy)
        selectPreset(copy)
    }

    public func resetClip() {
        engineManager.loudnessMeter.resetClip()
        currentMeter.isClippingLeft = false
        currentMeter.isClippingRight = false
    }

    private func syncProfileToEngine(_ profile: EQProfile) {
        engineManager.eqEngine.setProfile(profile)
        engineManager.limiter.ceilingDB = profile.limiterCeiling
        engineManager.limiter.isEnabled = profile.isLimiterEnabled
    }
}
