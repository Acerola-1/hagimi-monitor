import AppKit
import Combine
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

struct MetricWidthResolutionTests {
    private func item(_ id: String, _ width: CGFloat, span: Int = 0) -> MetricWidthResolution.Item {
        .init(id: id, span: span, idealWidth: width)
    }

    @Test func automaticFitsTwoColumnsAndPromotesLongValues() {
        var state = MetricWidthResolution()
        #expect(state.spans(for: [item("short", 100), item("long", 200)], width: 300, environment: "zh") == [1, 2])
        #expect(state.spans(for: [item("short", 100), item("long", 100)], width: 300, environment: "zh") == [1, 2])
    }

    @Test func widthEnvironmentAndExplicitPolicyResetTheBudget() {
        var state = MetricWidthResolution()
        #expect(state.spans(for: [item("a", 160)], width: 300, environment: "zh") == [2])
        #expect(state.spans(for: [item("a", 160)], width: 400, environment: "zh") == [1])
        #expect(state.spans(for: [item("a", 240)], width: 400, environment: "zh") == [2])
        #expect(state.spans(for: [item("a", 100)], width: 400, environment: "en") == [1])
        #expect(state.spans(for: [item("a", 240, span: 1)], width: 400, environment: "en") == [1])
        #expect(state.spans(for: [item("a", 100)], width: 400, environment: "en") == [1])
    }

    @Test func manualChoicesOverrideContentAndStableIDsSurviveReordering() {
        var state = MetricWidthResolution()
        #expect(state.spans(for: [item("a", 500, span: 1), item("b", 1, span: 2)], width: 300, environment: "zh") == [1, 2])
        #expect(state.spans(for: [item("b", 200), item("a", 80)], width: 300, environment: "zh") == [2, 1])
        #expect(state.spans(for: [item("a", 80), item("b", 80)], width: 300, environment: "zh") == [1, 2])
    }

    @Test func roundedBoundaryAndNonfiniteSizesAreConservative() {
        var state = MetricWidthResolution()
        #expect(state.spans(for: [item("a", 146), item("b", 146.1), item("c", .infinity)], width: 300, environment: "zh") == [1, 2, 2])
    }
}

