from pathlib import Path
p=Path(__file__).resolve().parent
s=(p/'Demo.swift').read_text()
style=s[s.index('enum DemoStyle {'):s.index('struct Snapshot:')]
style=style.replace('static let closedHeight: CGFloat = 202','static let closedHeight: CGFloat = 194').replace('static let capacity: CGFloat = closedHeight + revealHeight + 64','static let capacity: CGFloat = 780')
views=s[s.index('final class FlippedView:'):s.index('@MainActor\nfinal class MotionPanel:')]
views=views.replace('Text("SYSTEM · SNAPSHOT")','Text("SYSTEM · LIVE")')
body=s[s.index('@MainActor\nfinal class MotionPanel:'):s.index('@MainActor\nfinal class DemoControls:')]
body=body.replace('let snapshot: Snapshot','let store: MonitorStore')
body=body.replace('var cpuHeader: NSHostingView<Header>!', '''var cpuHeader: NSHostingView<AnyView>!
    var detailHost: NSHostingView<AnyView>!
    var otherHeaders: [(MonitorKind, NSHostingView<AnyView>)] = []
    var footerHost: NSHostingView<AnyView>!
    var revealHeight: CGFloat = 284
    var updates = 0
    var deferredRefresh = 0''')
body=body.replace('42 + DemoStyle.revealHeight','DemoStyle.capacity - 34').replace('height: 42)','height: 34)')
body=body.replace('init(snapshot: Snapshot) {\n        self.snapshot = snapshot','init(store: MonitorStore) {\n        self.store = store')
a=body.index('        let cpu = snapshot.module("cpu")');b=body.index('        shifted.append((footer.layer!,',a)
body=body[:a]+'''        cpuHeader = mount(NativeCPUPageParts.header(module: module(.cpu), dark: false, expanded: false, action: { [weak self] in self?.toggle() }),
                          frame: CGRect(x: 0, y: 0, width: 328, height: 34), into: cpuCard)
        detailHost = mount(NativeCPUPageParts.details(module: module(.cpu), processes: store.topCPUProcesses, dark: false),
                          frame: CGRect(x: 0, y: 34, width: 328, height: 284), into: cpuCard)
        makeRow(kind: "gpu", tint: DemoStyle.gpu, y: 74, height: 34)
        makeRow(kind: "memory", tint: DemoStyle.memory, y: 114, height: 34)
        let footer = mount(NativeCPUPageParts.footer(dark: false), frame: CGRect(x: 6, y: 154, width: 328, height: 34), into: surface)
        footerHost = footer
''' + body[b:]
body=body.replace('func makeRow(kind: String, symbol: String, title: String, tint: Color, y: CGFloat, height: CGFloat)', 'func makeRow(kind: String, tint: Color, y: CGFloat, height: CGFloat)')
a=body.index('        let module = snapshot.module(kind)');b=body.index('        shifted.append((row.layer!',a)
body=body[:a]+'''        let kind = MonitorKind(rawValue: kind)!
        let host = mount(NativeCPUPageParts.header(module: module(kind), dark: false, expanded: false, action: {}), frame: row.bounds, into: row)
        otherHeaders.append((kind, host))
''' + body[b:]
body=body.replace('let d = DemoStyle.revealHeight','let d = revealHeight').replace('from: 42 + p * d, to: 42 + target * d','from: 34 + p * d, to: 34 + target * d')
a=body.index('        let cpu = snapshot.module("cpu")');b=body.index('        operation += 1',a)
body=body[:a]+'''        store.beginExpansionAnimation()
        cpuHeader.rootView = NativeCPUPageParts.header(module: module(.cpu), dark: dark, expanded: expanded,
            action: { [weak self] in self?.toggle() })
''' + body[b:]
# Theme changes refresh the original views without changing their geometry every frame.
needle='    func sequence(reverse: Bool) {'
a=body.index(needle)
body=body[:a]+'''    func module(_ kind: MonitorKind) -> MonitorModule {
        store.modules.first { $0.kind == kind } ?? .placeholder(kind)
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
        detailHost.rootView = NativeCPUPageParts.details(module: module(.cpu), processes: store.topCPUProcesses, dark: dark)
        detailHost.layoutSubtreeIfNeeded()
        let natural = max(1, detailHost.fittingSize.height)
        detailHost.setFrameSize(CGSize(width: 328, height: natural))
        if abs(natural - revealHeight) > 0.5 {
            revealHeight = natural
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let amount = expanded ? natural : 0
            outerMask.bounds.size.height = DemoStyle.closedHeight + amount
            cpuMask.bounds.size.height = 34 + amount
            outline.path = contour(DemoStyle.closedHeight + amount)
            contourShadow.shadowPath = outline.path
            for (layer, base) in shifted { layer.position.y = base + amount }
            CATransaction.commit()
        }
        for (kind, host) in otherHeaders {
            host.rootView = NativeCPUPageParts.header(module: module(kind), dark: dark, expanded: false, action: {})
        }
        footerHost.rootView = NativeCPUPageParts.footer(dark: dark)
        updates += 1
        print("native-cpu update=\\(updates) cpu=\\(module(.cpu).summary) detail-height=\\(natural) processes=\\(store.topCPUProcesses.map(\\.name).joined(separator: ","))")
        fflush(stdout)
    }

''' + body[a:]
# End theme update after transaction commit with one content refresh.
a=body.index('    func updateTheme(');b=body.index('    func module(',a)
piece=body[a:b].replace('        CATransaction.commit()\n    }','        CATransaction.commit()\n        if detailHost != nil { refreshViews() }\n    }')
body=body[:a]+piece+body[b:]
# Keep renderer type names independent of existing project names.
for old,new in [('DemoStyle','NativeCPUStyle'),('FlippedView','NativeCPUFlippedView'),('FlippedEffectView','NativeCPUEffectView'),('PanelTitle','NativeCPUTitle'),('MotionPanel','NativeCPUAnimator'),('StaticHost','NativeCPUHost')]:
    style=style.replace(old,new); views=views.replace(old,new); body=body.replace(old,new)
header='''import AppKit
import Combine
import SwiftUI
import QuartzCore

final class NativeCPUHost<Content: View>: NSHostingView<Content> {
    var layoutCount = 0
    override func layout() { layoutCount += 1; super.layout() }
}

'''
coordinator='''
@MainActor
final class NativeCPUMotionDemo: ObservableObject {
    static let enabled = ProcessInfo.processInfo.environment["HAGIMI_NATIVE_CPU_DEMO"] == "1"
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
                print("complete operations=\\(self.panel.operation) updates=\\(self.panel.updates) layouts=\\(self.panel.layoutCounts.map { $0() })")
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
'''
(p/'NativeCPUMotionDemo.swift').write_text(header+style+views+body+coordinator)
