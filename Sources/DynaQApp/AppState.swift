import SwiftUI
import Combine
import CoreAudio
import DynaQCore
import DynaQDSP
import DynaQDynamics
import DynaQAnalysis
import DynaQAudioDriver

public enum ComparisonSlot: String, CaseIterable, Sendable {
    case slotA = "A"
    case slotB = "B"
}

/// Monospace Diagnostic Log Entry for live engine and hardware telemetry.
public struct DiagnosticLog: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: String
    public let level: String // "INFO", "WARN", "ERR", "DSP"
    public let message: String

    public init(timestamp: String, level: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
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

    // Audio Hardware I/O & Routing Mode
    @Published public var captureSource: AudioCaptureSource = .systemAudio
    @Published public var devices: [AudioDevice] = []
    @Published public var availableAudioApps: [AudioAppProcess] = []
    @Published public var selectedAudioApp: AudioAppProcess? = nil
    @Published public var tapAllProcesses: Bool = true

    @Published public var selectedInputDevice: AudioDevice?
    @Published public var selectedOutputDevice: AudioDevice?
    @Published public var selectedBufferSize: UInt32 = 256
    @Published public var roundtripLatencyMs: Double = 0.0
    @Published public var feedbackProtection: Bool = true {
        didSet {
            engineManager.feedbackProtectionEnabled = feedbackProtection
            logDiagnostic(level: "INFO", message: "Feedback protection \(feedbackProtection ? "ENABLED" : "DISABLED")")
        }
    }
    @Published public var isLiveMode: Bool = false {
        didSet {
            currentProfile.isLiveMode = isLiveMode
            dspPipeline.limiter.isLiveMode = isLiveMode
            logDiagnostic(level: "DSP", message: "Zero-Latency Live Tracking Mode \(isLiveMode ? "ENABLED (0ms delay for DAW)" : "DISABLED (Mastering True Peak)")")
        }
    }

    // Modal & Error Handling States
    @Published public var showSettingsModal: Bool = false
    @Published public var activeErrorMessage: String? = nil
    @Published public var diagnosticLogs: [DiagnosticLog] = []

    // Per-App Routing
    @Published public var appRoutes: [AppAudioRoute] = []

    // Real-Time DSP Telemetry
    @Published public var currentMeter: AudioMeter = .silent
    @Published public var spectrumDB: [Float] = []

    // Engine status
    @Published public var isEngineOnline: Bool = false
    @Published public var statusMessage: String = "Initializing..."

    public var underrunCount: Int {
        engineManager.underrunCount
    }

    private let engineManager = AudioEngineManager.shared
    private let coreAudioManager = CoreAudioManager.shared
    private let presetStore = PresetStore.shared

    // Client-side DSP pipeline for heavy audio manipulations (EQ, dynamics, limiting, FFT)
    public let dspPipeline: ClientDSPPipeline

    public init() {
        let loadedPresets = presetStore.loadAllProfiles()
        self.presets = loadedPresets
        let initial = loadedPresets.first ?? DefaultPresets.harmanHeadphoneTarget

        self.profileA = initial
        self.profileB = initial.duplicate(newName: "\(initial.name) (B)")
        self.selectedBandID = initial.bands.first?.id

        let coreAudio = CoreAudioManager.shared
        let defOutRate = Float(coreAudio.fetchAllDevices().first(where: { $0.id == coreAudio.getDefaultOutputDeviceID() })?.currentSampleRate ?? 48000.0)
        self.dspPipeline = ClientDSPPipeline(initialProfile: initial, sampleRate: defOutRate)
        self.engineManager.client = dspPipeline

        self.appRoutes = []

        setupAudioEngineBindings()
        refreshHardwareDevices()
        refreshAudioApps()
        startLiveSystemAudio()
    }

    public func logDiagnostic(level: String, message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let ts = formatter.string(from: Date())
        let entry = DiagnosticLog(timestamp: ts, level: level, message: message)
        DispatchQueue.main.async {
            self.diagnosticLogs.append(entry)
            if self.diagnosticLogs.count > 120 {
                self.diagnosticLogs.removeFirst(self.diagnosticLogs.count - 120)
            }
        }
    }

    public func clearDiagnosticLogs() {
        diagnosticLogs.removeAll()
    }

    public func dismissError() {
        activeErrorMessage = nil
    }

    private func setupAudioEngineBindings() {
        dspPipeline.onMeterUpdate = { [weak self] meter in
            self?.currentMeter = meter
        }

        dspPipeline.onSpectrumUpdate = { [weak self] spectrum in
            self?.spectrumDB = spectrum
        }

        engineManager.onLatencyUpdate = { [weak self] lat in
            self?.roundtripLatencyMs = lat
        }

        engineManager.onError = { [weak self] err in
            DispatchQueue.main.async {
                self?.activeErrorMessage = err.localizedDescription
                self?.logDiagnostic(level: "ERR", message: err.localizedDescription)
            }
        }

        coreAudioManager.onDevicesChanged = { [weak self] devs in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.devices = devs
                self.logDiagnostic(level: "INFO", message: "Audio devices updated (\(devs.count) devices found)")

                // Auto-fallback if active output was unplugged
                if let currentOut = self.selectedOutputDevice, !devs.contains(where: { $0.id == currentOut.id }) {
                    self.logDiagnostic(level: "WARN", message: "Output device #\(currentOut.id) disconnected. Falling back to default output...")
                    let defOutID = self.coreAudioManager.getDefaultOutputDeviceID()
                    if let defDev = devs.first(where: { $0.id == defOutID }) {
                        self.selectedOutputDevice = defDev
                        do {
                            try self.engineManager.switchOutputDevice(id: defDev.id)
                            self.activeErrorMessage = nil
                        } catch {
                            self.activeErrorMessage = "Auto-recovery failed: \(error.localizedDescription)"
                            self.logDiagnostic(level: "ERR", message: "Recovery output switch failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        coreAudioManager.onDefaultOutputChanged = { [weak self] dev in
            DispatchQueue.main.async {
                guard let self = self, let d = dev else { return }
                if self.selectedOutputDevice == nil || self.selectedOutputDevice?.id != d.id {
                    self.selectedOutputDevice = d
                    self.logDiagnostic(level: "INFO", message: "Default output changed to \(d.name) (#\(d.id))")
                    do {
                        try self.engineManager.switchOutputDevice(id: d.id)
                        self.activeErrorMessage = nil
                    } catch {
                        self.activeErrorMessage = "Switch to \(d.name) failed: \(error.localizedDescription)"
                        self.logDiagnostic(level: "ERR", message: "Switch to \(d.name) failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        coreAudioManager.onDefaultInputChanged = { [weak self] dev in
            DispatchQueue.main.async {
                guard let self = self, let d = dev else { return }
                if self.selectedInputDevice == nil || self.selectedInputDevice?.id != d.id {
                    self.selectedInputDevice = d
                    self.logDiagnostic(level: "INFO", message: "Default input changed to \(d.name) (#\(d.id))")
                    try? self.engineManager.switchInputDevice(id: d.id)
                }
            }
        }

        // IPC Server for Python Backend SDK & External Automation
        IPCServer.shared.commandHandler = { [weak self] cmd, params in
            guard let self = self else { return nil }
            switch cmd {
            case "ping":
                return ["status": "ok", "version": "1.0.0-beta.2"]
            case "get_status":
                let profile = self.currentProfile
                let bandsDict: [[String: Any]] = profile.bands.map { b in
                    [
                        "index": b.index,
                        "frequency": b.frequency,
                        "gain": b.gain,
                        "q": b.q,
                        "type": b.filterType.rawValue,
                        "enabled": b.isEnabled,
                        "is_fm_enabled": b.isFMEnabled,
                        "fm_mode": b.fmMode.rawValue,
                        "fm_depth": b.fmDepth,
                        "fm_rate": b.fmRate
                    ]
                }
                return [
                    "status": "online",
                    "sample_rate": self.engineManager.currentSampleRate,
                    "buffer_frames": self.selectedBufferSize,
                    "latency_ms": self.roundtripLatencyMs,
                    "capture_source": self.captureSource.rawValue,
                    "master_gain_db": profile.masterGain,
                    "is_live_mode": self.isLiveMode,
                    "limiter": [
                        "enabled": profile.isLimiterEnabled,
                        "ceiling_db": profile.limiterCeiling,
                        "is_live_mode": profile.isLiveMode
                    ],
                    "bands": bandsDict
                ]
            case "get_telemetry":
                return [
                    "status": "ok",
                    "peak_left_db": self.currentMeter.peakLeft,
                    "peak_right_db": self.currentMeter.peakRight,
                    "lufs_integrated": self.currentMeter.rmsLeft,
                    "correlation": 0.95,
                    "spectrum_64": self.spectrumDB
                ]
            case "set_band":
                guard let idx = params["index"] as? Int, idx >= 0, idx < self.currentProfile.bands.count else {
                    return ["status": "error", "message": "Invalid band index"]
                }
                DispatchQueue.main.async {
                    if let f = params["frequency"] as? Double {
                        self.currentProfile.bands[idx].frequency = Float(f)
                    }
                    if let g = params["gain"] as? Double {
                        self.currentProfile.bands[idx].gain = Float(g)
                    }
                    if let q = params["q"] as? Double {
                        self.currentProfile.bands[idx].q = Float(q)
                    }
                    if let en = params["is_enabled"] as? Bool {
                        self.currentProfile.bands[idx].isEnabled = en
                    }
                    if let fm = params["is_fm_enabled"] as? Bool {
                        self.currentProfile.bands[idx].isFMEnabled = fm
                    }
                    if let depth = params["fm_depth"] as? Double {
                        self.currentProfile.bands[idx].fmDepth = Float(depth)
                    }
                    if let rate = params["fm_rate"] as? Double {
                        self.currentProfile.bands[idx].fmRate = Float(rate)
                    }
                    self.syncProfileToEngine(self.currentProfile)
                }
                return ["status": "ok"]
            case "set_master_gain":
                if let g = params["gain_db"] as? Double {
                    DispatchQueue.main.async {
                        self.currentProfile.masterGain = Float(g)
                        self.syncProfileToEngine(self.currentProfile)
                    }
                }
                return ["status": "ok"]
            case "set_limiter":
                DispatchQueue.main.async {
                    if let c = params["ceiling_db"] as? Double {
                        self.currentProfile.limiterCeiling = Float(c)
                    }
                    if let en = params["is_enabled"] as? Bool {
                        self.currentProfile.isLimiterEnabled = en
                    }
                    self.syncProfileToEngine(self.currentProfile)
                }
                return ["status": "ok"]
            case "set_live_mode":
                if let live = params["is_live_mode"] as? Bool {
                    DispatchQueue.main.async {
                        self.isLiveMode = live
                    }
                }
                return ["status": "ok", "is_live_mode": self.isLiveMode]
            default:
                return nil
            }
        }
        IPCServer.shared.start()
    }

    public func refreshHardwareDevices() {
        self.devices = coreAudioManager.fetchAllDevices()
        let defOutID = coreAudioManager.getDefaultOutputDeviceID()
        let defInID = coreAudioManager.getDefaultInputDeviceID()
        self.selectedOutputDevice = devices.first(where: { $0.id == defOutID })
        self.selectedInputDevice = devices.first(where: { $0.id == defInID })
        logDiagnostic(level: "INFO", message: "Hardware devices refreshed (default out: #\(defOutID), default in: #\(defInID))")
    }

    public func refreshAudioApps() {
        if #available(macOS 14.2, *) {
            let apps = SystemAudioTap.shared.fetchAudioProcesses()
            self.availableAudioApps = apps
            if selectedAudioApp == nil && !tapAllProcesses {
                let musicApp = apps.first(where: { $0.bundleID.lowercased().contains("music") })
                let spotifyApp = apps.first(where: { $0.bundleID.lowercased().contains("spotify") })
                self.selectedAudioApp = musicApp ?? spotifyApp ?? apps.first
            }
        }
    }

    public func selectAudioApp(_ app: AudioAppProcess) {
        self.tapAllProcesses = false
        self.selectedAudioApp = app
        engineManager.selectedTargetProcessID = app.id
        logDiagnostic(level: "INFO", message: "Target audio process set to: \(app.name) (PID \(app.id))")
        do {
            try engineManager.start(captureSource: captureSource, inputDeviceID: selectedInputDevice?.id, outputDeviceID: selectedOutputDevice?.id)
            statusMessage = "Routing: \(app.name)"
            activeErrorMessage = nil
        } catch {
            activeErrorMessage = "Process tap failed: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Process tap failed: \(error.localizedDescription)")
        }
    }

    public func setTapAllProcesses(_ enable: Bool) {
        self.tapAllProcesses = enable
        if enable {
            self.selectedAudioApp = nil
            engineManager.selectedTargetProcessID = nil
            logDiagnostic(level: "INFO", message: "Capture mode set to: ALL SYSTEM AUDIO")
        }
        do {
            try engineManager.start(captureSource: captureSource, inputDeviceID: selectedInputDevice?.id, outputDeviceID: selectedOutputDevice?.id)
            statusMessage = enable ? "Equalizing: All System Audio" : "Equalizing: Single Process"
            activeErrorMessage = nil
        } catch {
            activeErrorMessage = "Capture configuration failed: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Capture configuration failed: \(error.localizedDescription)")
        }
    }

    public func resetAudioEngine() {
        logDiagnostic(level: "INFO", message: "User requested audio engine and ring buffer reset...")
        stopLiveSystemAudio()
        engineManager.resetUnderrunCount()
        refreshHardwareDevices()
        refreshAudioApps()
        activeErrorMessage = nil
        startLiveSystemAudio()
        logDiagnostic(level: "INFO", message: "Audio engine reset completed successfully.")
    }

    public var isHalDriverInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver")
    }

    public func installHalDriver() {
        guard let bundleResourcePath = Bundle.main.resourcePath else { return }
        let driverSource = "\(bundleResourcePath)/driver/DynaQDriver.driver"
        guard FileManager.default.fileExists(atPath: driverSource) else {
            logDiagnostic(level: "ERR", message: "Bundled driver not found at \(driverSource)")
            activeErrorMessage = "Driver source not found inside application bundle."
            return
        }

        let script = """
        do shell script "mkdir -p /Library/Audio/Plug-Ins/HAL && cp -R '\(driverSource)' /Library/Audio/Plug-Ins/HAL/ && chown -R root:wheel /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver && chmod -R 755 /Library/Audio/Plug-Ins/HAL/DynaQDriver.driver && killall coreaudiod" with administrator privileges
        """

        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "Authorization failed"
                logDiagnostic(level: "ERR", message: "Driver install failed: \(msg)")
                activeErrorMessage = "Driver installation failed: \(msg)"
                return
            }
            logDiagnostic(level: "INFO", message: "Virtual HAL Audio Driver deployed and coreaudiod restarted.")
            refreshHardwareDevices()
        }
    }

    public func startLiveSystemAudio() {
        do {
            refreshAudioApps()
            dspPipeline.setProfile(currentProfile)
            dspPipeline.startTelemetryTimer()
            engineManager.client = dspPipeline
            engineManager.selectedTargetProcessID = tapAllProcesses ? nil : selectedAudioApp?.id
            let inID = selectedInputDevice?.id ?? coreAudioManager.getDefaultInputDeviceID()
            let outID = selectedOutputDevice?.id ?? coreAudioManager.getDefaultOutputDeviceID()
            try engineManager.start(captureSource: captureSource, inputDeviceID: inID, outputDeviceID: outID)
            isEngineOnline = true
            var isWaiting = false
            if #available(macOS 14.2, *) {
                isWaiting = (captureSource == .systemAudio) && SystemAudioTap.shared.isWaitingForProcesses
            }
            if isWaiting {
                statusMessage = "Auto-Routing (Standby for Audio Stream)"
            } else {
                let appName = tapAllProcesses ? "All System Audio" : (selectedAudioApp?.name ?? "System Audio")
                statusMessage = captureSource == .systemAudio ? "Equalizing: \(appName)" : "Hardware Mic Active"
            }
            activeErrorMessage = nil
            logDiagnostic(level: "INFO", message: "Audio engine online: \(statusMessage) -> Output #\(outID)")
        } catch {
            isEngineOnline = false
            activeErrorMessage = error.localizedDescription
            statusMessage = "Audio I/O Error: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Audio startup failed: \(error.localizedDescription)")
        }
    }

    public func stopLiveSystemAudio() {
        dspPipeline.stopTelemetryTimer()
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

    public func setCaptureSource(_ source: AudioCaptureSource) {
        self.captureSource = source
        do {
            try engineManager.setCaptureSource(source)
            activeErrorMessage = nil
            logDiagnostic(level: "INFO", message: "Capture source set to \(source.rawValue)")
        } catch {
            activeErrorMessage = "Failed to set capture source: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Failed to set capture source: \(error.localizedDescription)")
        }
    }

    public func setInputDevice(_ device: AudioDevice) {
        self.selectedInputDevice = device
        do {
            try engineManager.switchInputDevice(id: device.id)
            activeErrorMessage = nil
            logDiagnostic(level: "INFO", message: "Input device set to \(device.name) (#\(device.id))")
        } catch {
            activeErrorMessage = "Failed to switch input: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Failed to switch input: \(error.localizedDescription)")
        }
    }

    public func setOutputDevice(_ device: AudioDevice) {
        self.selectedOutputDevice = device
        dspPipeline.eqEngine.setSampleRate(Float(device.currentSampleRate))
        do {
            try engineManager.switchOutputDevice(id: device.id)
            activeErrorMessage = nil
            logDiagnostic(level: "INFO", message: "Output device set to \(device.name) (#\(device.id))")
        } catch {
            activeErrorMessage = "Failed to switch output: \(error.localizedDescription)"
            logDiagnostic(level: "ERR", message: "Failed to switch output: \(error.localizedDescription)")
        }
    }

    public func setBufferSize(_ size: UInt32) {
        self.selectedBufferSize = size
        engineManager.setBufferFrameSize(size)
        logDiagnostic(level: "INFO", message: "Buffer size set to \(size) frames")
    }

    public func setLimiterCeiling(_ ceilingDB: Float) {
        var prof = currentProfile
        prof.limiterCeiling = ceilingDB
        currentProfile = prof
        logDiagnostic(level: "DSP", message: "Limiter ceiling set to \(String(format: "%.1f", ceilingDB)) dBFS")
    }

    public func toggleLimiter() {
        var prof = currentProfile
        prof.isLimiterEnabled.toggle()
        currentProfile = prof
        logDiagnostic(level: "DSP", message: "Limiter \(prof.isLimiterEnabled ? "ENABLED" : "BYPASSED")")
    }

    public func toggleMasterBypass() {
        var prof = currentProfile
        prof.isBypassed.toggle()
        currentProfile = prof
        logDiagnostic(level: "DSP", message: "DSP processing \(prof.isBypassed ? "BYPASSED" : "ACTIVE")")
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
        dspPipeline.resetClip()
        currentMeter.isClippingLeft = false
        currentMeter.isClippingRight = false
    }

    private func syncProfileToEngine(_ profile: EQProfile) {
        dspPipeline.setProfile(profile)
    }
}
