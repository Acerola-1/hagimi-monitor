import AppKit
import Combine
import WebKit
import UniformTypeIdentifiers

/// 硬件全景报表独立窗口控制器。
///
/// 报表以独立原生窗口内嵌 WKWebView 承载:规避 App Store 沙盒环境下
/// Safari 等外部沙盒应用无法跨容器读取应用私有目录文件(NSURLErrorDomain -3001)的限制,
/// 同时为用户提供沉浸式的软硬件规格查阅体验,支持系统打印、另存为与页面交互。
@MainActor
enum ReportWindowPresenter {
    private static var window: NSWindow?
    private static var webView: WKWebView?
    private static var currentURL: URL?
    private static let toolbarDelegate = ReportToolbarDelegate()
    /// 加载完成后要定位的板块;每次打开只定位一次,用户随后自行滚动不再干预。
    private static var pendingAnchor: StatisticsReportAnchor?
    private static let navigationDelegate = ReportNavigationDelegate()
    /// 主题订阅:窗口长驻,用户切换深浅色后报表窗口立即跟随(与设置窗口同规则)。
    private static var themeCancellable: AnyCancellable?
    /// 报表窗口内容区:按内容最佳宽度给足(内容 1140 上限 + 侧栏 + 内边距 + 余量),
    /// 打开即完整显示;宽度全程锁死(只能调纵向),纵向下限守双列可读。
    private static let contentRect = NSRect(x: 0, y: 0, width: 1380, height: 880)
    private static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    /// 拉伸代理需强持有:NSWindow.delegate 是弱引用,内联新实例赋值后会立刻释放,
    /// windowWillResize/windowDidResize 将不再触发(与设置窗口同一范式)。
    private static let resizeDelegate = ReportResizeDelegate(
        fixedWidth: NSWindow.frameRect(forContentRect: contentRect, styleMask: windowStyleMask).width,
        minHeight: 640
    )
    /// 实时刷新定时器:报表本体是打开时生成的快照,但右栏「运行状态」组要跟着走。
    /// 只在窗口可见时跑(见 `pushLiveReadings`),窗口关闭时由 `closeObserver` 停掉。
    private static var liveTimer: Timer?
    /// 窗口关闭观察者。窗口常驻复用(`isReleasedWhenClosed = false`),不监听关闭事件
    /// 的话关窗后 timer 会一直每秒空跑一次 Task+guard。
    private static var closeObserver: NSObjectProtocol?

    /// 打开或刷新硬件报表窗口;带 anchor 时加载完成后滚到对应板块。
    static func open(url: URL, anchor: StatisticsReportAnchor? = nil) {
        currentURL = url
        pendingAnchor = anchor
        let win = ensureWindow()
        win.appearance = AppDelegate.shared?.store.settings.themePreference.appearance
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        startLiveUpdates()
        focus(win)
    }

    /// 页面加载完成后定位板块;板块被当前范围隐藏或标题对不上时停在页首。
    static func scrollToPendingAnchor(in webView: WKWebView) {
        guard let anchor = pendingAnchor else { return }
        pendingAnchor = nil
        webView.evaluateJavaScript(anchorScrollScript(title: anchor.sectionTitle), completionHandler: nil)
    }

