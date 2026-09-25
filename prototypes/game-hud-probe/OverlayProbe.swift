import AppKit
import Security

@MainActor
private func record(_ event: String, _ fields: [String: Any] = [:]) {
    var entry = fields
    entry["event"] = event
    entry["time"] = ISO8601DateFormatter().string(from: Date())
    entry["pid"] = ProcessInfo.processInfo.processIdentifier
    let data = try! JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

@MainActor
private func sandboxEntitlement() -> Bool {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let dictionary = information as? [String: Any],
          let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return false }
    return entitlements["com.apple.security.app-sandbox"] as? Bool == true
}

@MainActor
private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class HardwareHUDView: NSView {
    var sample: ProbeMetrics?
    var history: [(Double?, Double?)] = []
    let sandboxed: Bool
    let cpuName: String
    let coreCount: Int
    let displayDescription: String
    override var isFlipped: Bool { true }

    init(frame: NSRect, sandboxed: Bool, sampler: ProbeSampler, screen: NSScreen) {
        self.sandboxed = sandboxed
        cpuName = sampler.cpuName
        coreCount = sampler.logicalCPUCount
        displayDescription = "Desktop \(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt"
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Sandbox hardware monitoring overlay")
    }

    required init?(coder: NSCoder) { nil }

    private func text(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 13, color: NSColor = .white, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (string as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 22), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func metricRow(_ label: String, _ value: String, y: CGFloat, color: NSColor = .white) {
        text(label, x: 14, y: y, width: 176, color: NSColor.white.withAlphaComponent(0.68))
        text(value, x: 181, y: y, width: bounds.width - 195, color: color, alignment: .right)
    }

    private func number(_ value: Double?, format: String) -> String {
        value.map { String(format: format, $0) } ?? "Unavailable"
    }

    private func memory(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return value >= 1_073_741_824
            ? String(format: "%.2f GiB", value / 1_073_741_824)
            : String(format: "%.0f MiB", value / 1_048_576)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.025, alpha: 0.93).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        text("HAGIMI  /  HARDWARE", x: 14, y: 12, width: 226, size: 14)
        text(sandboxed ? "SANDBOX ON" : "BASELINE", x: bounds.width - 125, y: 13, width: 111, size: 11, color: sandboxed ? .systemGreen : .systemOrange, alignment: .right)
        text("\(cpuName) · \(coreCount) CPU cores", x: 14, y: 37, width: bounds.width - 28, size: 12, color: .lightGray)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        text("macOS \(os.majorVersion).\(os.minorVersion) · \(displayDescription)", x: 14, y: 57, width: bounds.width - 28, size: 11, color: .lightGray)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: 14, y: 80))
        separator.line(to: NSPoint(x: bounds.width - 14, y: 80))
        separator.stroke()

        metricRow("CPU · system", number(sample?.cpuPercent, format: "%.1f %%"), y: 92, color: .systemGreen)
        metricRow("GPU · system", number(sample?.gpuPercent, format: "%.1f %%"), y: 114, color: .systemCyan)
        let ram = sample.flatMap { sample in
            sample.memoryUsedBytes.map { String(format: "%.2f / %.0f GiB", $0 / 1_073_741_824, sample.memoryTotalBytes / 1_073_741_824) }
        } ?? "Unavailable"
        metricRow("RAM used / total", ram, y: 136)
        metricRow("Compressed", memory(sample?.compressedBytes), y: 158)
        metricRow("Swap used", memory(sample?.swapUsedBytes), y: 180)
        metricRow("GPU memory · driver", memory(sample?.gpuMemoryUsedBytes), y: 202)
        metricRow("GPU allocated", memory(sample?.gpuMemoryAllocatedBytes), y: 224)
        metricRow("System power", number(sample?.systemPowerWatts, format: "%.2f W"), y: 246)
        metricRow("Battery", number(sample?.batteryPercent, format: "%.0f %%"), y: 268)
        metricRow("Thermal state", sample?.thermalState ?? "Sampling…", y: 290)
        text("SYSTEM LOAD · 1 Hz · \(history.count) samples", x: 14, y: 324, width: 275, size: 11, color: .lightGray)
        text("CPU", x: bounds.width - 91, y: 324, width: 34, size: 11, color: .systemGreen)
        text("GPU", x: bounds.width - 49, y: 324, width: 35, size: 11, color: .systemCyan)
        drawHistory(in: NSRect(x: 14, y: 346, width: bounds.width - 28, height: 67))
        metricRow("Game FPS / frame time", "Not available", y: 432, color: .systemOrange)
        metricRow("CPU °C / CPU-GPU W", "Not available", y: 454, color: .systemOrange)
        metricRow("MetalFX / render size", "Not available", y: 476, color: .systemOrange)
        text("No Metal HUD · No game telemetry", x: 14, y: 509, width: bounds.width - 28, size: 10.5, color: .lightGray)
    }

    private func drawHistory(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let grid = NSBezierPath()
        for fraction in [0.0, 0.5, 1.0] {
            let y = rect.minY + rect.height * fraction
            grid.move(to: NSPoint(x: rect.minX, y: y))
            grid.line(to: NSPoint(x: rect.maxX, y: y))
        }
        grid.stroke()
        guard history.count > 1 else { return }
        for (isCPU, color) in [(true, NSColor.systemGreen), (false, NSColor.systemCyan)] {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.25
            var connected = false
            for (index, entry) in history.enumerated() {
                guard let value = isCPU ? entry.0 : entry.1 else {
                    connected = false
                    continue
                }
                let point = NSPoint(x: rect.minX + CGFloat(index) / CGFloat(history.count - 1) * rect.width,
                                    y: rect.maxY - CGFloat(min(100, max(0, value))) / 100 * rect.height)
                if connected { path.line(to: point) } else { path.move(to: point) }
                connected = true
            }
            path.stroke()
        }
    }
}

