import SwiftUI
import Combine
import DynaQCore
import DynaQDSP
import DynaQAudioDriver

/// Global Application State coordinating DSP Engine, UI, and Audio Drivers.
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // Active Configuration
    @Published public var currentProfile: EQProfile {
        didSet {
            engineManager.eqEngine.setProfile(currentProfile)
            engineManager.limiter.ceilingDB = currentProfile.limiterCeiling
            engineManager.limiter.isEnabled = currentProfile.isLimiterEnabled
        }
    }
    @Published public var presets: [EQProfile] = []
    @Published public var selectedBandID: UUID?

    // Audio Devices & Routing
    @Published public var devices: [AudioDevice] = []
    @Published public var currentDevice: AudioDevice?
    @Published public var appRoutes: [AppAudioRoute] = []

    // Real-Time DSP Telemetry
    @Published public var currentMeter: AudioMeter = .silent
    @Published public var spectrumDB: [Float] = []

    // Engine status & Simulated Generator
    @Published public var isEngineRunning: Bool = false
    @Published public var isDemoAudioRunning: Bool = false
    @Published public var statusMessage: String = "Ready"

    private let engineManager = AudioEngineManager.shared
    private let coreAudioManager = CoreAudioManager.shared
    private let presetStore = PresetStore.shared
    private var demoTimer: Timer?

    public init() {
        let loadedPresets = presetStore.loadAllProfiles()
        self.presets = loadedPresets
        let initial = loadedPresets.first ?? DefaultPresets.studioFlat
        self.currentProfile = initial
        self.selectedBandID = initial.bands.first?.id

        // Populate sample app routes
        self.appRoutes = [
            AppAudioRoute(bundleIdentifier: "com.spotify.client", appName: "Spotify", volume: 1.0),
            AppAudioRoute(bundleIdentifier: "com.apple.Music", appName: "Apple Music", volume: 1.0),
            AppAudioRoute(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", volume: 0.9),
            AppAudioRoute(bundleIdentifier: "com.apple.logic10", appName: "Logic Pro", volume: 1.0)
        ]

        setupAudioEngineBindings()
        loadDevices()
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

        coreAudioManager.onDevicesChanged = { [weak self] devs in
            DispatchQueue.main.async {
                self?.devices = devs
            }
        }

        coreAudioManager.onDefaultOutputChanged = { [weak self] dev in
            DispatchQueue.main.async {
                self?.currentDevice = dev
            }
        }
    }

    public func loadDevices() {
        self.devices = coreAudioManager.fetchAllDevices()
        let defOutID = coreAudioManager.getDefaultOutputDeviceID()
        self.currentDevice = devices.first(where: { $0.id == defOutID })
    }

    public func startEngine() {
        do {
            try engineManager.start()
            isEngineRunning = true
            statusMessage = "DSP Engine Running"
        } catch {
            statusMessage = "Engine startup: \(error.localizedDescription)"
        }
    }

    public func stopEngine() {
        engineManager.stop()
        isEngineRunning = false
        statusMessage = "DSP Engine Stopped"
    }

    public func toggleDemoAudio() {
        if isDemoAudioRunning {
            demoTimer?.invalidate()
            demoTimer = nil
            isDemoAudioRunning = false
            currentMeter = .silent
            spectrumDB = [Float](repeating: -80.0, count: 64)
            statusMessage = "Demo Tone Stopped"
        } else {
            isDemoAudioRunning = true
            statusMessage = "Generating Pink Tone & Harmonics"
            // Start 60fps synthesized generator to exercise the EQ & spectrum analyzer
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.engineManager.processSimulatedBuffer(frequency: 440.0)
                let spec = self.engineManager.analyzer.getSpectrumDB()
                DispatchQueue.main.async {
                    self.spectrumDB = spec
                }
            }
        }
    }

    public func selectPreset(_ preset: EQProfile) {
        self.currentProfile = preset
        self.selectedBandID = preset.bands.first?.id
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
}
