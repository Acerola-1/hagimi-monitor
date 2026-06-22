import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: MonitorStore
    let darkMode: Bool

    var body: some View {
        switch store.settings.menuBarDisplayMode {
        case .ring:
            Image(nsImage: MenuBarComputeRingIcon.image(
                load: store.displayedComputeLoad,
                darkMode: darkMode,
                loadLevel: store.haloRingLoadLevel
            ))
            .resizable()
            .frame(width: 18, height: 18)
            .help("HagimiMonitor")
        case .metrics:
            MenuBarMetricLabel(items: store.menuBarMetricItems)
                .help("HagimiMonitor")
        }
    }
}

struct MenuBarMetricLabel: View {
    let items: [MenuBarMetricItem]

    private var text: String {
        items.map { item in
            if item.kind.menuBarPrefix.isEmpty {
                item.value
            } else {
                "\(item.kind.menuBarPrefix) \(item.value)"
            }
        }
        .joined(separator: "   ")
    }

    private var reservedText: String {
        items.map { item in
            if item.kind.menuBarPrefix.isEmpty {
                reservedValue(for: item.kind)
            } else {
                "\(item.kind.menuBarPrefix) \(reservedValue(for: item.kind))"
            }
        }
        .joined(separator: "   ")
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .frame(width: reservedWidth, alignment: .center)
    }

    private var reservedWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return ceil((reservedText as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    private func reservedValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryLevel:
            "100%"
        case .networkDownload:
            "↓999M"
        case .networkUpload:
            "↑999M"
        case .cpuTemperature:
            "100°"
        case .storageFree:
            "999G"
        }
    }
}
