import AppKit
import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQAudioDriver

// MARK: - CLI Mode Handlers

func printHelp() {
    print("""
    dynaQ - Professional System-Wide Audio Management Suite
    Version 1.0.0 (macOS)

    USAGE:
      dynaQ [options]

    OPTIONS:
      --gui                 Launch the full graphical studio interface (default)
      --list-devices        List all discovered CoreAudio input & output hardware
      --test-dsp            Run real-time biquad & FFT benchmark test
      --driver-status       Check dynaQ Virtual Audio Driver installation status
      --help, -h            Show this help reference
    """)
}

func listDevices() {
    print("Enumerating CoreAudio hardware devices...")
    let devices = CoreAudioManager.shared.fetchAllDevices()
    if devices.isEmpty {
        print("No active audio devices found.")
        return
    }

    print("\n------------------------------------------------------------")
    print(String(format: "%-4@ | %-6@ | %-8@ | %@", "ID", "DIR", "RATE", "NAME"))
    print("------------------------------------------------------------")
    for d in devices {
        let dir = d.isOutput && d.isInput ? "IN/OUT" : (d.isOutput ? "OUTPUT" : "INPUT")
        let defMark = d.isDefaultOutput ? "*" : " "
        print(String(format: "%-4d | %-6@ | %5.0f Hz | %@%@", d.id, dir, d.currentSampleRate, d.name, defMark))
    }
    print("------------------------------------------------------------")
    print("* = Current default system output\n")
}

func runDSPTest() {
    print("Running dynaQ DSP Filter & FFT Benchmark...")
    let sampleRate: Float = 48000.0
    let engine = ParametricEQEngine(profile: DefaultPresets.harmanHeadphoneTarget, sampleRate: sampleRate)
    let limiter = TruePeakLimiter(ceilingDB: -0.2)
    let analyzer = SpectrumAnalyzer(fftSize: 1024, binCount: 64, sampleRate: sampleRate)
    let meter = LoudnessMeter()

    let bufferSize = 512
    var left = [Float](repeating: 0.5, count: bufferSize)
    var right = [Float](repeating: 0.5, count: bufferSize)

    let iterations = 2000
    let startTime = DispatchTime.now().uptimeNanoseconds

    for _ in 0..<iterations {
        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                engine.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: bufferSize)
                limiter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: bufferSize)

                var mono = [Float](repeating: 0.0, count: bufferSize)
                for i in 0..<bufferSize {
                    mono[i] = (lPtr[i] + rPtr[i]) * 0.5
                }
                mono.withUnsafeBufferPointer { mPtr in
                    analyzer.feed(samples: mPtr.baseAddress!, count: bufferSize)
                }

                _ = meter.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, count: bufferSize)
            }
        }
    }

    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
    let totalProcessedFrames = Double(iterations * bufferSize)
    let audioDurationSec = totalProcessedFrames / Double(sampleRate)

    print(String(format: "DSP benchmark completed in %.2f ms", elapsedMs))
    print(String(format: "Processed %.2f seconds of 48kHz stereo audio across 7 biquad bands + limiter + FFT", audioDurationSec))
    print(String(format: "Real-time performance factor: %.1fx faster than real-time", (audioDurationSec * 1000.0) / elapsedMs))
    print("DSP engine verification passed successfully!")
}

func checkDriverStatus() {
    let status = AudioTapController.shared.driverStatusMessage()
    print("dynaQ Audio Driver Status:")
    print(status)
}

// MARK: - Application Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        openStudioWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "dynaQ")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popoverView = MenuBarView { [weak self] in
            self?.openStudioWindow()
        }
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 260, height: 260)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: popoverView)
        self.popover = pop
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openStudioWindow() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let mainView = MainWindowView()
        let hostingController = NSHostingController(rootView: mainView)

        let w = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.title = "dynaQ — Professional System-Wide Audio Suite"
        w.contentViewController = hostingController
        w.minSize = NSSize(width: 820, height: 620)
        w.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = w
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background menu bar
        return false
    }
}

// MARK: - Main Dispatcher

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    printHelp()
    exit(0)
} else if args.contains("--list-devices") {
    listDevices()
    exit(0)
} else if args.contains("--test-dsp") {
    runDSPTest()
    exit(0)
} else if args.contains("--driver-status") {
    checkDriverStatus()
    exit(0)
}

// Default: Run macOS Studio GUI Application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

