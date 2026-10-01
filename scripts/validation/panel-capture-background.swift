import AppKit

// 有限时长、非激活、输入穿透的原生背景窗口；材质采样来自真实 WindowServer 合成。
final class Background: NSView {
    let style: String
    init(frame: NSRect, style: String) { self.style = style; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("programmatic fixture") }
    override func draw(_ dirtyRect: NSRect) {
        (style == "dark" ? NSColor(calibratedWhite: 0.06, alpha: 1) : .white).setFill()
        bounds.fill()
        if style == "complex" {
            let colors: [NSColor] = [.systemPurple, .systemBlue, .systemOrange, .systemGreen]
            for x in stride(from: CGFloat(0), to: bounds.width, by: 80) {
                for y in stride(from: CGFloat(0), to: bounds.height, by: 80) {
                    colors[(Int(x / 80) + Int(y / 80)) % colors.count].withAlphaComponent(0.7).setFill()
                    NSRect(x: x, y: y, width: 70, height: 70).fill()
                }
            }
        }
    }
}

@MainActor final class BackgroundDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }) else { NSApp.terminate(nil); return }
        let style = CommandLine.arguments.dropFirst().first ?? "white"
        let panel = NSPanel(contentRect: screen.visibleFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.ignoresMouseEvents = true; panel.hasShadow = false
        panel.level = .normal
        panel.contentView = Background(frame: NSRect(origin: .zero, size: screen.visibleFrame.size), style: style)
        panel.orderFrontRegardless(); window = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 65) { NSApp.terminate(nil) }
    }
}
@main struct BackgroundFixture {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = BackgroundDelegate()
        application.delegate = delegate
        application.run()
    }
}