@MainActor
struct MetricWidthSettingsTests {
    private func defaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MetricWidthSettingsTests." + name)!
        defaults.removePersistentDomain(forName: "MetricWidthSettingsTests." + name)
        return defaults
    }

    @Test func preferencesSurviveRestartAndMemoryDisplayAlias() {
        let defaults = defaults(#function)
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.panelMetricWidth(for: .cpu, id: "uptime") == .automatic)
        settings.setPanelMetricWidth(.half, for: .cpu, id: "uptime")
        settings.setPanelMetricWidth(.full, for: .memory, id: "usage")
        let reopened = MonitorSettings(defaults: defaults)
        #expect(reopened.panelMetricWidth(for: .cpu, id: "uptime") == .half)
        #expect(reopened.panelMetricWidth(for: .memory, id: "pressure") == .full)
        settings.setPanelMetricWidth(.automatic, for: .cpu, id: "uptime")
        #expect(MonitorSettings(defaults: defaults).panelMetricWidth(for: .cpu, id: "uptime") == .automatic)
    }

    @Test func resetIsPerModuleAndPreservesSelectionAndOrder() {
        let settings = MonitorSettings(defaults: defaults(#function))
        let order = settings.panelOrder(for: .metrics(.cpu))
        let selected = settings.isMetricEnabled("uptime", for: .cpu)
        settings.setPanelMetricWidth(.half, for: .cpu, id: "thermal-pressure")
        settings.setPanelMetricWidth(.full, for: .network, id: "ipv6")
        settings.resetPanelMetricWidths(for: .cpu)
        #expect(settings.panelMetricWidth(for: .cpu, id: "thermal-pressure") == .automatic)
        #expect(settings.panelMetricWidth(for: .network, id: "ipv6") == .full)
        #expect(settings.panelOrder(for: .metrics(.cpu)) == order)
        #expect(settings.isMetricEnabled("uptime", for: .cpu) == selected)
    }

    @Test func rejectsUnknownStoredModesAndKeepsSpecialFormsFullWidth() {
        let defaults = defaults(#function)
        defaults.set(["cpu.uptime": "future-mode", "network.ipv6": "full"], forKey: "settings.panel.metricWidths")
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.panelMetricWidth(for: .cpu, id: "uptime") == .automatic)
        #expect(settings.panelMetricWidth(for: .network, id: "ipv6") == .full)
        settings.setPanelMetricWidth(.half, for: .cpu, id: "core-split")
        settings.setPanelMetricWidth(.half, for: .battery, id: "power-flow")
        #expect(settings.panelMetricWidth(for: .cpu, id: "core-split") == .automatic)
        #expect(settings.panelMetricWidth(for: .battery, id: "power-flow") == .automatic)
    }
}

@MainActor
@Suite(.serialized)
struct MetricWidthRenderingTests {
    private final class WidthModel: ObservableObject {
        @Published var widths: [String: PanelMetricWidth] = ["cpu.thermal-pressure": .half, "cpu.uptime": .half]
        @Published var uptime = "3天51分钟"
    }

    private struct ResizingDetail: View {
        @ObservedObject var model: WidthModel
        let metrics: [MonitorMetric]
        let theme: MonitorPanelTheme
        var body: some View {
            SingleHostDetail(id: "cpu", isExpanded: true, available: true,
                content: MetricDetailGrid(metrics: metrics.map { $0.name == "uptime" ? MonitorMetric(name: "uptime", value: model.uptime) : $0 }, kind: .cpu, theme: theme, showsSeparator: false)
                    .environment(\.panelMetricWidths, model.widths), measurementKey: "stable-structure")
                .frame(width: 320)
        }
    }

    private let metrics = [
        MonitorMetric(name: "system", value: "17%", numericValue: 17, unit: "%"),
        MonitorMetric(name: "user", value: "29%", numericValue: 29, unit: "%"),
        MonitorMetric(name: "temperature", value: "40 °C", numericValue: 40, unit: " °C"),
        MonitorMetric(name: "thermal-pressure", value: "normal", numericValue: 0),
        MonitorMetric(name: "uptime", value: "3天51分钟")
    ]

    private func host<V: View>(_ view: V, width: CGFloat, name: String, height: CGFloat = 180, verify: () throws -> Void = {}) async throws -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        host.frame.size = CGSize(width: width, height: height)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/metric-width")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        try verify()
        return host
    }

    @Test func manualHalfRowsAndFullRowUseActualReorderGeometry() async throws {
        for scheme: ColorScheme in [.light, .dark] {
            let settings = MonitorSettings(defaults: UserDefaults(suiteName: "MetricWidthRenderingTests.\(scheme)")!)
            settings.resetPanelMetricWidths(for: .cpu)
            settings.setPanelMetricWidth(.half, for: .cpu, id: "thermal-pressure")
            settings.setPanelMetricWidth(.half, for: .cpu, id: "uptime")
            let controller = PanelReorderController()
            let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: scheme))
            let view = MetricDetailGrid(metrics: metrics, kind: .cpu, theme: theme, showsSeparator: false)
                .frame(width: 320)
                .environment(\.panelMetricWidths, settings.panelMetricWidths)
                .environment(\.panelReorderSettings, settings)
                .environment(\.panelReorderController, controller)
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color.black : Color.white)
            _ = try await host(view, width: 320, name: "cpu-half-\(scheme)") {
                let thermal = try #require(controller.registeredFrame(scope: .metrics(.cpu), id: "thermal-pressure"))
                let uptime = try #require(controller.registeredFrame(scope: .metrics(.cpu), id: "uptime"))
                #expect(abs(thermal.width - 156) < 0.5)
                #expect(abs(thermal.midY - uptime.midY) < 0.5)
                #expect(controller.availableDirections("thermal-pressure", scope: .metrics(.cpu), settings: settings).contains(.right))
            }
        }
    }

    @Test func automaticCardsFitSupportedWidthsAndPreviewUsesOverrides() async throws {
        let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: .light))
        for width: CGFloat in [280, 320, 440] {
            let settings = MonitorSettings(defaults: UserDefaults(suiteName: "MetricWidthRenderingTests.auto")!)
            let controller = PanelReorderController()
            let view = MetricDetailGrid(metrics: metrics, kind: .cpu, theme: theme, showsSeparator: false)
                .frame(width: width).background(Color.white)
                .environment(\.panelReorderSettings, settings)
                .environment(\.panelReorderController, controller)
            let host = try await host(view, width: width, name: "cpu-auto-\(Int(width))") {
                let system = try #require(controller.registeredFrame(scope: .metrics(.cpu), id: "system"))
                #expect(abs(system.width - (width - 8) / 2) < 0.5)
                #expect(controller.availableDirections("user", scope: .metrics(.cpu), settings: settings).contains(.left))
            }
            #expect(host.fittingSize.width == width)
            #expect(host.fittingSize.height > 0 && host.fittingSize.height <= 110)
        }
        let switches = MonitorKind.cpu.availableMetrics.filter { ["system", "user", "thermal-pressure", "uptime"].contains($0.id) }
        let preview = ModuleRowPreview(kind: .cpu, metrics: switches, memoryPressureMode: false,
                                       palette: MonitorPalette(preference: .balanced, colorScheme: .light), metricOrders: [:],
                                       metricWidths: ["cpu.thermal-pressure": .half, "cpu.uptime": .half], batteryTab: .constant(.health))
            .frame(width: 340)
        _ = try await host(preview, width: 340, name: "settings-preview-half")
    }

    @Test func changingWidthUpdatesTheCachedExpandedDetailHeight() async throws {
        let model = WidthModel()
        let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: .light))
        let view = ResizingDetail(model: model, metrics: metrics, theme: theme)
        let host = NSHostingView(rootView: view)
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 180),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let halfHeight = host.fittingSize.height
        model.widths["cpu.thermal-pressure"] = .full
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > halfHeight + 10)
        model.widths["cpu.thermal-pressure"] = .half
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.height - halfHeight) < 0.5)
        model.widths["cpu.uptime"] = .automatic
        model.uptime = String(repeating: "8天", count: 30)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let longHeight = host.fittingSize.height
        #expect(longHeight > halfHeight + 10)
        model.uptime = "3天51分钟"
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.height - longHeight) < 0.5)
        model.widths["cpu.uptime"] = .half
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.height - halfHeight) < 0.5)
    }

    @Test func settingsPageExposesThePerMetricWidthControl() async throws {
        let settings = MonitorSettings(defaults: UserDefaults(suiteName: "MetricWidthRenderingTests.settings")!)
        settings.setVisible(true, for: .cpu)
        settings.colorSchemePreference = .balanced
        settings.resetPanelMetricWidths(for: .cpu)
        settings.setPanelMetricWidth(.half, for: .cpu, id: "thermal-pressure")
        settings.setPanelMetricWidth(.half, for: .cpu, id: "uptime")
        let view = ModuleSettingsView(kind: .cpu, settings: settings)
            .frame(width: 700)
            .environment(\.colorScheme, .light)
            .background(Color.white)
        _ = try await host(view, width: 700, name: "settings-width-controls", height: 900)
    }
}
