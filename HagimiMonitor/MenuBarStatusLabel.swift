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
    enum Style {
        case menuBar
        case preview
    }

    let items: [MenuBarMetricItem]
    var style: Style = .menuBar

    private var text: String {
        items.map { metricText(for: $0.kind, value: $0.value) }
            .joined(separator: separator)
    }

    private var reservedText: String {
        items.map { metricText(for: $0.kind, value: reservedValue(for: $0.kind)) }
            .joined(separator: separator)
    }

    var body: some View {
        Text(text)
            .font(labelFont)
            .lineLimit(1)
            .allowsTightening(false)
            .minimumScaleFactor(1)
            .frame(width: reservedWidth, alignment: labelAlignment)
            .clipped()
    }

    private var labelFont: Font {
        .system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    private var measuringFont: NSFont {
        NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }

    private var fontSize: CGFloat {
        switch style {
        case .menuBar:
            9
        case .preview:
            9
        }
    }

    private var separator: String { "  " }

    private var labelAlignment: Alignment {
        switch style {
        case .menuBar:
            .leading
        case .preview:
            .center
        }
    }

    private var reservedWidth: CGFloat {
        ceil((reservedText as NSString).size(withAttributes: [.font: measuringFont]).width) + 4
    }

    private func metricText(for kind: MenuBarMetricKind, value: String) -> String {
        if kind.menuBarPrefix.isEmpty {
            value
        } else {
            "\(kind.menuBarPrefix) \(value)"
        }
    }

    private func reservedValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryLevel:
            "100%"
        case .networkDownload:
            "↓9.9G"
        case .networkUpload:
            "↑9.9G"
        case .cpuTemperature:
            "999°"
        case .storageFree:
            "9.9T"
        }
    }
}
