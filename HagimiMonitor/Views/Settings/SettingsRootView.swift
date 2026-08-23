import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: MonitorSettings
    let store: MonitorStore
    @State private var selection: SettingsRoute = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, settings: settings, fanAvailable: store.fanAvailable)
                .frame(width: 164)
                .background {
                    // 26 上 `.sidebar` 列表样式自带系统液态玻璃侧栏,
                    // 手铺 `.bar` 会把它压成平面材质,仅在 15 上补铺。
                    if #unavailable(macOS 26) {
                        Rectangle()
                            .fill(.bar)
                            .ignoresSafeArea(edges: .top)
                    }
                }

            SettingsColumnDivider()

            // 内容区忽略顶部安全区直达窗口顶边:标题栏由空 unified 工具栏 +
            // 透明标题栏抹平,右栏背景与窗口背景同为 windowBackgroundColor,
            // 顶部不再出现从红绿灯延伸过来的横条。页面自身的顶边距提供呼吸空间。
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea(edges: .top)
        }
        .background(SettingsWindowTracker(selection: $selection))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(settings: settings, store: store)
        case .module(let kind):
            ModuleSettingsView(kind: kind, settings: settings)
        case .displayModule:
            #if DISPLAY_CONTROL
            DisplayModuleSettingsView(settings: settings)
            #else
            DisplayInfoSettingsView(settings: settings)
            #endif

        case .statistics:
            StatisticsSettingsView(recorder: store.statisticsRecorder) {
                selection = .storage
            }

        case .storage:
            StorageSettingsView(recorder: store.statisticsRecorder) {
                selection = .statistics
            }

        case .about:
            AboutSettingsView()
        }
    }
}

/// 侧栏与内容区之间的分隔线：上下两端渐隐，避免通顶到底的硬线在两种不同材质
/// （侧栏的 `.bar` 模糊材质、内容区的 `.regularMaterial`）交界处显得生硬。
private struct SettingsColumnDivider: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Color(nsColor: .separatorColor).opacity(0.6), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .ignoresSafeArea(edges: .top)
    }
}

struct SettingsWindowTracker: NSViewRepresentable {
    @Binding var selection: SettingsRoute

    func makeNSView(context: Context) -> NSView {
        SettingsWindowTrackingView(frame: .zero) { tab in
            Task { @MainActor in
                if let route = tab.route {
                    selection = route
                }
            }
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard nsView.window != nil else { return }
        Task { @MainActor in
            SettingsWindowPresenter.settingsViewDidAppear()
        }

        if let view = nsView as? SettingsWindowTrackingView {
            view.onTabChanged = { tab in
                Task { @MainActor in
                    if let route = tab.route {
                        selection = route
                    }
                }
            }
        }
    }
}

private final class SettingsWindowTrackingView: NSView {
    var onTabChanged: ((SettingsTab) -> Void)?
    private var observer: NSObjectProtocol?

    init(frame frameRect: NSRect, onTabChanged: @escaping (SettingsTab) -> Void) {
        self.onTabChanged = onTabChanged
        super.init(frame: frameRect)

        observer = NotificationCenter.default.addObserver(
            forName: SettingsWindowPresenter.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let tabValue = note.userInfo?[SettingsWindowPresenter.tabUserInfoKey] as? String,
                  let tab = SettingsTab(rawValue: tabValue) else { return }
            self?.onTabChanged?(tab)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            return
        }

        // 同步回调(不经 Task 延迟):此时路由观察者已随跟踪视图创建完毕,
        // 补发窗口打开时指定但尚未消费的目标页。
        MainActor.assumeIsolated {
            SettingsWindowPresenter.settingsViewDidAppear()
        }
    }
}

extension SettingsTab {
    var route: SettingsRoute? {
        switch self {
        case .general:
            return .general
        case .modules:
            return nil
        case .statistics:
            return .statistics
        case .storage:
            return .storage
        case .about:
            return .about
        }
    }
}
