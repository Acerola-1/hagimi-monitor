import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: MonitorSettings
    let store: MonitorStore
    @State private var selection: SettingsRoute = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SettingsSidebar(selection: $selection, settings: settings)
                    .frame(width: 164)
                    .background(.bar, ignoresSafeAreaEdges: .top)

                SettingsColumnDivider()

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(
                minWidth: 560,
                idealWidth: 600,
                minHeight: 384,
                idealHeight: 406
            )
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
        #if DISPLAY_CONTROL
        case .displayModule:
            DisplayModuleSettingsView(settings: settings)
        #endif

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
        guard let window = nsView.window else { return }
        Task { @MainActor in
            SettingsWindowPresenter.register(window)
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

        guard let window else {
            return
        }

        // 同步注册(不经 Task 延迟):此回调在窗口真正显示之前触发,
        // 让标题栏样式与居中在窗口可见前完成,消除首次打开时的闪烁与位置跳变。
        MainActor.assumeIsolated {
            SettingsWindowPresenter.register(window)
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
        case .about:
            return .about
        }
    }
}
