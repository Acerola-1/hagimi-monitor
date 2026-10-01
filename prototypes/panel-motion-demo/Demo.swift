import AppKit
import SwiftUI
import QuartzCore

// 独立原生原型：静态内容保留完整布局，只在交互时提交一次图层运动。
enum DemoStyle {
    static let width: CGFloat = 340
    static let closedHeight: CGFloat = 202
    static let revealHeight: CGFloat = 284
    static let capacity: CGFloat = closedHeight + revealHeight + 64
    static let palette = MonitorPalette(preference: .vibrant, colorScheme: .light)
    static let cpu = palette.moduleTint(for: .cpu)
    static let gpu = palette.moduleTint(for: .gpu)
    static let memory = palette.moduleTint(for: .memory)
    static let outerPadding: CGFloat = 20
    static let omega: Double = 20
}

struct Snapshot: Decodable {
    struct Metric: Decodable { let name: String; let value: String }
    struct Core: Decodable { let performance: Bool; let usage: Double }
    struct Module: Decodable {
        let kind: String; let summary: String; let samples: [Double]; let metrics: [Metric]
        let cores: [Core]?
    }
    struct Process: Decodable { let name: String; let usage: Double }
    let modules: [Module]
    let cpu: [Process]
    func module(_ kind: String) -> Module { modules.first { $0.kind == kind }! }
    func value(_ name: String) -> String {
        module("cpu").metrics.first { $0.name == name }?.value ?? "—"
    }
}

final class StaticHost<Content: View>: NSHostingView<Content> {
    var layoutCount = 0
    override func layout() { layoutCount += 1; super.layout() }
}

struct HistoryLine: Shape {
    let samples: [Double]
    var area = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, v) in samples.enumerated() {
            let q = CGPoint(x: r.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1)),
                            y: r.height * (1 - CGFloat(v) / 100))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        if area { p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() }
        return p
    }
}

struct Header: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MonitorPalette { MonitorPalette(preference: .vibrant, colorScheme: colorScheme) }
    let symbol: String; let title: String; let value: String; let tint: Color
    let samples: [Double]
    var expanded: Bool = false
    var action: (() -> Void)? = nil
    var body: some View {
        let row = HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(tint).frame(width: 20)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primaryText)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(palette.valueText)
            Spacer(minLength: 6)
            ZStack {
                HistoryLine(samples: samples, area: true).fill(tint.opacity(0.18))
                HistoryLine(samples: samples).stroke(tint, lineWidth: 1.2)
            }.frame(width: 54, height: 16)
            if action != nil {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.secondaryText).frame(width: 10)
            }
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
        if let action {
            Button(action: action) { row.contentShape(Rectangle()) }.buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起 CPU 明细" : "展开 CPU 明细")
        } else { row }
    }
}

struct CPUDetails: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MonitorPalette { MonitorPalette(preference: .vibrant, colorScheme: colorScheme) }
    let snapshot: Snapshot
    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
              HStack(spacing: 10) {
                ForEach(Array((snapshot.module("cpu").cores ?? []).sorted { $0.performance && !$1.performance }.enumerated()), id: \.offset) { _, core in
                    ZStack {
                        Circle().stroke(palette.rowSeparator(for: .cpu), lineWidth: 2)
                        Circle().trim(from: 0, to: core.usage / 100)
                            .stroke(core.performance ? palette.performanceCoreTint : palette.severityTint(for: .calm), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }.frame(width: 20, height: 20)
                }
              }.frame(height: 30)
              Rectangle().fill(palette.captionText.opacity(0.16)).frame(height: 0.5).padding(.horizontal, 8)
              HStack(spacing: 0) {
                coreGroup("P", "49%", palette.performanceCoreTint)
                Rectangle().fill(palette.captionText.opacity(0.22)).frame(width: 0.5, height: 13)
                coreGroup("E", "12%", palette.severityTint(for: .calm))
              }.frame(height: 25)
            }.background(palette.trackFill, in: RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 6) {
                metric("闲置", snapshot.value("idle")); metric("系统", snapshot.value("system"))
            }
            HStack(spacing: 6) {
                metric("用户", snapshot.value("user")); metric("进程数", snapshot.value("process-count"))
            }
            metric("热压力", snapshot.value("temperature"), normal: true)
            metric("启动时间", snapshot.value("uptime"))
            HStack { Text("进程占用"); Spacer(); Text("CPU") }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.captionText).padding(.top, 3)
            ForEach(Array(snapshot.cpu.enumerated()), id: \.offset) { _, process in
                HStack {
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", process.usage)).monospacedDigit().foregroundStyle(palette.secondaryText)
                }.font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.primaryText).frame(height: 17)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
            .frame(width: 316, height: DemoStyle.revealHeight, alignment: .top)
    }
    func coreGroup(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(palette.captionText)
            Circle().fill(color).frame(width: 5, height: 5)
            Text(value).fontWeight(.bold).foregroundStyle(palette.valueText).monospacedDigit()
        }.font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity)
    }
    func metric(_ label: String, _ value: String, normal: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(palette.captionText)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().foregroundStyle(palette.valueText)
            if normal { Text("正常").foregroundStyle(palette.severityTint(for: .calm)) }
        }.font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).frame(height: 23)
            .background(palette.trackFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Footer: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 6) {
            item("waveform.path.ecg", "监视器")
            item("wrench.and.screwdriver", "工具")
            item("gearshape", "设置")
        }.frame(width: 328, height: 34)
    }
    func item(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 7) { Image(systemName: symbol); Text(title) }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(MonitorPalette(preference: .vibrant, colorScheme: colorScheme).primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RowMaterial().clipShape(RoundedRectangle(cornerRadius: 14)))
            .accessibilityElement(children: .combine)
    }
}

