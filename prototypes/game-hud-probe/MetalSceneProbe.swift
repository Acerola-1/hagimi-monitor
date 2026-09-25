import AppKit
import MetalKit

@MainActor private var reportHandle: FileHandle?

@MainActor
private func record(_ event: String, _ fields: [String: Any] = [:]) {
    var entry = fields
    entry["event"] = event
    entry["time"] = ISO8601DateFormatter().string(from: Date())
    entry["pid"] = ProcessInfo.processInfo.processIdentifier
    let data = try! JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) + Data([10])
    FileHandle.standardOutput.write(data)
    reportHandle?.write(data)
}

@MainActor
private final class SceneWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class SceneView: MTKView {
    var onClick: ((NSEvent) -> Void)?
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event) }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

@MainActor
private final class Renderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let started = ProcessInfo.processInfo.systemUptime

    init(device: MTLDevice, format: MTLPixelFormat) throws {
        queue = device.makeCommandQueue()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 position [[position]]; float3 color; };
        vertex VertexOut vertexMain(uint id [[vertex_id]], constant float &time [[buffer(0)]]) {
            float2 positions[3] = { float2(0, 0.65), float2(-0.65, -0.55), float2(0.65, -0.55) };
            float3 colors[3] = { float3(0.3, 1, 0.75), float3(0.25, 0.4, 1), float3(1, 0.4, 0.3) };
            float angle = time * 0.55;
            float2 p = positions[id];
            float2 rotated = float2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle));
            return { float4(rotated, 0, 1), colors[id] };
        }
        fragment float4 fragmentMain(VertexOut in [[stage_in]]) { return float4(in.color, 1); }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = format
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        record("drawable-size", ["width": size.width, "height": size.height])
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var time = Float(ProcessInfo.processInfo.systemUptime - started)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

