import AppKit
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

    /// 打开或刷新硬件报表窗口。
    static func open(url: URL) {
        currentURL = url
        let win = ensureWindow()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        focus(win)
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

        let view = WKWebView(frame: .zero, configuration: config)
        view.underPageBackgroundColor = .clear
        self.webView = view

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "stats.report.window.title", defaultValue: "硬件规格档案 · HagimiMonitor")
        win.titleVisibility = .visible
        win.minSize = NSSize(width: 860, height: 580)
        win.isReleasedWhenClosed = false
        win.contentView = view

        let toolbar = NSToolbar(identifier: "ReportWindowToolbar")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        win.toolbar = toolbar
        win.toolbarStyle = .unified

        self.window = win
        return win
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
