import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var selection: SettingsRoute = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, settings: settings)
                .frame(width: 164)
                .background(.bar)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: 560,
            idealWidth: 600,
            minHeight: 360,
            idealHeight: 382
        )
        .background(SettingsWindowTracker(selection: $selection))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(settings: settings)
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

        Task { @MainActor in
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
