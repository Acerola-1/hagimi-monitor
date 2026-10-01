import AppKit
import Combine
import SwiftUI
import QuartzCore

final class NativeCPUHost<Content: View>: NSHostingView<Content> {
    var layoutCount = 0
    override func layout() { layoutCount += 1; super.layout() }
}

enum NativeCPUStyle {
    static let width: CGFloat = 340
    static let closedHeight: CGFloat = 194
    static let revealHeight: CGFloat = 284
    static let capacity: CGFloat = 780
    static let palette = MonitorPalette(preference: .vibrant, colorScheme: .light)
    static let cpu = palette.moduleTint(for: .cpu)
    static let gpu = palette.moduleTint(for: .gpu)
    static let memory = palette.moduleTint(for: .memory)
    static let outerPadding: CGFloat = 20
    static let omega: Double = 20
}

final class NativeCPUFlippedView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let mask = layer?.mask, !(mask.presentation() ?? mask).bounds.contains(convert(point, from: superview)) { return nil }
        return super.hitTest(point)
    }
}
final class NativeCPUEffectView: NSVisualEffectView { override var isFlipped: Bool { true } }

struct NativeCPUTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(NativeCPUStyle.cpu).frame(width: 5, height: 5)
            Text("SYSTEM · LIVE").font(.system(size: 10, weight: .semibold)).tracking(1.1)
                .foregroundStyle(MonitorPalette(preference: .vibrant, colorScheme: colorScheme).captionText)
            Spacer()
        }.padding(.horizontal, 14)
    }
}

@MainActor
final class NativeCPUAnimator: NSView {
    override var isFlipped: Bool { true }
    let store: MonitorStore
    let surface = NativeCPUFlippedView(frame: CGRect(x: NativeCPUStyle.outerPadding, y: NativeCPUStyle.outerPadding, width: NativeCPUStyle.width, height: NativeCPUStyle.capacity))
    let outline = CAShapeLayer()
    let contourShadow = CALayer()
    let outerMask = CALayer()
    let cpuMask = CALayer()
    let cpuCard = NativeCPUFlippedView(frame: CGRect(x: 6, y: 34, width: 328, height: NativeCPUStyle.capacity - 34))
    let effect = NSVisualEffectView()
    let tint = CALayer()
    var rowFills: [(CAGradientLayer, NSColor)] = []
    var brighteners: [CALayer] = []
    var shifted: [(CALayer, CGFloat)] = []
    var shiftedViews: [(NSView, CGPoint)] = []
    var cpuHeader: NSHostingView<AnyView>!
    var detailHost: NSHostingView<AnyView>!
    var otherHeaders: [(MonitorKind, NSHostingView<AnyView>)] = []
    var footerHost: NSHostingView<AnyView>!
    var revealHeight: CGFloat = 284
    var updates = 0
    var deferredRefresh = 0
    var layoutCounts: [() -> Int] = []
    var expanded = false
    var dark = false
    var started = CACurrentMediaTime()
    var start: Double = 0
    var velocity: Double = 0
    var destination: Double = 0
    var onChange: (() -> Void)?
    var operation = 0
    var sequenceID = 0