@MainActor
private final class SceneDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: SceneWindow!
    private var view: SceneView!
    private var renderer: Renderer!
    private let status = NSTextField(wrappingLabelWithString: "")
    private var clicks = 0
    private var keys = 0
    private var lastInput = "none"
    private var borderless = false
    private var savedFrame = NSRect.zero
    private var hudVisible = true
    private let launchEnvironment: [String: String]
    private let noHUD = CommandLine.arguments.contains("--no-hud")
    private let autoFullscreen = CommandLine.arguments.contains("--auto-fullscreen")
    private let normalStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    init(launchEnvironment: [String: String]) {
        self.launchEnvironment = launchEnvironment
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Metal Scene Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let displayItem = NSMenuItem()
        displayItem.title = "Display"
        let displayMenu = NSMenu(title: "Display")
        let fullScreen = NSMenuItem(title: "Toggle Native Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        fullScreen.target = self
        displayMenu.addItem(fullScreen)
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
        NSApp.mainMenu = menu

        guard let device = MTLCreateSystemDefaultDevice() else {
            record("metal-unavailable")
            NSApp.terminate(nil)
            return
        }
        window = SceneWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680), styleMask: normalStyle, backing: .buffered, defer: false)
        window.title = "Hagimi Metal Scene Probe"
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        view = SceneView(frame: window.contentLayoutRect, device: device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.025, green: 0.055, blue: 0.1, alpha: 1)
        view.preferredFramesPerSecond = 60
        if noHUD {
            hudVisible = false
            (view.layer as? CAMetalLayer)?.developerHUDProperties = ["mode": "disabled", "logging": "disabled"]
        }
        do {
            renderer = try Renderer(device: device, format: view.colorPixelFormat)
        } catch {
            record("renderer-error", ["message": String(describing: error)])
            NSApp.terminate(nil)
            return
        }
        view.delegate = renderer
        view.onClick = { [weak self] event in self?.clicked(event) }
        view.onKey = { [weak self] event in self?.keyPressed(event) }
        window.contentView = view
        status.frame = NSRect(x: 24, y: 24, width: 900, height: 110)
        status.autoresizingMask = [.width]
        status.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        status.textColor = .white
        view.addSubview(status)
        refreshStatus()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        record("scene-launched", ["gpu": device.name, "hudEnvironment": ProcessInfo.processInfo.environment["MTL_HUD_ENABLED"] ?? "unset", "hudLoggingEnvironment": ProcessInfo.processInfo.environment["MTL_HUD_LOG_ENABLED"] ?? "unset", "receivedEnvironmentMarker": launchEnvironment["HAGIMI_ENV_PROBE"] ?? "absent", "officialHUDDisabled": noHUD])
        if autoFullscreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.toggleFullScreen() }
        } else if CommandLine.arguments.contains("--auto-borderless") {
            toggleBorderless()
            refreshStatus()
        }
    }

    private func clicked(_ event: NSEvent) {
        clicks += 1
        let point = event.locationInWindow
        let screenPoint = window.convertPoint(toScreen: point)
        lastInput = "click \(clicks) at \(Int(screenPoint.x)),\(Int(screenPoint.y))"
        record("scene-mouse-down", ["count": clicks, "screenX": screenPoint.x, "screenY": screenPoint.y, "keyWindow": window.isKeyWindow, "frontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0])
        refreshStatus()
    }

    private func keyPressed(_ event: NSEvent) {
        keys += 1
        let key = event.charactersIgnoringModifiers ?? ""
        lastInput = "key \(key.debugDescription) (#\(keys))"
        record("scene-key-down", ["key": key, "count": keys, "keyWindow": window.isKeyWindow])
        switch key.lowercased() {
        case "a":
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            record("scene-activation-requested")
        case "f": toggleFullScreen()
        case "b": toggleBorderless()
        case "1": view.preferredFramesPerSecond = 30
        case "2": view.preferredFramesPerSecond = 60
        case "h":
            if !noHUD {
                hudVisible.toggle()
                (view.layer as? CAMetalLayer)?.developerHUDProperties = ["mode": hudVisible ? "default" : "disabled"]
                record("official-hud-mode", ["visible": hudVisible])
            }
        case "q": NSApp.terminate(nil)
        case "\u{1b}":
            if window.styleMask.contains(.fullScreen) { toggleFullScreen() }
            else if borderless { toggleBorderless() }
        default: break
        }
        refreshStatus()
    }

    @objc private func toggleFullScreen() {
        guard !borderless else { return }
        window.toggleFullScreen(nil)
    }

    private func toggleBorderless() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        borderless.toggle()
        if borderless {
            savedFrame = window.frame
            let frame = window.screen?.frame ?? NSScreen.main!.frame
            window.styleMask = [.borderless]
            window.setFrame(frame, display: true)
        } else {
            window.styleMask = normalStyle
            window.setFrame(savedFrame, display: true)
        }
        window.makeFirstResponder(view)
        record("borderless-mode", ["enabled": borderless, "frame": NSStringFromRect(window.frame)])
    }

    private func refreshStatus() {
        let mode = window.styleMask.contains(.fullScreen) ? "NATIVE FULL SCREEN" : (borderless ? "BORDERLESS" : "WINDOWED")
        let explicitlyEnabled = launchEnvironment["MTL_HUD_ENABLED"] == "1"
        let hudState = noHUD ? "OFF (forced)" : (explicitlyEnabled ? (hudVisible ? "enabled" : "hidden") : "system default")
        let marker = launchEnvironment["HAGIMI_ENV_PROBE"] ?? "absent"
        status.stringValue = "METAL SCENE · \(mode) · Official HUD: \(hudState)\nF: full screen  B: borderless  A: activate  1/2: 30/60  Q: quit\nLaunch env marker: \(marker) · No telemetry sent to overlay\nClicks: \(clicks)   Keys: \(keys)   Target cap: \(view.preferredFramesPerSecond)   Last: \(lastInput)"
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        record("native-fullscreen-entered", ["frame": NSStringFromRect(window.frame), "keyWindow": window.isKeyWindow])
        refreshStatus()
        if autoFullscreen {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        record("native-fullscreen-exited", ["keyWindow": window.isKeyWindow])
        refreshStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { record("scene-terminated") }
}

@main
private enum MetalSceneProbe {
    @MainActor static func main() {
        let launchEnvironment = ProcessInfo.processInfo.environment
        if CommandLine.arguments.contains("--no-hud") {
            setenv("MTL_HUD_ENABLED", "0", 1)
            setenv("MTL_HUD_LOG_ENABLED", "0", 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--report-path"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            FileManager.default.createFile(atPath: path, contents: nil)
            reportHandle = FileHandle(forWritingAtPath: path)
        }
        let app = NSApplication.shared
        let delegate = SceneDelegate(launchEnvironment: launchEnvironment)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        try? reportHandle?.close()
    }
}