struct RowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu; view.blendingMode = .withinWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
final class FlippedEffectView: NSVisualEffectView { override var isFlipped: Bool { true } }

struct PanelTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(DemoStyle.cpu).frame(width: 5, height: 5)
            Text("SYSTEM · SNAPSHOT").font(.system(size: 10, weight: .semibold)).tracking(1.1)
                .foregroundStyle(MonitorPalette(preference: .vibrant, colorScheme: colorScheme).captionText)
            Spacer()
        }.padding(.horizontal, 14)
    }
}

@MainActor
final class MotionPanel: NSView {
    override var isFlipped: Bool { true }
    let snapshot: Snapshot
    let surface = FlippedView(frame: CGRect(x: DemoStyle.outerPadding, y: DemoStyle.outerPadding, width: DemoStyle.width, height: DemoStyle.capacity))
    let outline = CAShapeLayer()
    let contourShadow = CALayer()
    let outerMask = CALayer()
    let cpuMask = CALayer()
    let cpuCard = FlippedView(frame: CGRect(x: 6, y: 34, width: 328, height: 42 + DemoStyle.revealHeight))
    let effect = NSVisualEffectView()
    let tint = CALayer()
    var rowFills: [(CAGradientLayer, NSColor)] = []
    var brighteners: [CALayer] = []
    var shifted: [(CALayer, CGFloat)] = []
    var cpuHeader: NSHostingView<Header>!
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

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        super.init(frame: CGRect(x: 0, y: 0, width: DemoStyle.width + 2 * DemoStyle.outerPadding, height: DemoStyle.capacity + 2 * DemoStyle.outerPadding))
        wantsLayer = true
        let position = CGPoint(x: DemoStyle.outerPadding, y: DemoStyle.outerPadding)
        contourShadow.anchorPoint = .zero; contourShadow.position = position; contourShadow.bounds = surface.bounds
        contourShadow.shadowColor = NSColor.black.cgColor; contourShadow.shadowOpacity = 0.22
        contourShadow.shadowRadius = 9; contourShadow.shadowOffset = CGSize(width: 0, height: 3)
        contourShadow.shadowPath = contour(DemoStyle.closedHeight)
        layer!.addSublayer(contourShadow)
        surface.wantsLayer = true
        addSubview(surface)
        let surfaceLayer = surface.layer!
        outerMask.anchorPoint = .zero
        outerMask.position = .zero
        outerMask.bounds = CGRect(x: 0, y: 0, width: DemoStyle.width, height: DemoStyle.closedHeight)
        outerMask.backgroundColor = NSColor.white.cgColor
        outerMask.cornerRadius = MonitorConstants.panelCornerRadius
        surfaceLayer.mask = outerMask
        outline.anchorPoint = .zero; outline.position = position; outline.bounds = surface.bounds
        outline.fillColor = nil; outline.lineWidth = 0.5
        outline.path = contour(DemoStyle.closedHeight)
        layer!.addSublayer(outline)
        effect.frame = surface.bounds
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        surface.addSubview(effect)
        tint.frame = surface.bounds
        effect.wantsLayer = true
        effect.layer!.addSublayer(tint)
        mount(PanelTitle(), frame: CGRect(x: 0, y: 7, width: 340, height: 22), into: surface)
        cpuCard.wantsLayer = true
        surface.addSubview(cpuCard)
        cpuMask.anchorPoint = .zero
        cpuMask.position = .zero
        cpuMask.bounds = CGRect(x: 0, y: 0, width: 328, height: 42)
        cpuMask.backgroundColor = NSColor.white.cgColor
        cpuMask.cornerRadius = 14
        cpuCard.layer!.mask = cpuMask
        addFill(to: cpuCard, color: DemoStyle.cpu)
        let cpu = snapshot.module("cpu")
        cpuHeader = mount(Header(symbol: "cpu", title: "CPU:", value: cpu.summary, tint: DemoStyle.cpu,
                                samples: cpu.samples, action: { [weak self] in self?.toggle() }),
                          frame: CGRect(x: 0, y: 0, width: 328, height: 42), into: cpuCard)
        mount(CPUDetails(snapshot: snapshot), frame: CGRect(x: 6, y: 42, width: 316, height: DemoStyle.revealHeight), into: cpuCard)
        makeRow(kind: "gpu", symbol: "display", title: "GPU:", tint: DemoStyle.gpu, y: 82, height: 34)
        makeRow(kind: "memory", symbol: "memorychip", title: "内存:", tint: DemoStyle.memory, y: 122, height: 34)
        let footer = mount(Footer(), frame: CGRect(x: 6, y: 162, width: 328, height: 34), into: surface)
        shifted.append((footer.layer!, footer.layer!.position.y))
        updateTheme(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func contour(_ height: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: 0, y: 0, width: DemoStyle.width, height: height),
               cornerWidth: MonitorConstants.panelCornerRadius, cornerHeight: MonitorConstants.panelCornerRadius,
               transform: nil)
    }

    @discardableResult
    func mount<V: View>(_ view: V, frame: CGRect, into parent: NSView) -> NSHostingView<V> {
        let host = StaticHost(rootView: view)
        host.frame = frame
        host.wantsLayer = true
        parent.addSubview(host)
        layoutCounts.append { [weak host] in host?.layoutCount ?? 0 }
        return host
    }

    func addFill(to view: NSView, color: Color) {
        let material = FlippedEffectView(frame: view.bounds)
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

    func makeRow(kind: String, symbol: String, title: String, tint: Color, y: CGFloat, height: CGFloat) {
        let row = FlippedView(frame: CGRect(x: 6, y: y, width: 328, height: height))
        row.wantsLayer = true
        row.layer!.cornerRadius = 14
        row.layer!.masksToBounds = true
        surface.addSubview(row)
        addFill(to: row, color: tint)
        let module = snapshot.module(kind)
        mount(Header(symbol: symbol, title: title, value: kind == "memory" ? "警告" : module.summary,
                     tint: tint, samples: module.samples), frame: row.bounds, into: row)
        shifted.append((row.layer!, row.layer!.position.y))
    }

    func state(at now: Double) -> (Double, Double) {
        let t = max(0, now - started), w = DemoStyle.omega
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
        spring.stiffness = DemoStyle.omega * DemoStyle.omega
        spring.damping = 2 * DemoStyle.omega
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
        let d = DemoStyle.revealHeight
        animate(outerMask, "bounds.size.height", from: DemoStyle.closedHeight + p * d,
                to: DemoStyle.closedHeight + target * d, now: now, speed: speed, instantly: instantly)
        // 描边和阴影随可见轮廓运动，透明窗口的固定 bounds 不参与阴影计算。
        let fromPath = contour(DemoStyle.closedHeight + p * d)
        let toPath = contour(DemoStyle.closedHeight + target * d)
        outline.path = toPath; contourShadow.shadowPath = toPath
        for (layer, key) in [(outline as CALayer, "path"), (contourShadow, "shadowPath")] {
            layer.removeAnimation(forKey: "motion")
            if !instantly {
                let animation = springAnimation(key, now: now, layer: layer, speed: speed)
                animation.fromValue = fromPath; animation.toValue = toPath
                layer.add(animation, forKey: "motion")
            }
        }
        animate(cpuMask, "bounds.size.height", from: 42 + p * d, to: 42 + target * d,
                now: now, speed: speed, instantly: instantly)
        for (layer, base) in shifted {
            animate(layer, "position.y", from: base + p * d, to: base + target * d,
                    now: now, speed: speed, instantly: instantly)
        }
        CATransaction.commit()
        started = now; start = instantly ? target : p; velocity = instantly ? 0 : v; destination = target
        let cpu = snapshot.module("cpu")
        cpuHeader.rootView = Header(symbol: "cpu", title: "CPU:", value: cpu.summary,
                                   tint: DemoStyle.cpu, samples: cpu.samples, expanded: expanded,
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
final class DemoControls: ObservableObject {
    let panel: MotionPanel
    @Published var expanded = false
    @Published var dark = false
    init(panel: MotionPanel) { self.panel = panel; panel.onChange = { [weak self] in self?.expanded = panel.expanded } }
    func toggle() { panel.sequenceID += 1; panel.toggle() }
}

struct ControlView: View {
    @ObservedObject var controls: DemoControls
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("一起展开，一起收起").font(.system(size: 23, weight: .semibold))
            Text("观察右侧面板：内容展开时，下方卡片、按钮和外框底边是否始终连贯。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(controls.expanded ? "收起 CPU" : "展开 CPU") { controls.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("连续反转") { controls.panel.sequence(reverse: true) }
            }.controlSize(.large)
            Button("播放展开 / 收起") { controls.panel.sequence(reverse: false) }
            Toggle("深色外观", isOn: $controls.dark).onChange(of: controls.dark) { _, v in controls.panel.updateTheme(v) }
            Divider()
            Text("按空格或点击 CPU 卡片即可切换。\n可以在运动中反复点击，感受衔接。")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("动画演示 · 数值来自已采集快照，非实时监测。\n本版仅 CPU 可展开，底部按钮用于观察运动。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("退出 Demo") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.padding(26).frame(width: 350, height: 430, alignment: .topLeading)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    struct Probe: Codable {
        let time: Double
        let outerReveal: Double
        let cpuReveal: Double
        let gpuOffset: Double
        let footerOffset: Double
        let borderReveal: Double
        let shadowReveal: Double
    }
    var panelWindow: NSPanel!
    var controlsWindow: NSWindow!
    var controls: DemoControls!
    var probeTimer: Timer?
    var probes: [Probe] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let url = Bundle.main.url(forResource: "snapshot", withExtension: "json")!
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
            let panel = MotionPanel(snapshot: snapshot)
            controls = DemoControls(panel: panel)
            let screen = NSScreen.main!.visibleFrame
            panelWindow = NSPanel(contentRect: CGRect(x: screen.maxX - 410, y: screen.maxY - DemoStyle.capacity - 55,
                                                      width: DemoStyle.width + 2 * DemoStyle.outerPadding,
                                                      height: DemoStyle.capacity + 2 * DemoStyle.outerPadding),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panelWindow.title = "Hagimi Motion Demo"
            panelWindow.isOpaque = false; panelWindow.backgroundColor = .clear
            panelWindow.hasShadow = false; panelWindow.level = .floating
            panelWindow.contentView = panel
            let startsDark = CommandLine.arguments.contains("--dark")
            panel.updateTheme(startsDark)
            controls.dark = startsDark
            panelWindow.isMovableByWindowBackground = false
            panelWindow.orderFrontRegardless()
            controlsWindow = NSWindow(contentRect: CGRect(x: screen.maxX - 775, y: screen.maxY - 465,
                                                           width: 350, height: 430),
                                       styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            controlsWindow.title = "面板动画 Demo"
            controlsWindow.contentView = NSHostingView(rootView: ControlView(controls: controls))
            controlsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if CommandLine.arguments.contains("--autotest") {
                // 仅自动验收开启主线程采样；正常演示没有逐帧回调。
                probeTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let gpu = panel.shifted[0], footer = panel.shifted[2]
                        self.probes.append(Probe(time: CACurrentMediaTime(),
                            outerReveal: (panel.outerMask.presentation() ?? panel.outerMask).bounds.height - DemoStyle.closedHeight,
                            cpuReveal: (panel.cpuMask.presentation() ?? panel.cpuMask).bounds.height - 42,
                            gpuOffset: (gpu.0.presentation() ?? gpu.0).position.y - gpu.1,
                            footerOffset: (footer.0.presentation() ?? footer.0).position.y - footer.1,
                            borderReveal: (panel.outline.presentation()?.path ?? panel.outline.path!)
                                .boundingBoxOfPath.height - DemoStyle.closedHeight,
                            shadowReveal: ((panel.contourShadow.presentation() ?? panel.contourShadow).shadowPath ?? panel.contourShadow.shadowPath!)
                                .boundingBoxOfPath.height - DemoStyle.closedHeight))
                    }
                }
                for i in 0..<16 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 0.85) { panel.toggle() }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 16) { panel.sequence(reverse: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    self.probeTimer?.invalidate()
                    if let path = ProcessInfo.processInfo.environment["DEMO_PROBE_PATH"],
                       let data = try? JSONEncoder().encode(self.probes) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                    print("complete operations=\(panel.operation) layouts=\(panel.layoutCounts.map { $0() })")
                    fflush(stdout)
                    NSApp.terminate(nil)
                }
            }
        } catch {
            print("Demo snapshot load failed: \(error)")
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = Delegate()
    application.delegate = delegate
    application.run()
}