    init(store: MonitorStore) {
        self.store = store
        super.init(frame: CGRect(x: 0, y: 0, width: NativeCPUStyle.width + 2 * NativeCPUStyle.outerPadding, height: NativeCPUStyle.capacity + 2 * NativeCPUStyle.outerPadding))
        wantsLayer = true
        let position = CGPoint(x: NativeCPUStyle.outerPadding, y: NativeCPUStyle.outerPadding)
        contourShadow.anchorPoint = .zero; contourShadow.position = position; contourShadow.bounds = surface.bounds
        contourShadow.shadowColor = NSColor.black.cgColor; contourShadow.shadowOpacity = 0.22
        contourShadow.shadowRadius = 9; contourShadow.shadowOffset = CGSize(width: 0, height: 3)
        contourShadow.shadowPath = contour(NativeCPUStyle.closedHeight)
        layer!.addSublayer(contourShadow)
        surface.wantsLayer = true
        addSubview(surface)
        let surfaceLayer = surface.layer!
        outerMask.anchorPoint = .zero
        outerMask.position = .zero
        outerMask.bounds = CGRect(x: 0, y: 0, width: NativeCPUStyle.width, height: NativeCPUStyle.closedHeight)
        outerMask.backgroundColor = NSColor.white.cgColor
        outerMask.cornerRadius = MonitorConstants.panelCornerRadius
        surfaceLayer.mask = outerMask
        outline.anchorPoint = .zero; outline.position = position; outline.bounds = surface.bounds
        outline.fillColor = nil; outline.lineWidth = 0.5
        outline.path = contour(NativeCPUStyle.closedHeight)
        layer!.addSublayer(outline)
        effect.frame = surface.bounds
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        surface.addSubview(effect)
        tint.frame = surface.bounds
        effect.wantsLayer = true
        effect.layer!.addSublayer(tint)
        mount(NativeCPUTitle(), frame: CGRect(x: 0, y: 7, width: 340, height: 22), into: surface)
        cpuCard.wantsLayer = true
        surface.addSubview(cpuCard)
        cpuMask.anchorPoint = .zero
        cpuMask.position = .zero
        cpuMask.bounds = CGRect(x: 0, y: 0, width: 328, height: 34)
        cpuMask.backgroundColor = NSColor.white.cgColor
        cpuMask.cornerRadius = 14
        cpuCard.layer!.mask = cpuMask
        addFill(to: cpuCard, color: NativeCPUStyle.cpu)
        cpuHeader = mount(NativeCPUPageParts.header(module: module(.cpu), dark: false, expanded: false, action: { [weak self] in self?.toggle() }),
                          frame: CGRect(x: 0, y: 0, width: 328, height: 34), into: cpuCard)
        detailHost = mount(NativeCPUPageParts.details(module: module(.cpu), processes: store.topCPUProcesses, dark: false, settings: store.settings),
                          frame: CGRect(x: 0, y: 34, width: 328, height: 284), into: cpuCard)
        makeRow(kind: "gpu", tint: NativeCPUStyle.gpu, y: 74, height: 34)
        makeRow(kind: "memory", tint: NativeCPUStyle.memory, y: 114, height: 34)
        let footer = mount(NativeCPUPageParts.footer(dark: false), frame: CGRect(x: 6, y: 154, width: 328, height: 34), into: surface)
        footerHost = footer
        shifted.append((footer.layer!, footer.layer!.position.y))
        shiftedViews.append((footer, footer.frame.origin))
        updateTheme(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func contour(_ height: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: 0, y: 0, width: NativeCPUStyle.width, height: height),
               cornerWidth: MonitorConstants.panelCornerRadius, cornerHeight: MonitorConstants.panelCornerRadius,
               transform: nil)
    }

    @discardableResult
    func mount<V: View>(_ view: V, frame: CGRect, into parent: NSView) -> NSHostingView<V> {
        let host = NativeCPUHost(rootView: view)
        host.frame = frame
        host.wantsLayer = true
        parent.addSubview(host)
        layoutCounts.append { [weak host] in host?.layoutCount ?? 0 }
        return host
    }

    func addFill(to view: NSView, color: Color) {
        let material = NativeCPUEffectView(frame: view.bounds)
        material.material = .menu; material.blendingMode = .withinWindow; material.state = .active
        material.wantsLayer = true
        view.addSubview(material)
        let brighten = CALayer()
        brighten.frame = view.bounds
        material.layer!.addSublayer(brighten)
        brighteners.append(brighten)
        let fill = CAGradientLayer()
        let c = NSColor(color)
        fill.frame = view.bounds
        fill.locations = [0, NSNumber(value: min(MonitorConstants.rowTintPlateau / view.bounds.height, 1)),
                          NSNumber(value: min(MonitorConstants.rowTintFadeEnd / view.bounds.height, 1))]
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        material.layer!.addSublayer(fill)
        rowFills.append((fill, c))
    }

