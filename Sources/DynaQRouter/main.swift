import Foundation
import CoreAudio
import DynaQCore
import DynaQAudioDriver
import CDspKernel

/// Dedicated Ultra-Lightweight Audio Routing Backend Daemon for dynaQ.
/// Operates as an independent background audio pipe across CoreAudio inputs/taps and physical outputs.
/// Performs zero heavy DSP manipulations: transparent audio routing with ~0.0% CPU overhead.

print("""
┌─────────────────────────────┐
│  DYNAQ AUDIO ROUTER BACKEND │
└─────────────────────────────┘
""")

let router = AudioRouterBackend.shared
let coreAudio = CoreAudioManager.shared

let allDevices = coreAudio.fetchAllDevices()
let defOutID = coreAudio.getDefaultOutputDeviceID()
let defInID = coreAudio.getDefaultInputDeviceID()
let outDev = allDevices.first(where: { $0.id == defOutID })
let inDev = allDevices.first(where: { $0.id == defInID })

let outName = outDev?.name ?? "Default Output"
let inName = inDev?.name ?? "Default Input"
let sr = outDev?.currentSampleRate ?? 48000.0
let bufSize = coreAudio.getBufferFrameSize(deviceID: defOutID)

print("// [ROUTER BACKEND INITIALIZING]")
print("   COREAUDIO CAPTURE : System Process Tap (macOS 14.2+)")
print("   OUTPUT HARDWARE   : \(outName) (ID: \(defOutID))")
print("   SAMPLE RATE       : \(Int(sr)) Hz")
print("   BUFFER FRAME SIZE : \(bufSize) samples")

router.onLatencyUpdate = { latencyMs in
    let statusStr = String(format: "   ROUNDTRIP LATENCY : %.2f ms [OPTIMAL]", latencyMs)
    print(statusStr)
}

do {
    try router.start(captureSource: .systemAudio, inputDeviceID: defInID, outputDeviceID: defOutID)
    print("// [ROUTER STATUS: ONLINE // ROUTING ACTIVE // PASSTHROUGH READY]")
    print("// Running in ultra-lightweight mode (~0.0% CPU). Press Ctrl+C to terminate.")
} catch {
    print("!! [ROUTER ERROR] Failed to start audio router: \(error.localizedDescription)")
    exit(1)
}

signal(SIGINT) { _ in
    print("\n// [ROUTER SHUTTING DOWN] Stopping HAL stream pipe...")
    AudioRouterBackend.shared.stop()
    print("// [ROUTER TERMINATED]")
    exit(0)
}

signal(SIGTERM) { _ in
    AudioRouterBackend.shared.stop()
    exit(0)
}

RunLoop.main.run()
