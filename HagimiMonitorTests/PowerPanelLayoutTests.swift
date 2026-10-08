import AppKit
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct PowerPanelLayoutTests {
    private final class RowMeasurement {
        var size: CGSize?
        var networkSize: CGSize?
    }
    private let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tmp/power-ui-review")

    private func module(_ state: String) -> MonitorModule {
        let charging = state == "charging" || state == "missing"
        let flow: Double? = ["missing", "ac-power"].contains(state) ? nil : charging ? 6.1 : -7
        let input: Double? = state == "on-battery" ? nil : state == "ac-power" ? 7 : 13.1
        let load = state == "maintain" ? 20.1 : 7.0
        return MonitorModule(kind: .battery, value: 100, summary: "100%", metrics: [
            MonitorMetric(name: "type", value: "battery"),
            MonitorMetric(name: "status", value: state == "missing" ? "charging" : state),
            MonitorMetric(name: "adapter", value: "15 W", numericValue: 15),
            MonitorMetric(name: "power-in", value: wattString(input), numericValue: input),
            MonitorMetric(name: "power", value: wattString(load), numericValue: load),
            MonitorMetric(name: "battery-flow", value: wattString(flow), numericValue: flow),
            MonitorMetric(name: "time-remaining", value: "9999", numericValue: 9999)
        ], samples: [])
    }

    private func capture<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) async throws -> CGSize {
        let host = NSHostingView(rootView: view)
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        host.frame.size = CGSize(width: width, height: height)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        return size
    }

    @Test func productionRowsKeepHeaderAndFlowGeometryAtMinimumWidth() async throws {
        for state in ["charging", "on-battery", "maintain", "ac-power", "missing"] {
            for scheme: ColorScheme in [.light, .dark] {
                let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: scheme))
                let readings = module(state)
                let measurement = RowMeasurement()
                let collapsed = BatteryGlassRow(module: readings, theme: theme)
                    .frame(width: MonitorConstants.panelMinWidth)
                    .environment(\.colorScheme, scheme)
                    .onPreferenceChange(PanelNaturalMeasurements.self) { values in
                        measurement.size = values["row:battery"]
                    }
                _ = try await capture(collapsed, name: "header-\(state)-\(scheme)", width: MonitorConstants.panelMinWidth, height: 34)
                let row = try #require(measurement.size)
                #expect(abs(row.height - MonitorConstants.panelRowHeaderHeight) < 0.5)
                let diagram = PowerFlowDiagram(module: readings, theme: theme, tint: theme.moduleTint(for: .battery), animate: false)
                    .frame(width: 260)
                    .environment(\.colorScheme, scheme)
                let size = try await capture(diagram, name: "flow-\(state)-\(scheme)", width: 260, height: state == "maintain" ? 145 : 100)
                if state != "maintain" {
                    #expect(abs(size.height - 100) < 0.5, "新增电池功率不得增高正常流图")
                }
            }
        }
    }

    @Test func networkAndPowerHeadersShareTheSameGeometry() async throws {
        for scheme: ColorScheme in [.light, .dark] {
            let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: scheme))
            let network = MonitorModule(kind: .network, value: 0, summary: "Wi-Fi", metrics: [
                MonitorMetric(name: "upload", value: "1024 KB/s"),
                MonitorMetric(name: "download", value: "1024 MB/s")
            ], samples: [])
            let measurement = RowMeasurement()
            let view = VStack(spacing: 4) {
                NetworkGlassRow(module: network, theme: theme)
                    .frame(height: MonitorConstants.panelRowHeaderHeight, alignment: .top).clipped()
                BatteryGlassRow(module: module("charging"), theme: theme)
                    .frame(height: MonitorConstants.panelRowHeaderHeight, alignment: .top).clipped()
            }
            .frame(width: MonitorConstants.panelMinWidth)
            .environment(\.colorScheme, scheme)
            .onPreferenceChange(PanelNaturalMeasurements.self) { values in
                measurement.size = values["row:battery"]
                measurement.networkSize = values["row:network"]
            }
            _ = try await capture(view, name: "network-power-\(scheme)", width: MonitorConstants.panelMinWidth,
                                  height: 2 * MonitorConstants.panelRowHeaderHeight + 4)
            let networkSize = try #require(measurement.networkSize)
            let powerSize = try #require(measurement.size)
            #expect(abs(networkSize.height - powerSize.height) < 0.5)
            #expect(abs(networkSize.height - MonitorConstants.panelRowHeaderHeight) < 0.5)
        }
    }

    @Test func bilingualBatteryContentUsesOriginalBarHeight() async throws {
        let catalog = output.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        func localized(_ key: String, _ language: String) throws -> String {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let translation = try #require(localizations[language] as? [String: Any])
            let unit = try #require(translation["stringUnit"] as? [String: Any])
            return try #require(unit["value"] as? String)
        }
        for language in ["zh-Hans", "en"] {
            let input = try localized("panel.power.input", language)
            let load = try localized("panel.power.load", language)
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: language)
            formatter.calendar = calendar
            let duration = try #require(formatter.string(from: 9999 * 60))
            let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: .light))
            for (statusKey, etaKey) in [
                ("battery-state.charging", "panel.power-flow.eta-full"),
                ("panel.power.discharging", "panel.power-flow.eta-empty"),
                ("battery-state.insufficient", "panel.power-flow.optimized-protection")
            ] {
                let status = try localized(statusKey, language)
                let eta = String(format: try localized(etaKey, language), duration)
                let content = PowerFlowBatteryContent(percentage: "100%", status: status, power: "999.9 W", eta: eta,
                                                      primary: .black, secondary: .black.opacity(0.6))
                let contentHost = NSHostingView(rootView: content.frame(width: 260))
                #expect(contentHost.fittingSize.height <= PowerFlowDiagram.barHeight)
                let view = VStack(spacing: 8) {
                    HStack(spacing: RowHeaderPillMetrics.spacing) {
                        MetricLabelPill(title: input, value: "999.9 W", theme: theme)
                        MetricLabelPill(title: load, value: "188.0 W", theme: theme)
                    }
                    content
                        .frame(height: PowerFlowDiagram.barHeight)
                        .background(Color.green.opacity(0.15))
                }
                .frame(width: 260)
                let size = try await capture(view, name: "bilingual-\(language)-\(status)", width: 260,
                                             height: RowHeaderPillMetrics.height + 8 + PowerFlowDiagram.barHeight)
                #expect(abs(size.height - (RowHeaderPillMetrics.height + 8 + PowerFlowDiagram.barHeight)) < 0.5)
            }
        }
    }
}
