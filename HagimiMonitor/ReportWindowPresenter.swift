import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// 硬件全景报表独立窗口控制器。
///
/// 采用 macOS 原生窗口（AppKit + SwiftUI）承载：
/// 日常查看、打印及多格式导出均直接消费强类型 Swift 数据模型与原生组件，不创建 WKWebView。
/// 关窗时释放专用数据模型、图表状态与图标缓存，彻底避免内存残留。
@MainActor
enum ReportWindowPresenter {
    static let commandState = ReportCommandState()
    private static var window: NSWindow?
    private static var exportBusy = false
    private static var viewModel: NativeReportViewModel?
    private static var windowDelegate: ReportWindowDelegate?
    private static var themeCancellable: AnyCancellable?
    private static var activePrintOperation: NSPrintOperation?
    private static var printDelegate: PrintOperationDelegate?

    static func refreshCommands() {
        commandState.isAvailable = window != nil && NSApp.keyWindow === window
            && viewModel?.committedExportRange() != nil
            && !exportBusy && window?.attachedSheet == nil
            && activePrintOperation == nil
        commandState.isExporting = exportBusy
    }

    private static let contentRect = NSRect(x: 0, y: 0, width: 1380, height: 880)
    private static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// 打开原生硬件报表窗口；窗口先显示，数据快照在后台加载完成后更新内容。
    static func open(recorder: StatisticsRecorder, anchor: StatisticsReportAnchor? = nil) {
        open(recorder: recorder, context: StatisticsReportContext(anchor: anchor))
    }

    /// 携带范围、模块、应用与指标上下文打开；已有窗口复用同一实例并提交新上下文。
    static func open(recorder: StatisticsRecorder, context: StatisticsReportContext) {
        let win = ensureWindow(recorder: recorder)
        win.appearance = AppDelegate.shared?.store.settings.themePreference.appearance
        focus(win)
        viewModel?.apply(context)
        windowDelegate?.refreshVisibility()
    }

    /// 聚焦窗口并激活应用。
    private static func focus(_ win: NSWindow) {
        if !win.isVisible {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 重新加载当前报表数据快照；保留当前范围与深链目标。
    static func reloadCurrentReport() {
        viewModel?.refreshCurrentReport()
    }

    /// 另存为导出统计报表（支持 PDF / Markdown / CSV / JSON）。
    static func exportCurrentReport(format: ReportBundleExportFormat = .pdf) {
        guard let snapshot = viewModel?.snapshot,
              let rangeModel = viewModel?.rangeModel,
              viewModel?.committedExportRange() != nil else { return }
        guard !exportBusy, activePrintOperation == nil else { return }

        exportBusy = true
        refreshCommands()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.utType]
        savePanel.nameFieldStringValue = ReportExportService.defaultFileName(for: format)
        savePanel.title = String(localized: "stats.report.export.title", defaultValue: "导出统计报表")

        let performExport: (URL) -> Void = { targetURL in
            Task { @MainActor in
                defer {
                    exportBusy = false
                    refreshCommands()
                }
                do {
                    let didStartAccess = targetURL.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess { targetURL.stopAccessingSecurityScopedResource() }
                    }
                    let meta = snapshot.meta
                    let hardware = snapshot.hardware
                    let data: Data
                    switch format {
                    case .pdf:
                        data = ReportExportService.renderPDFData(model: rangeModel, meta: meta, hardware: hardware)
                    case .markdown:
                        data = try await Task.detached(priority: .userInitiated) {
                            let md = ReportExportService.generateMarkdownReport(model: rangeModel, meta: meta, hardware: hardware)
                            return Data(md.utf8)
                        }.value
                    case .csv:
                        let rows = rangeModel.rows
                        let bucketSeconds = rangeModel.granularity.bucketSeconds
                        data = try await Task.detached(priority: .userInitiated) {
                            let csv = ReportDataExporter.generateCSV(rows: rows, bucketSeconds: bucketSeconds)
                            return Data(csv.utf8)
                        }.value
                    case .json:
                        data = try await Task.detached(priority: .userInitiated) {
                            try ReportExportService.generateJSONReport(model: rangeModel, meta: meta)
                        }.value
                    }
                    try data.write(to: targetURL, options: .atomic)
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                } catch {
                    AppLogger.settings.error("Report export failed: \(String(describing: error), privacy: .public)")
                    presentOutputError(error)
                }
            }
        }

        if let window {
            savePanel.beginSheetModal(for: window) { response in
                guard response == .OK, let targetURL = savePanel.url else {
                    exportBusy = false
                    refreshCommands()
                    return
                }
                performExport(targetURL)
            }
        } else if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            performExport(targetURL)
        } else {
            exportBusy = false
            refreshCommands()
        }
    }

    /// 系统打印使用与直接导出相同的分页内容。
    static func printCurrentReport() {
        guard !exportBusy, activePrintOperation == nil,
              let snapshot = viewModel?.snapshot,
              let rangeModel = viewModel?.rangeModel,
              viewModel?.committedExportRange() != nil else { return }

        guard let operation = ReportExportService.makePrintOperation(
            model: rangeModel,
            meta: snapshot.meta,
            hardware: snapshot.hardware
        ) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "stats.report.print-interrupted")
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }
        activePrintOperation = operation
        refreshCommands()

        if let window {
            let delegate = PrintOperationDelegate {
                activePrintOperation = nil
                printDelegate = nil
                refreshCommands()
            }
            printDelegate = delegate
            operation.runModal(
                for: window,
                delegate: delegate,
                didRun: #selector(PrintOperationDelegate.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            operation.run()
            activePrintOperation = nil
            refreshCommands()
        }
    }

    private static func presentOutputError(_ error: Error) {
        guard let window, window.isVisible, window.attachedSheet == nil else {
            NSAlert(error: error).runModal()
            return
        }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private static func ensureWindow(recorder: StatisticsRecorder) -> NSWindow {
        if let window, viewModel != nil {
            return window
        }

        let vm = NativeReportViewModel(recorder: recorder)
        self.viewModel = vm
        commandState.observe(vm)

        let rootView = NativeReportView(
            viewModel: vm,
            onReload: { reloadCurrentReport() },
            onPrint: { printCurrentReport() },
            onExport: { format in exportCurrentReport(format: format) }
        )

        let hostingView = NSHostingView(rootView: rootView)
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: windowStyleMask,
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "report.ui.windowTitle")
        win.autorecalculatesKeyViewLoop = true
        win.titleVisibility = .visible
        win.minSize = NSSize(width: 1100, height: 640)
        win.contentView = hostingView
        win.isReleasedWhenClosed = false

        let del = ReportWindowDelegate(
            minWidth: 1100,
            minHeight: 640,
            onClose: {
                handleWindowClose()
            },
            onVisibilityChange: { [weak vm] isVisible in
                vm?.setWindowVisible(isVisible)
            }
        )
        win.delegate = del
        del.attach(to: win)
        self.windowDelegate = del
        self.window = win

        themeCancellable = AppDelegate.shared?.store.settings.$themePreference
            .receive(on: DispatchQueue.main)
            .sink { [weak win] preference in
                win?.appearance = preference.appearance
            }

        return win
    }

    /// 窗口关闭时的完全清理处理
    private static func handleWindowClose() {
        activePrintOperation = nil
        printDelegate = nil
        viewModel?.teardown()
        viewModel = nil
        window = nil
        refreshCommands()
        windowDelegate = nil
        themeCancellable?.cancel()
        themeCancellable = nil
    }
}

