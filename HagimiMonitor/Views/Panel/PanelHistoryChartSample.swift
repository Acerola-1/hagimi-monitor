#if DEBUG
import AppKit
import SwiftUI

/// 独立样例仅构造视图输入，不接入采样、统计和真实设备设置。
@MainActor
enum PanelHistoryChartSample {
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HagimiPanelChartBaselineSample") as? Bool == true
    }

    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 410),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "panel.chart.sample.title")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PanelHistoryChartSampleView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window
        NSApp.activate()
    }
}

private struct PanelHistoryChartSampleView: View {
    @State private var dark = false

    private var theme: MonitorPanelTheme {
        MonitorPanelTheme(palette: MonitorPalette(preference: .vibrant, colorScheme: dark ? .dark : .light))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("panel.chart.sample.notice")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
            Picker("panel.chart.sample.appearance", selection: $dark) {
                Text("panel.chart.sample.light").tag(false)
                Text("panel.chart.sample.dark").tag(true)
            }
            .pickerStyle(.segmented)
            sampleRow(.cpu, value: "10%", samples: Array(repeating: 10, count: MonitorConstants.sparklineMaxPoints))
            sampleRow(.gpu, value: "90%", samples: Array(repeating: 90, count: MonitorConstants.sparklineMaxPoints))
            VStack(alignment: .leading, spacing: 4) {
                sampleRow(.fan, value: "2600 RPM", samples: halfHistory(before: 0, after: 2600),
                          scale: PanelChartScale(upper: 6500))
                Text("panel.chart.sample.zero-transition")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 4) {
                sampleRow(.memory, value: "65%", samples: halfHistory(before: .nan, after: 65))
                Text("panel.chart.sample.missing-transition")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(20)
        .frame(width: 400, height: 410, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(dark ? .dark : .light)
    }

    private func halfHistory(before: Double, after: Double) -> [Double] {
        let half = MonitorConstants.sparklineMaxPoints / 2
        return Array(repeating: before, count: half)
            + Array(repeating: after, count: MonitorConstants.sparklineMaxPoints - half)
    }

    private func sampleRow(_ kind: MonitorKind, value: String, samples: [Double],
                           scale: PanelChartScale = PanelChartScale()) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.moduleTint(for: kind))
                .frame(width: 18)
            Text("\(kind.title):")
                .monitorPanelMetricLabelFont()
                .foregroundStyle(theme.primaryText)
            Text(value)
                .monitorPanelMonoFont(weight: .semibold)
                .foregroundStyle(theme.valueText)
            Spacer(minLength: 8)
            PanelHistoryChart(samples: samples, tint: theme.moduleTint(for: kind), theme: theme, scale: scale)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, RowHeaderPillMetrics.verticalPadding)
        .panelRowHeaderHeight()
        .background {
            theme.rowGlassFill(for: kind)
                .clipShape(RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
        }
    }
}
#endif
