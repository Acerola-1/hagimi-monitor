import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 硬件全景报表独立窗口控制器。
///
/// 采用 macOS 原生窗口（AppKit + SwiftUI）承载：
/// 日常查看报表直接消费强类型 Swift 数据模型与原生组件，不创建 WKWebView。
/// 关窗时释放专用数据模型、图表状态与图标缓存，彻底避免内存残留。
/// 导出 HTML 与打印作为独立服务，仅在用户明确触发时按需执行。
@MainActor
enum ReportWindowPresenter {
    private static var window: NSWindow?
    private static var viewModel: NativeReportViewModel?
    private static var windowDelegate: ReportWindowDelegate?
    private static var themeCancellable: AnyCancellable?
    private static var printSession: TransientReportPrintSession?
    private static var printSessionID: UUID?
    private static var printGenerationTask: Task<Void, Never>?
    private static var printGenerationID: UUID?

    private static let contentRect = NSRect(x: 0, y: 0, width: 1380, height: 880)
    private static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// 打开原生硬件报表窗口；窗口先显示,数据快照在后台加载完成后更新内容。
    static func open(recorder: StatisticsRecorder, anchor: StatisticsReportAnchor? = nil) {
        let win = ensureWindow(recorder: recorder)
        win.appearance = AppDelegate.shared?.store.settings.themePreference.appearance
        focus(win)
        viewModel?.load(anchor: anchor)
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

    /// 重新加载当前报表数据快照
    static func reloadCurrentReport() {
        viewModel?.load()
    }

    /// 另存为导出独立 HTML 文件（按需生成）
    static func exportCurrentReport() {
        guard let snapshot = viewModel?.snapshot else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = "HagimiMonitor-Report.html"
        savePanel.title = String(localized: "stats.report.export.title", defaultValue: "导出硬件规格档案")

        let performExport: (URL) -> Void = { targetURL in
            Task { @MainActor in
                do {
                    let didStartAccess = targetURL.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess { targetURL.stopAccessingSecurityScopedResource() }
                    }
                    let generation = Task.detached(priority: .userInitiated) {
                        try Self.writeHTML(snapshot: snapshot, to: targetURL)
                    }
                    _ = try await generation.value
                } catch {
                    let alert = NSAlert(error: error)
                    if let window {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        if let window {
            savePanel.beginSheetModal(for: window) { response in
                guard response == .OK, let targetURL = savePanel.url else { return }
                performExport(targetURL)
            }
        } else if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            performExport(targetURL)
        }
    }

    /// 触发报表打印：按需临时创建 WebKit 打印操作，完成后立即销毁，日常查看无 WebKit 常驻。
    static func printCurrentReport() {
        guard printGenerationTask == nil, printSession == nil,
              let snapshot = viewModel?.snapshot else { return }
        let generationID = UUID()
        printGenerationID = generationID
        let generationTask = Task { @MainActor in
            defer {
                if printGenerationID == generationID {
                    printGenerationTask = nil
                    printGenerationID = nil
                }
            }
            do {
                let fileURL = try await Task.detached(priority: .userInitiated) {
                    let fileURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("HagimiMonitor-Report-\(UUID().uuidString).html")
                    do {
                        return try Self.writeHTML(snapshot: snapshot, to: fileURL)
                    } catch {
                        // 生成阶段也可能已经创建了部分文件,失败时不能把它留在临时目录。
                        try? FileManager.default.removeItem(at: fileURL)
                        throw error
                    }
                }.value

                guard !Task.isCancelled, window != nil else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                presentPrintSession(fileURL: fileURL)
            } catch {
                AppLogger.settings.error("Print generation failed: \(String(describing: error), privacy: .public)")
            }
        }
        printGenerationTask = generationTask
    }

    /// 组装导出或打印所需的单文件 HTML。调用方负责把它放到后台任务。
    nonisolated private static func writeHTML(snapshot: ReportSnapshot, to outputURL: URL) throws -> URL {
        let process = snapshot.process.flatMap { StandaloneHTMLReportExporter.processSnapshot(from: $0) }
        return try StandaloneHTMLReportExporter.write(
            to: outputURL,
            snapshot: (minutes: snapshot.minutes, hours: snapshot.hours, days: snapshot.days),
            meta: [
                "device": snapshot.meta.deviceName,
                "model": snapshot.meta.modelName,
                "os": snapshot.meta.osVersion,
                "days": snapshot.meta.recordDays,
                "appVersion": snapshot.meta.appVersion,
                "direct": snapshot.meta.isDirect
            ],
            process: process,
            hardware: snapshot.hardware
        )
    }

    /// 按需启动一次性临时 WebKit 打印流程并在结束后彻底销毁。
    private static func presentPrintSession(fileURL: URL) {
        if let staleSession = printSession {
            staleSession.finish()
        }
        guard printSession == nil else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let sessionID = UUID()
        printSessionID = sessionID
        let session = TransientReportPrintSession(
            fileURL: fileURL,
            parentWindow: window,
            onFinish: {
                guard ReportWindowPresenter.printSessionID == sessionID else { return }
                ReportWindowPresenter.printSession = nil
                ReportWindowPresenter.printSessionID = nil
            }
        )
        printSession = session
        session.start()
    }

    private static func ensureWindow(recorder: StatisticsRecorder) -> NSWindow {
        if let window, viewModel != nil {
            return window
        }

        let vm = NativeReportViewModel(recorder: recorder)
        self.viewModel = vm

        let rootView = NativeReportView(
            viewModel: vm,
            onReload: { reloadCurrentReport() },
            onPrint: { printCurrentReport() },
            onExport: { exportCurrentReport() }
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

        // 主题跟随订阅
        themeCancellable = AppDelegate.shared?.store.settings.$themePreference
            .receive(on: DispatchQueue.main)
            .sink { [weak win] preference in
                win?.appearance = preference.appearance
            }

        return win
    }

    /// 窗口关闭时的完全清理处理
    private static func handleWindowClose() {
        printGenerationTask?.cancel()
        printGenerationTask = nil
        printGenerationID = nil
        printSession?.finish()
        printSession = nil
        printSessionID = nil
        viewModel?.teardown()
        viewModel = nil
        window = nil
        windowDelegate = nil
        themeCancellable?.cancel()
        themeCancellable = nil
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

private var transientPrintSessionAssociationKey: UInt8 = 0

/// 一次性 HTML 打印会话。
///
/// 每次打印拥有自己的 WebView、导航回调和临时文件。所有出口都汇入幂等的
/// `finish()`：它只负责断开应用持有关系和删除临时文件，不把 WebKit helper
/// 进程的退出时间当成同步生命周期信号。
@MainActor
final class TransientReportPrintSession: NSObject, WKNavigationDelegate {
    typealias WebViewFactory = @MainActor () -> WKWebView?
    typealias PageLoader = @MainActor (WKWebView, URL) -> Void

    enum State: Equatable {
        case idle
        case loading
        case printing
        case finished
    }

    private(set) var state: State = .idle
    private(set) var webView: WKWebView?
    private(set) var fileURL: URL?
    private(set) var cleanupCount = 0

    private weak var parentWindow: NSWindow?
    private let onFinish: () -> Void
    private let webViewFactory: WebViewFactory
    private let pageLoader: PageLoader
    private var printOperation: NSPrintOperation?
    private var printDelayTask: Task<Void, Never>?
    private var loadingTimeoutTask: Task<Void, Never>?

    init(
        fileURL: URL,
        parentWindow: NSWindow?,
        webViewFactory: @escaping WebViewFactory = {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            return WKWebView(
                frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                configuration: configuration
            )
        },
        pageLoader: @escaping PageLoader = { webView, fileURL in
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        },
        onFinish: @escaping () -> Void = {}
    ) {
        self.fileURL = fileURL
        self.parentWindow = parentWindow
        self.webViewFactory = webViewFactory
        self.pageLoader = pageLoader
        self.onFinish = onFinish
        super.init()
    }

    func start() {
        guard state == .idle, let fileURL, let webView = webViewFactory() else {
            finish()
            return
        }
        self.webView = webView
        state = .loading
        webView.navigationDelegate = self
        objc_setAssociatedObject(
            webView,
            &transientPrintSessionAssociationKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        scheduleLoadingTimeout()
        pageLoader(webView, fileURL)
    }

    /// 可从成功、取消、导航/脚本失败以及父窗口关闭路径重复调用。
    func finish() {
        guard state != .finished else { return }
        state = .finished
        cleanupCount += 1
        printDelayTask?.cancel()
        printDelayTask = nil
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil

        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            objc_setAssociatedObject(
                webView,
                &transientPrintSessionAssociationKey,
                nil,
                .OBJC_ASSOCIATION_ASSIGN
            )
        }
        printOperation = nil
        webView = nil

        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        self.fileURL = nil
        onFinish()
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.pageDidFinish()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.navigationFailed(error)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.navigationFailed(error)
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            self?.finish()
        }
    }

    private func pageDidFinish() {
        guard state == .loading, let webView else { return }
        webView.evaluateJavaScript("enterPrintMode(); true") { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self, self.state == .loading else { return }
                if let error {
                    self.scriptFailed(error)
                } else {
                    self.schedulePrint()
                }
            }
        }
    }

    private func schedulePrint() {
        printDelayTask?.cancel()
        printDelayTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard let self, self.state == .loading else { return }
            self.beginPrint()
        }
    }

    private func beginPrint() {
        guard state == .loading, let webView else {
            finish()
            return
        }
        state = .printing
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.topMargin = 28
        printInfo.bottomMargin = 28
        printInfo.leftMargin = 28
        printInfo.rightMargin = 28
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let printOperation = webView.printOperation(with: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        self.printOperation = printOperation
        defer { finish() }
        if let parentWindow {
            printOperation.runModal(for: parentWindow, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOperation.run()
        }
    }

    private func navigationFailed(_ error: Error) {
        guard state != .finished else { return }
        AppLogger.settings.error("Transient print navigation failed: \(String(describing: error), privacy: .public)")
        finish()
    }

    private func scriptFailed(_ error: Error) {
        guard state != .finished else { return }
        AppLogger.settings.error("Transient print script failed: \(String(describing: error), privacy: .public)")
        finish()
    }

    private func scheduleLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                return
            }
            self?.handleLoadingTimeout()
        }
    }

    /// 计时器与测试共用同一条超时出口，确保只清理仍停在加载阶段的会话。
    func handleLoadingTimeout() {
        guard state == .loading else { return }
        AppLogger.settings.error("Transient print loading timed out")
        finish()
    }
}