    func makeRow(kind: String, tint: Color, y: CGFloat, height: CGFloat) {
        let row = NativeCPUFlippedView(frame: CGRect(x: 6, y: y, width: 328, height: height))
        row.wantsLayer = true
        row.layer!.cornerRadius = 14
        row.layer!.masksToBounds = true
        surface.addSubview(row)
        addFill(to: row, color: tint)
        let kind = MonitorKind(rawValue: kind)!
        let host = mount(NativeCPUPageParts.header(module: module(kind), dark: false, expanded: false, action: {}), frame: row.bounds, into: row)
        otherHeaders.append((kind, host))
        shifted.append((row.layer!, row.layer!.position.y))
        shiftedViews.append((row, row.frame.origin))
    }

    func state(at now: Double) -> (Double, Double) {
        let t = max(0, now - started), w = NativeCPUStyle.omega
        let a = start - destination, b = velocity + w * a, e = exp(-w * t)
        return (destination + (a + b * t) * e, (b - w * (a + b * t)) * e)
    }

    func animate(_ layer: CALayer, _ key: String, from: CGFloat, to: CGFloat, now: Double, speed: Double, instantly: Bool) {
        layer.removeAnimation(forKey: "motion")
        layer.setValue(to, forKeyPath: key)
        guard !instantly, abs(to - from) > 0.0001 else { return }
        let spring = springAnimation(key, now: now, layer: layer, speed: speed)
        spring.fromValue = from
        spring.toValue = to
        layer.add(spring, forKey: "motion")
    }

