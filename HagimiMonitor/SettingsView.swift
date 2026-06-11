import AppKit
import SwiftUI

enum SettingsTab: String {
    case general
    case modules
    case about
}

enum SettingsSelection: Hashable {
    case general
    case module(MonitorKind)
    #if DISPLAY_CONTROL
    case display
    #endif
    case about
}

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var selection: SettingsSelection = .general

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    Label("常规", systemImage: "gearshape")
                        .tag(SettingsSelection.general)
                }

                Section("监控模块") {
                    ForEach(MonitorKind.allCases) { kind in
                        moduleRow(kind)
                    }

                    #if DISPLAY_CONTROL
                    displayModuleRow
                    #endif
                }

                Section {
                    Label("关于", systemImage: "info.circle")
                        .tag(SettingsSelection.about)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 360)
        .background(SettingsWindowTracker())
    }

    private func moduleRow(_ kind: MonitorKind) -> some View {
        HStack {
            Image(systemName: kind.symbol)
                .frame(width: 16)

            Text(kind.title)

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.isVisible(kind) },
                set: { settings.setVisible($0, for: kind) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .tag(SettingsSelection.module(kind))
    }

    #if DISPLAY_CONTROL
    private var displayModuleRow: some View {
        HStack {
            Image(systemName: "display")
                .frame(width: 16)

            Text("显示器")

            Spacer()

            Toggle("", isOn: $settings.displayModuleVisible)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .tag(SettingsSelection.display)
    }
    #endif

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(settings: settings)
        case .module(let kind):
            ModuleSettingsView(kind: kind, settings: settings)
        #if DISPLAY_CONTROL
        case .display:
            DisplayModuleSettingsView(settings: settings)
        #endif
        case .about:
            AboutSettingsView()
        }
    }
}

private struct SettingsWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowTrackingView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }

        Task { @MainActor in
            SettingsWindowPresenter.register(window)
        }
    }
}

private final class SettingsWindowTrackingView: NSView {
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