@MainActor
private final class PrintOperationDelegate: NSObject {
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        onComplete()
    }
}

/// 自动管理多个 NotificationCenter 观察者生命周期的包装器。
/// 安全不变式：在 deinit 时自动注销所有观察者，避免在 MainActor 隔离类的 deinit 中访问非 Sendable 数组。
nonisolated private final class NotificationObserversBox: @unchecked Sendable {
    private var observers: [any NSObjectProtocol] = []

    func add(_ observer: any NSObjectProtocol) {
        observers.append(observer)
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }
}

/// 报表窗口代理：负责尺寸限制、关窗清理与可见性状态门控。
@MainActor
final class ReportWindowDelegate: NSObject, NSWindowDelegate {
    private let minWidth: CGFloat
    private let minHeight: CGFloat
    private let onClose: () -> Void
    private let onVisibilityChange: ((Bool) -> Void)?
    private weak var window: NSWindow?
    private let observersBox = NotificationObserversBox()
    private var lastVisibility = false

    init(
        minWidth: CGFloat,
        minHeight: CGFloat,
        onClose: @escaping () -> Void,
        onVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.onClose = onClose
        self.onVisibilityChange = onVisibilityChange
        super.init()
        let center = NotificationCenter.default
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observersBox.add(center.addObserver(
                forName: name,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshVisibility()
                }
            })
        }
    }

    func attach(to window: NSWindow) {
        self.window = window
        refreshVisibility()
    }

    func refreshVisibility() {
        guard let window else {
            updateVisibility(false)
            return
        }
        let visible = window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
            && !NSApp.isHidden
        updateVisibility(visible)
    }

    private func updateVisibility(_ visible: Bool) {
        guard visible != lastVisibility else { return }
        lastVisibility = visible
        onVisibilityChange?(visible)
    }

    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        NSSize(width: max(size.width, minWidth), height: max(size.height, minHeight))
    }

    func windowWillClose(_ notification: Notification) {
        updateVisibility(false)
        onClose()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        refreshVisibility()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        refreshVisibility()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        refreshVisibility()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshVisibility()
    }

    func windowDidResignKey(_ notification: Notification) {
        refreshVisibility()
    }
}

/// 菜单和工具栏共享当前窗口的可执行状态。
@MainActor
final class ReportCommandState: ObservableObject {
    @Published var isAvailable = false
    @Published var isExporting = false
    private var subscriptions = Set<AnyCancellable>()
    private var modelSubscription: AnyCancellable?

    init() {
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification))
            .receive(on: RunLoop.main)
            .sink { _ in ReportWindowPresenter.refreshCommands() }
            .store(in: &subscriptions)
    }

    func observe(_ model: NativeReportViewModel) {
        modelSubscription = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { _ in ReportWindowPresenter.refreshCommands() }
    }
}
