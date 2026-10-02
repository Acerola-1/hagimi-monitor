from pathlib import Path
import sys
repo=Path(sys.argv[1])
root=Path(__file__).resolve().parent
p=repo/'HagimiMonitor/MonitorPanelView.swift'
s=p.read_text()
if 'enum NativeCPUPageParts' not in s:
    row=s.index('private struct MetricGlassRow:')
    h=s.index('            HStack(spacing: 10) {',row)
    he=s.index('\n\n            CollapsibleDetail(',h)
    header=s[h:he]
    g=s.index('                Group {',he)
    ge=s.index('\n            }\n        }\n        .panelCardBrighten()',g)
    detail=s[g:ge]
    s=s[:g]+'                detailContent'+s[ge:]
    s=s[:h]+'            headerContent'+s[he:]
    at=s.index('    @ViewBuilder\n    private func trailingView(',row)
    def indent(part,n): return '\n'.join(line[n:] if line.startswith(' '*n) else line for line in part.splitlines())
    properties='    fileprivate var headerContent: some View {\n'+indent(header,4)+'\n    }\n\n    fileprivate var detailContent: some View {\n'+indent(detail,8)+'\n    }\n\n'
    s=s[:at]+properties+s[at:]
    s+='''

/// 独立 CPU 原生原型复用正式渲染组件，几何运动由原型宿主承担。
@MainActor
enum NativeCPUPageParts {
    static func row(module: MonitorModule, dark: Bool, expanded: Bool, processes: [TopCPUProcess], action: (() -> Void)? = nil) -> MetricGlassRow {
        let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .vibrant, colorScheme: dark ? .dark : .light))
        let ids = Set(module.kind.availableMetrics.filter(\\.isDefault).map(\\.id))
        var details = module.metrics.filter { ids.contains($0.name) }
        if module.kind == .cpu, details.contains(where: { $0.name == "thermal-pressure" }),
           let temperature = module.metrics.first(where: { $0.name == "temperature" }) {
            details.append(temperature)
        }
        let text = module.kind == .memory
            ? localizedMemoryPressure((module.pressure ?? .unknown).identifier) : module.summary
        return MetricGlassRow(module: module, theme: theme, detail: text,
            statusTint: module.kind == .memory ? theme.palette.severityTint(for: .warning) : nil,
            samples: module.kind == .memory ? module.pressureSamples : module.samples,
            details: details, isExpanded: expanded, topCPUProcesses: processes, toggleExpansion: action)
    }
    static func header(module: MonitorModule, dark: Bool, expanded: Bool, action: @escaping () -> Void) -> AnyView {
        AnyView(row(module: module, dark: dark, expanded: expanded, processes: [], action: action).headerContent
            .environment(\\.colorScheme, dark ? .dark : .light))
    }
    static func details(module: MonitorModule, processes: [TopCPUProcess], dark: Bool) -> AnyView {
        AnyView(row(module: module, dark: dark, expanded: true, processes: processes).detailContent
            .fixedSize(horizontal: false, vertical: true).environment(\\.colorScheme, dark ? .dark : .light))
    }
    static func footer(dark: Bool) -> AnyView {
        AnyView(HStack(spacing: 6) {
            Button {} label: { Label(String(localized: "panel.monitor"), systemImage: "waveform.path.ecg").frame(maxWidth: .infinity) }
                .compatibleButtonStyle(minimumHeight: MonitorConstants.panelRowHeaderHeight)
            Button {} label: { Label(String(localized: "panel.tools"), systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity) }
                .compatibleButtonStyle(minimumHeight: MonitorConstants.panelRowHeaderHeight)
            Button {} label: { Label(String(localized: "panel.settings"), systemImage: "gearshape").frame(maxWidth: .infinity) }
                .compatibleButtonStyle(minimumHeight: MonitorConstants.panelRowHeaderHeight)
        }.foregroundStyle(MonitorPalette(preference: .vibrant, colorScheme: dark ? .dark : .light).primaryText)
            .environment(\\.colorScheme, dark ? .dark : .light))
    }
}
'''
    # 私有类型不出现在原型的对外接口中。
    s=s.replace('    static func row(module:', '    private static func row(module:')
    p.write_text(s)
s=p.read_text().replace('details: details, isExpanded: expanded',
    'details: details, metricOrder: PanelOrderCatalog.defaultIDs(for: .metrics(module.kind)), isExpanded: expanded')