    /// 按板块标题匹配,与模板粘性导航同一依据,不依赖具体元素 id。
    private static func anchorScrollScript(title: String) -> String {
        let literal = (try? JSONEncoder().encode(title))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function () {
          const title = \(literal);
          const sections = Array.from(document.querySelectorAll('#content > section'));
          const match = sections.find((sec) => ((sec.querySelector('h2') || {}).textContent || '').trim() === title);
          if (!match || match.hidden) return false;
          match.scrollIntoView({ block: 'start' });
          return true;
        })();
        """
    }

    // MARK: - 实时读数

    /// 启动每秒推送。窗口常驻复用,重复打开不重复建定时器。
    private static func startLiveUpdates() {
        guard liveTimer == nil else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in pushLiveReadings() }
        }
    }

    private static func stopLiveUpdates() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    /// 把 `MonitorStore` 的当前读数推给网页。
    ///
    /// 遮挡门控:窗口不可见(最小化、被完全遮挡、切到别的空间)时不推——
    /// 每秒一次 `evaluateJavaScript` 对常驻窗口是白烧 CPU,而用户根本看不到。
    private static func pushLiveReadings() {
        guard let win = window, win.isVisible, win.occlusionState.contains(.visible),
              let webView,
              let store = AppDelegate.shared?.store else {
            return
        }
        let readings = HardwareLiveReadings.snapshot(from: store)
        guard !readings.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: readings),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.__HAGIMI_HARDWARE_LIVE__ && window.__HAGIMI_HARDWARE_LIVE__(\(json));")
    }

    /// 聚焦窗口并激活应用。
    private static func focus(_ win: NSWindow) {
        if !win.isVisible {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 另存为导出独立 HTML 文件。
    static func exportCurrentReport() {
        guard let currentURL else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = "HagimiMonitor-Report.html"
        savePanel.title = String(localized: "stats.report.export.title", defaultValue: "导出硬件规格档案")

        let performCopy: (URL) -> Void = { targetURL in
            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.copyItem(at: currentURL, to: targetURL)
            } catch {
                let alert = NSAlert(error: error)
                if let window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }

        if let window {
            savePanel.beginSheetModal(for: window) { response in
                guard response == .OK, let targetURL = savePanel.url else { return }
                performCopy(targetURL)
            }
        } else if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            performCopy(targetURL)
        }
    }

    /// 触发原生报表打印。先通知网页切换到打印浅色模式并完成重绘,
    /// 随后调起 WKWebView 原生 NSPrintOperation,弹出系统打印面板或保存为 PDF。
    static func printCurrentReport() {
        guard let webView else { return }
        webView.evaluateJavaScript("enterPrintMode(); true") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
                printInfo.topMargin = 28
                printInfo.bottomMargin = 28
                printInfo.leftMargin = 28
                printInfo.rightMargin = 28
                printInfo.isHorizontallyCentered = true
                printInfo.isVerticallyCentered = false
                let printOp = webView.printOperation(with: printInfo)
                printOp.showsPrintPanel = true
                printOp.showsProgressPanel = true
                if let window = self.window {
                    printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    printOp.run()
                }
                webView.evaluateJavaScript("exitPrintMode(); true", completionHandler: nil)
            }
        }
    }

    /// 重新加载当前报表。
    static func reloadCurrentReport() {
        webView?.reload()
    }

    private static let scriptMessageHandler = ReportScriptMessageHandler()

    private static func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        config.userContentController.add(scriptMessageHandler, name: "hagimiPrint")
        // 非持久数据存储:报表窗口每次加载都从磁盘读新文件,不带 WebKit 文件缓存,
        // 避免重新生成后仍显示旧模板/旧图标。
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let view = WKWebView(frame: .zero, configuration: config)
        view.underPageBackgroundColor = .clear
        view.navigationDelegate = navigationDelegate
        self.webView = view

        // 默认尺寸按内容最佳宽度给足,打开即完整显示,不让用户再手动拉宽。
        let lockedFrameWidth = NSWindow.frameRect(forContentRect: contentRect, styleMask: windowStyleMask).width
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: windowStyleMask,
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "stats.report.window.title", defaultValue: "硬件规格档案 · HagimiMonitor")
        win.titleVisibility = .visible
        win.minSize = NSSize(width: lockedFrameWidth, height: 640)
        win.delegate = resizeDelegate
        win.isReleasedWhenClosed = false
        win.contentView = view

        let toolbar = NSToolbar(identifier: "ReportWindowToolbar")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        win.toolbar = toolbar
        win.toolbarStyle = .unified

        // 关窗即停推;重新打开时 startLiveUpdates() 会再起(它按 liveTimer == nil 去重)。
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in
            Task { @MainActor in stopLiveUpdates() }
        }

        self.window = win

        // 建窗即订阅:窗口常驻复用,不订阅的话改主题后只有重开才能跟上。
        themeCancellable = AppDelegate.shared?.store.settings.$themePreference
            .receive(on: DispatchQueue.main)
            .sink { [weak win] preference in
                win?.appearance = preference.appearance
            }

        return win
    }
}

/// 报表加载完成回调:应用打开时携带的板块锚点。
final class ReportNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            ReportWindowPresenter.scrollToPendingAnchor(in: webView)
        }
    }
}

/// 承接来自 WKWebView 内部的 JavaScript 打印桥接调用。
final class ReportScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "hagimiPrint" {
            Task { @MainActor in
                ReportWindowPresenter.printCurrentReport()
            }
        }
    }
}

/// 报表窗口:宽度锁死、高度随意的伸缩裁定,与设置窗口同一套代理范式。
/// 用户拖拽横边/对角时宽度一律回归固定值,只保留纵向伸缩。
@MainActor
private final class ReportResizeDelegate: NSObject, NSWindowDelegate {
    private let fixedWidth: CGFloat
    private let minHeight: CGFloat
    private var liveResizeOriginX: CGFloat?

    init(fixedWidth: CGFloat, minHeight: CGFloat) {
        self.fixedWidth = fixedWidth
        self.minHeight = minHeight
        super.init()
    }

    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        NSSize(width: fixedWidth, height: max(size.height, minHeight))
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            liveResizeOriginX = window.frame.origin.x
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.inLiveResize,
              let liveResizeOriginX else { return }
        guard window.frame.origin.x != liveResizeOriginX else { return }
        window.setFrameOrigin(NSPoint(x: liveResizeOriginX, y: window.frame.origin.y))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeOriginX = nil
    }
}

/// 报表窗口顶部工具栏代理。
final class ReportToolbarDelegate: NSObject, NSToolbarDelegate {
    private static let exportItemID = NSToolbarItem.Identifier("ReportExportItem")
    private static let printItemID = NSToolbarItem.Identifier("ReportPrintItem")
    private static let reloadItemID = NSToolbarItem.Identifier("ReportReloadItem")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.reloadItemID, Self.printItemID, Self.exportItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.reloadItemID, Self.printItemID, Self.exportItemID]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.exportItemID:
            item.label = String(localized: "stats.report.toolbar.export", defaultValue: "导出")
            item.toolTip = String(localized: "stats.report.toolbar.export.tooltip", defaultValue: "另存为 HTML 文件")
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")
            item.target = self
            item.action = #selector(handleExport)
            return item
        case Self.printItemID:
            item.label = String(localized: "stats.report.toolbar.print", defaultValue: "打印")
            item.toolTip = String(localized: "stats.report.toolbar.print.tooltip", defaultValue: "打印或保存为 PDF")
            item.image = NSImage(systemSymbolName: "printer", accessibilityDescription: "Print")
            item.target = self
            item.action = #selector(handlePrint)
            return item
        case Self.reloadItemID:
            item.label = String(localized: "stats.report.toolbar.reload", defaultValue: "刷新")
            item.toolTip = String(localized: "stats.report.toolbar.reload.tooltip", defaultValue: "重新载入报表")
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.target = self
            item.action = #selector(handleReload)
            return item
        default:
            return nil
        }
    }

    @objc private func handleExport() {
        Task { @MainActor in
            ReportWindowPresenter.exportCurrentReport()
        }
    }

    @objc private func handlePrint() {
        Task { @MainActor in
            ReportWindowPresenter.printCurrentReport()
        }
    }

    @objc private func handleReload() {
        Task { @MainActor in
            ReportWindowPresenter.reloadCurrentReport()
        }
    }
}
