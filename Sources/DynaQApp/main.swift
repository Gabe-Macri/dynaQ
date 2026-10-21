import AppKit
import SwiftUI
import DynaQCore
import DynaQDSP
import DynaQAudioDriver

// MARK: - CLI Mode Handlers

func printHelp() {
    print("""
    dynaQ — Professional System-Wide Audio Management Suite
    Version 1.0.0 (macOS CoreAudio)

    USAGE:
      dynaQ [options]

    OPTIONS:
      --gui                 Launch the full graphical studio interface (default)
      --list-devices        Enumerate CoreAudio I/O hardware, channels, and latencies
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

    print("\n--------------------------------------------------------------------------------")
    print(String(format: "%-4@ | %-6@ | %-8@ | %-8@ | %-8@ | %@", "ID", "DIR", "RATE", "BUFFER", "LATENCY", "NAME"))
    print("--------------------------------------------------------------------------------")
    for d in devices {
        let dir = d.isOutput && d.isInput ? "IN/OUT" : (d.isOutput ? "OUTPUT" : "INPUT")
        let defMark = d.isDefaultOutput ? " [DEFAULT OUT]" : (d.isDefaultInput ? " [DEFAULT IN]" : "")
        let latStr = String(format: "%.1f ms", d.latencyMs)
        print(String(format: "%-4d | %-6@ | %5.0f Hz | %4d spl | %-8@ | %@%@", d.id, dir, d.currentSampleRate, d.bufferFrameSize, latStr, d.name, defMark))
    }
    print("--------------------------------------------------------------------------------\n")
}

func checkDriverStatus() {
    print("dynaQ Audio Routing Status:")
    if #available(macOS 14.2, *) {
        print("• Native CoreAudio System Tap: Fully supported & active")
    } else {
        print("• Native CoreAudio System Tap requires macOS 14.2+")
    }
    let halDriverPath = "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver"
    let hasHal = FileManager.default.fileExists(atPath: halDriverPath)
    print("• Virtual HAL Driver: \(hasHal ? "Installed" : "Not Installed (Using Native User-Space Tap)")")
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
        pop.contentSize = NSSize(width: 270, height: 280)
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
            contentRect: NSRect(x: 100, y: 100, width: 940, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.title = "dynaQ — Professional System-Wide Audio Suite"
        w.contentViewController = hostingController
        w.minSize = NSSize(width: 880, height: 640)
        w.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = w
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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