@MainActor
private final class OverlayDelegate: NSObject, NSApplicationDelegate {
    private var panels: [PassivePanel] = []
    private var views: [HardwareHUDView] = []
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var sampler: ProbeSampler!
    private var sandboxed = false
    private var visible = true
    private var lastState = ""
    private var history: [(Double?, Double?)] = []
    private var latestSample: ProbeMetrics?

    func applicationDidFinishLaunching(_ notification: Notification) {
        sandboxed = sandboxEntitlement()
        #if SANDBOX_PROBE
        guard sandboxed else {
            record("sandbox-verification-failed")
            NSApp.terminate(nil)
            return
        }
        #endif
        sampler = ProbeSampler()
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = sandboxed ? "Sandbox HUD" : "HUD Baseline"
        let menu = NSMenu()
        addItem("Show / Hide HUD", action: #selector(toggleVisible), to: menu)
        addItem("Floating Level", action: #selector(useFloatingLevel), to: menu)
        addItem("Status Bar Level", action: #selector(useStatusBarLevel), to: menu)
        menu.addItem(.separator())
        addItem("Quit HUD", action: #selector(quit), to: menu)
        statusItem.menu = menu
        rebuildPanels()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildPanels), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        record("overlay-launched", ["sandboxEntitlement": sandboxed, "screens": NSScreen.screens.count, "macOS": ProcessInfo.processInfo.operatingSystemVersionString, "gpuName": sampler.gpuName, "privateAPI": false, "officialHUDData": false])
        if let index = CommandLine.arguments.firstIndex(of: "--launch-scene"), CommandLine.arguments.indices.contains(index + 1) {
            launchScene(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }

    private func launchScene(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--no-hud", "--auto-fullscreen"]
        if let index = CommandLine.arguments.firstIndex(of: "--scene-report"), CommandLine.arguments.indices.contains(index + 1) {
            configuration.arguments += ["--report-path", CommandLine.arguments[index + 1]]
        }
        configuration.environment = ["HAGIMI_ENV_PROBE": "sent-by-overlay"]
        record("launch-environment-request", ["sandboxed": sandboxed, "marker": "sent-by-overlay", "target": url.lastPathComponent])
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            let pid = app?.processIdentifier
            let message = error.map { String(describing: $0) }
            Task { @MainActor in
                record("launch-environment-result", ["targetPID": pid.map(Int.init) ?? -1, "error": message ?? "none"])
            }
        }
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let available = screen.visibleFrame
        return NSRect(x: available.maxX - 422, y: available.maxY - 548, width: 398, height: 534)
    }

    @objc private func rebuildPanels() {
        panels.forEach { $0.close() }
        panels.removeAll()
        views.removeAll()
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = panelFrame(on: screen)
            let panel = PassivePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            panel.title = "Hagimi Hardware HUD \(index + 1)"
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            let view = HardwareHUDView(frame: NSRect(origin: .zero, size: frame.size), sandboxed: sandboxed, sampler: sampler, screen: screen)
            view.sample = latestSample
            view.history = history
            panel.contentView = view
            panels.append(panel)
            views.append(view)
            if visible { panel.orderFrontRegardless() }
            record("overlay-window", ["screen": index, "frame": NSStringFromRect(frame), "windowNumber": panel.windowNumber, "level": panel.level.rawValue, "collectionBehavior": panel.collectionBehavior.rawValue])
        }
    }

    @objc private func refresh() {
        let sample = sampler.sample()
        latestSample = sample
        history.append((sample.cpuPercent, sample.gpuPercent))
        if history.count > 61 { history.removeFirst() }
        for view in views {
            view.sample = sample
            view.history = history
            view.needsDisplay = true
        }
        var fields: [String: Any] = ["thermalState": sample.thermalState, "diagnostics": sample.diagnostics, "memoryTotalBytes": sample.memoryTotalBytes]
        let values: [(String, Double?)] = [
            ("cpuPercent", sample.cpuPercent), ("gpuPercent", sample.gpuPercent),
            ("memoryUsedBytes", sample.memoryUsedBytes), ("compressedBytes", sample.compressedBytes),
            ("swapUsedBytes", sample.swapUsedBytes), ("gpuMemoryUsedBytes", sample.gpuMemoryUsedBytes),
            ("gpuMemoryAllocatedBytes", sample.gpuMemoryAllocatedBytes), ("systemPowerWatts", sample.systemPowerWatts),
            ("batteryPercent", sample.batteryPercent)
        ]
        for (key, value) in values { fields[key] = value.map { $0 as Any } ?? NSNull() }
        record("hardware-sample", fields)
        let front = NSWorkspace.shared.frontmostApplication
        let state = "\(front?.processIdentifier ?? 0)|\(panels.map { "\($0.isOnActiveSpace)/\($0.isVisible)/\($0.isKeyWindow)" })"
        if state != lastState {
            lastState = state
            record("overlay-state", ["frontName": front?.localizedName ?? "", "frontPID": front?.processIdentifier ?? 0, "overlayActive": NSApp.isActive, "panels": panels.map { ["onActiveSpace": $0.isOnActiveSpace, "visible": $0.isVisible, "key": $0.isKeyWindow, "level": $0.level.rawValue] }])
        }
    }

    @objc private func spaceChanged() {
        for (panel, screen) in zip(panels, NSScreen.screens) {
            panel.setFrame(panelFrame(on: screen), display: true)
        }
        record("active-space-changed")
    }
    @objc private func toggleVisible() {
        visible.toggle()
        panels.forEach { visible ? $0.orderFrontRegardless() : $0.orderOut(nil) }
        record("overlay-visibility", ["visible": visible])
    }
    @objc private func useFloatingLevel() { setLevel(.floating) }
    @objc private func useStatusBarLevel() { setLevel(.statusBar) }
    private func setLevel(_ level: NSWindow.Level) {
        panels.forEach { $0.level = level }
        record("overlay-level", ["level": level.rawValue])
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        record("overlay-terminated")
    }
}

@main
private enum OverlayProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = OverlayDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