    func springAnimation(_ key: String, now: Double, layer: CALayer, speed: Double) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: key)
        spring.mass = 1
        spring.stiffness = NativeCPUStyle.omega * NativeCPUStyle.omega
        spring.damping = 2 * NativeCPUStyle.omega
        spring.initialVelocity = speed
        spring.duration = spring.settlingDuration
        spring.beginTime = layer.convertTime(now, from: nil)
        return spring
    }

    func toggle() {
        let now = CACurrentMediaTime()
        let (p, v) = state(at: now)
        expanded.toggle()
        let target = expanded ? 1.0 : 0.0
        let speed = abs(target - p) > 0.00001 ? v / (target - p) : 0
        let instantly = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let d = revealHeight
        animate(outerMask, "bounds.size.height", from: NativeCPUStyle.closedHeight + p * d,
                to: NativeCPUStyle.closedHeight + target * d, now: now, speed: speed, instantly: instantly)
        // 描边和阴影随可见轮廓运动，透明窗口的固定 bounds 不参与阴影计算。
        let fromPath = contour(NativeCPUStyle.closedHeight + p * d)
        let toPath = contour(NativeCPUStyle.closedHeight + target * d)
        outline.path = toPath; contourShadow.shadowPath = toPath
        for (layer, key) in [(outline as CALayer, "path"), (contourShadow, "shadowPath")] {
            layer.removeAnimation(forKey: "motion")
            if !instantly {
                let animation = springAnimation(key, now: now, layer: layer, speed: speed)
                animation.fromValue = fromPath; animation.toValue = toPath
                layer.add(animation, forKey: "motion")
            }
        }
        animate(cpuMask, "bounds.size.height", from: 34 + p * d, to: 34 + target * d,
                now: now, speed: speed, instantly: instantly)
        for (view, origin) in shiftedViews {
            view.setFrameOrigin(CGPoint(x: origin.x, y: origin.y + target * d))
        }
        for (layer, base) in shifted {
            animate(layer, "position.y", from: base + p * d, to: base + target * d,
                    now: now, speed: speed, instantly: instantly)
        }
        CATransaction.commit()
        started = now; start = instantly ? target : p; velocity = instantly ? 0 : v; destination = target
        store.beginExpansionAnimation()
        cpuHeader.rootView = NativeCPUPageParts.header(module: module(.cpu), dark: dark, expanded: expanded,
            action: { [weak self] in self?.toggle() })
        operation += 1
        print("motion operation=\(operation) target=\(target) start=\(p) velocity=\(v) layouts=\(layoutCounts.map { $0() })")
        fflush(stdout)
        onChange?()
    }

    func updateTheme(_ dark: Bool) {
        self.dark = dark
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.backgroundColor = (dark ? NSColor.black.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.45)).cgColor
        outline.strokeColor = (dark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.25)).cgColor
        contourShadow.shadowOpacity = dark ? 0.4 : 0.22
        for brighten in brighteners { brighten.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.08 : 0.15).cgColor }
        for (fill, color) in rowFills {
            let full = dark ? 0.16 : 0.08
            fill.colors = [color.withAlphaComponent(full).cgColor, color.withAlphaComponent(full).cgColor,
                           color.withAlphaComponent(MonitorConstants.rowTintFaintOpacity).cgColor]
        }
        CATransaction.commit()
        if detailHost != nil { refreshViews() }
    }

    func module(_ kind: MonitorKind) -> MonitorModule {
        store.modules.first { $0.kind == kind } ?? .placeholder(kind: kind)
    }

    func refreshViews() {
        let (_, v) = state(at: CACurrentMediaTime())
        if abs(v) > 0.01 {
            deferredRefresh += 1
            let ticket = deferredRefresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, self.deferredRefresh == ticket else { return }
                self.refreshViews()
            }
            return
        }
        cpuHeader.rootView = NativeCPUPageParts.header(module: module(.cpu), dark: dark, expanded: expanded,
            action: { [weak self] in self?.toggle() })
        detailHost.rootView = NativeCPUPageParts.details(module: module(.cpu), processes: store.topCPUProcesses, dark: dark, settings: store.settings)
        detailHost.layoutSubtreeIfNeeded()
        let natural = max(1, detailHost.fittingSize.height)
        detailHost.setFrameSize(CGSize(width: 328, height: natural))
        if abs(natural - revealHeight) > 0.5 {
            revealHeight = natural
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let amount = expanded ? natural : 0
            outerMask.bounds.size.height = NativeCPUStyle.closedHeight + amount
            cpuMask.bounds.size.height = 34 + amount
            outline.path = contour(NativeCPUStyle.closedHeight + amount)
            contourShadow.shadowPath = outline.path
            for (view, origin) in shiftedViews { view.setFrameOrigin(CGPoint(x: origin.x, y: origin.y + amount)) }
            for (layer, base) in shifted { layer.position.y = base + amount }
            CATransaction.commit()
        }
        for (kind, host) in otherHeaders {
            host.rootView = NativeCPUPageParts.header(module: module(kind), dark: dark, expanded: false, action: {})
        }
        footerHost.rootView = NativeCPUPageParts.footer(dark: dark)
        updates += 1
        print("native-cpu update=\(updates) cpu=\(module(.cpu).summary) detail-height=\(natural) processes=\(store.topCPUProcesses.map(\.name).joined(separator: ","))")
        fflush(stdout)
    }

    func sequence(reverse: Bool) {
        sequenceID += 1
        let id = sequenceID
        let times: [Double] = reverse ? [0, 0.11, 0.22, 0.33, 0.48, 0.65, 0.82, 1.0] : [0, 1.2, 2.4, 3.6]
        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, self.sequenceID == id else { return }
                self.toggle()
            }
        }
    }
}