p.write_text(s)
p=repo/'HagimiMonitor/MonitorModels.swift' 
s=p.read_text()
if 'private let isNativeCPUDemo' not in s:
    s=s.replace('final class MonitorStore: ObservableObject {','final class MonitorStore: ObservableObject {\n    private let isNativeCPUDemo: Bool',1)
    at=s.index('    init() {',s.index('final class MonitorStore:'))
    s=s[:at]+s[at:].replace('    init() {\n        let settings = MonitorSettings()', '''    init(nativeCPUDemo: Bool = false) {
        isNativeCPUDemo = nativeCPUDemo
        let settings = MonitorSettings()
        if nativeCPUDemo {
            settings.statisticsEnabled = false
            settings.cpuShowSystemProcesses = true
        }''',1)
    s=s.replace('        fanSampler.start()\n        FanAlertService.shared.attach(to: fanSampler, settings: settings)', '        if !nativeCPUDemo {\n            fanSampler.start()\n            FanAlertService.shared.attach(to: fanSampler, settings: settings)\n        }',1)
    s=s.replace('        if settings.isVisible(.bluetooth) {\n            bluetoothSampler.start()', '        if !nativeCPUDemo, settings.isVisible(.bluetooth) {\n            bluetoothSampler.start()',1)
    s=s.replace('        bluetoothSampler.activateBLE()\n        if wasEmpty {','        if !isNativeCPUDemo { bluetoothSampler.activateBLE() }\n        if wasEmpty {',1)
    s=s.replace('    private func enabledProcessKinds() -> Set<MonitorKind> {','    private func enabledProcessKinds() -> Set<MonitorKind> {\n        if isNativeCPUDemo { return [.cpu] }',1)
    s=s.replace('        let requestedKinds = Set(kinds)','        let requestedKinds = isNativeCPUDemo ? Set(kinds).intersection([.cpu, .gpu, .memory]) : Set(kinds)',1)
    p.write_text(s)
p=repo/'HagimiMonitor/AppDelegate.swift'
s=p.read_text()
if 'private var nativeCPUDemo:' not in s:
    s=s.replace('private(set) lazy var store: MonitorStore = MonitorStore()', 'private(set) lazy var store: MonitorStore = MonitorStore(nativeCPUDemo: NativeCPUMotionDemo.enabled)\n    private var nativeCPUDemo: NativeCPUMotionDemo?',1)
    s=s.replace('        if PanelMotionExperiment.enabled {', '        if let nativeCPUDemo { nativeCPUDemo.show(); return false }\n        if PanelMotionExperiment.enabled {',1)
    s=s.replace('    func applicationDidFinishLaunching(_ notification: Notification) {','''    func applicationDidFinishLaunching(_ notification: Notification) {
        if NativeCPUMotionDemo.enabled {
            nativeCPUDemo = NativeCPUMotionDemo(store: store)
            nativeCPUDemo?.show()
            return
        }''',1)
    p.write_text(s)
s=p.read_text().replace('if let nativeCPUDemo { nativeCPUDemo.show(); return false }', 'if NativeCPUMotionDemo.enabled { nativeCPUDemo?.show(); return false }')
p.write_text(s)
p=repo/'HagimiMonitor/HagimiMonitorApp.swift'
s=p.read_text()
if 'guard !NativeCPUMotionDemo.enabled' not in s:
    s=s.replace('    init() {\n        CrashHandler.install()', '    init() {\n        guard !NativeCPUMotionDemo.enabled else { return }\n        CrashHandler.install()',1)
    p.write_text(s)
(repo/'HagimiMonitor/Diagnostics/NativeCPUMotionDemo.swift').write_text((root/'NativeCPUMotionDemo.swift').read_text())

p=repo/'HagimiMonitor/MonitorPanelView.swift'
s=p.read_text()
s=s.replace('processes: [TopCPUProcess], action: (() -> Void)? = nil) -> MetricGlassRow',
    'processes: [TopCPUProcess], order: [String]? = nil, enabledMetrics: Set<String>? = nil, action: (() -> Void)? = nil) -> MetricGlassRow')
s=s.replace('let ids = Set(module.kind.availableMetrics.filter(\\.isDefault).map(\\.id))',
    'let ids = enabledMetrics ?? Set(module.kind.availableMetrics.filter(\\.isDefault).map(\\.id))')
s=s.replace('metricOrder: PanelOrderCatalog.defaultIDs(for: .metrics(module.kind)), isExpanded: expanded',
    'metricOrder: order ?? PanelOrderCatalog.defaultIDs(for: .metrics(module.kind)), isExpanded: expanded')
s=s.replace('static func details(module: MonitorModule, processes: [TopCPUProcess], dark: Bool) -> AnyView',
    'static func details(module: MonitorModule, processes: [TopCPUProcess], dark: Bool, settings: MonitorSettings) -> AnyView')
s=s.replace('expanded: true, processes: processes).detailContent',
    'expanded: true, processes: processes, order: settings.panelOrder(for: .metrics(.cpu)), enabledMetrics: settings.enabledMetrics[.cpu]).detailContent')
p.write_text(s)
p=repo/'HagimiMonitor/HagimiMonitorApp.swift'
s=p.read_text().replace('guard !NativeCPUMotionDemo.enabled else { return }',
    'guard !NativeCPUMotionDemo.enabled else { NativeCPUMotionDemo.seedCPUUserPreferences(); return }')
p.write_text(s)