@MainActor
final class NativeCPUMotionDemo: ObservableObject {
    static let enabled = ProcessInfo.processInfo.environment["HAGIMI_NATIVE_CPU_DEMO"] == "1"
        || Bundle.main.bundleIdentifier?.hasPrefix("local.hagimi.cpu-native-demo") == true
    static func seedCPUUserPreferences() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("local.hagimi.cpu-native-demo") == true,
              let sourceID = Bundle(path: "/Applications/HagimiMonitorDirect.app")?.bundleIdentifier,
              let source = UserDefaults(suiteName: sourceID) else { return }
        if let order = source.dictionary(forKey: "settings.panel.orders")?["metrics.cpu"] as? [String] {
            UserDefaults.standard.set(["metrics.cpu": order], forKey: "settings.panel.orders")
        }
        if let enabled = source.array(forKey: "settings.enabledMetrics.cpu") as? [String] {
            UserDefaults.standard.set(enabled, forKey: "settings.enabledMetrics.cpu")
        }
    }
    @Published var expanded = false
    @Published var dark = false
    let store: MonitorStore
    let panel: NativeCPUAnimator
    var panelWindow: NSPanel!
    var controlsWindow: NSWindow!
    var subscriptions = Set<AnyCancellable>()
    init(store: MonitorStore) {
        self.store = store
        panel = NativeCPUAnimator(store: store)
        NSApp.setActivationPolicy(.regular)
        let screen = NSScreen.main!.visibleFrame
        let height = min(NativeCPUStyle.capacity + 40, screen.height - 40)
        panelWindow = NSPanel(contentRect: CGRect(x: screen.maxX - 410, y: screen.maxY - height - 15,
            width: 380, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panelWindow.title = "Native CPU Motion Demo"
        panelWindow.isOpaque = false; panelWindow.backgroundColor = .clear; panelWindow.hasShadow = false
        panelWindow.level = .floating; panelWindow.contentView = panel
        controlsWindow = NSWindow(contentRect: CGRect(x: screen.maxX - 805, y: screen.maxY - 445, width: 350, height: 410),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        controlsWindow.title = "原版 CPU · 新动画 Demo"
        controlsWindow.contentView = NSHostingView(rootView: NativeCPUControls(model: self))
        panel.onChange = { [weak self] in guard let self else { return }; self.expanded = self.panel.expanded }
        store.panelDidAppear()
        store.objectWillChange.debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.panel.refreshViews() }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--dark") { dark = true; panel.updateTheme(true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.panel.refreshViews() }
        if CommandLine.arguments.contains("--autotest") {
            for i in 0..<16 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(i) * 0.85) { [weak self] in self?.panel.toggle() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in self?.panel.sequence(reverse: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
                guard let self else { return }
                print("complete operations=\(self.panel.operation) updates=\(self.panel.updates) layouts=\(self.panel.layoutCounts.map { $0() })")
                fflush(stdout); NSApp.terminate(nil)
            }
        }
    }
    func show() {
        panelWindow.orderFrontRegardless(); controlsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct NativeCPUControls: View {
    @ObservedObject var model: NativeCPUMotionDemo
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("原版 CPU，新的运动方式").font(.system(size: 21, weight: .semibold))
            Text("圆环、指标网格、趋势图和五行进程排名复用原版组件，数值通过原有采样通道实时更新。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.expanded ? "收起 CPU" : "展开 CPU") { model.panel.sequenceID += 1; model.panel.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("连续反转") { model.panel.sequence(reverse: true) }
            }.controlSize(.large)
            Toggle("深色外观", isOn: $model.dark).onChange(of: model.dark) { _, v in model.panel.updateTheme(v) }
            Divider()
            Text("可点击指标复制数值。\n请重点对照原版的字号、位置、间距和明细层次。")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("本轮聚焦 CPU 页；下方模块只展示行头，底部入口仅作布局参照。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("退出 Demo") { NSApp.terminate(nil) }
        }.padding(26).frame(width: 350, height: 410)
    }
}
