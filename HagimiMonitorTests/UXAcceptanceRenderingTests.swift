import AppKit
import SwiftUI
import Testing
import Vision
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct UXAcceptanceRenderingTests {
    private let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tmp/ux-final-acceptance")

    private func snapshot(fan: Double? = 1200, peak: Double? = 2400, direct: Bool = true) -> ReportSnapshot {
        let now = Date()
        let rows = (0..<30).map { index in
            var row = StatisticsRow(t: Int64(now.timeIntervalSince1970) - Int64(30 - index) * 60, n: 60)
            row.cpuAvg = 20 + Double(index % 10)
            row.cpuMax = 65 + Double(index % 20)
            row.gpuAvg = 35 + Double(index % 8)
            row.gpuMax = 75
            row.memUsedAvg = 9 * 1_073_741_824
            row.memPressureAvg = 20
            row.powerAvg = 18
            row.cpuTempAvg = 55
            row.cpuThermalAvg = 0
            row.fanAvg = fan
            row.fanMax = peak
            row.coverS = 60
            row.cpuPAvg = 38
            row.cpuEAvg = 16
            return row
        }
        return ReportSnapshot(capturedAt: now,
            meta: ReportMeta(deviceName: "Controlled acceptance sample", modelName: "Fixture Mac",
                osVersion: "macOS 27", recordDays: 1, appVersion: "validation", isDirect: direct),
            minutes: rows, hours: [], days: [], process: nil, hardware: nil)
    }

    private func text(in element: Any, depth: Int = 0) -> [String] {
        guard depth < 30, let node = element as? NSObject else { return [] }
        func attribute(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            guard node.responds(to: selector) else { return nil }
            return node.perform(selector)?.takeUnretainedValue()
        }
        var result: [String] = []
        if let value = attribute("accessibilityValue") as? String { result.append(value) }
        if let label = attribute("accessibilityLabel") as? String { result.append(label) }
        let children = attribute("accessibilityChildren") as? [Any] ?? (node as? NSView)?.subviews ?? []
        for child in children { result += text(in: child, depth: depth + 1) }
        return result
    }

    private func capture<V: View>(_ view: V, name: String, scheme: ColorScheme = .light,
                                  width: CGFloat = 1120, height: CGFloat = 1240) async throws -> String {
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 16) {
            Text("CONTROLLED ACCEPTANCE FIXTURE · \(language)").font(.caption)
            view
        }.padding(20).background(scheme == .dark ? Color.black : .white).environment(\.colorScheme, scheme))
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        host.frame.size = CGSize(width: width, height: height)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = output.appendingPathComponent(language)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"))
        var content = text(in: host).joined(separator: "\n")
        if content.isEmpty {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            let handler = VNImageRequestHandler(cgImage: try #require(bitmap.cgImage), options: [:])
            try handler.perform([request])
            content = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        try content.write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        #expect(!content.contains("stats.r."))
        return content.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    @Test func fanStatesAndDesktopPowerUseTheirRealNativeViews() async throws {
        for (name, hasFans, direct, average, peak, key) in [
            ("fanless", false, true, nil, nil, "stats.r.fanlessTitle"),
            ("unavailable", true, false, nil, nil, "stats.r.fanUnavailableCaption"),
            ("no-history", true, true, nil, nil, "stats.r.fanNoHistoryCaption"),
            ("stopped", true, true, 0.0, 0.0, "stats.r.fanStoppedCaption"),
            ("measured", true, true, 1200.0, 2400.0, "stats.r.sAvgFan")
        ] as [(String, Bool, Bool, Double?, Double?, String)] {
            let model = NativeReportViewModel(previewSnapshot: snapshot(fan: average, peak: peak, direct: direct),
                hardwareHasBattery: true, hardwareHasFans: hasFans)
            let content = try await capture(ReportThermalView(viewModel: model), name: "thermal-" + name)
            #expect(content.contains(String(localized: String.LocalizationValue(key))))
            if name == "no-history" || name == "unavailable" || name == "fanless" {
                #expect(!content.contains("0 RPM"))
            }
            if name == "measured" { #expect(content.contains("1200 RPM")); #expect(content.contains("2400")) }
            model.teardown()
        }
        let desktop = NativeReportViewModel(previewSnapshot: snapshot(), hardwareHasBattery: false, hardwareHasFans: true)
        let content = try await capture(ReportPowerView(viewModel: desktop), name: "desktop-ac")
        #expect(content.contains(String(localized: "stats.r.acPower")))
        #expect(content.contains(String(localized: "stats.r.desktopMacFormFactor")))
        desktop.teardown()
    }

    @Test func reportThemesAndFailureStatesRenderWithoutChangingUserPreferences() async throws {
        let domain = "ux-render-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = NativeReportViewModel(previewSnapshot: snapshot(), hardwareHasBattery: true, hardwareHasFans: true)
        defer { model.teardown() }
        for preference in [MonitorColorSchemePreference.balanced, .vibrant] {
            defaults.set(preference.rawValue, forKey: "settings.colorSchemePreference")
            for scheme in [ColorScheme.light, .dark] {
                let suffix = "\(preference.rawValue)-\(scheme == .light ? "light" : "dark")"
                _ = try await capture(ReportCpuView(viewModel: model).defaultAppStorage(defaults), name: "cpu-" + suffix, scheme: scheme)
                _ = try await capture(ReportGpuView(viewModel: model).defaultAppStorage(defaults), name: "gpu-" + suffix, scheme: scheme)
                _ = try await capture(ReportMemoryView(viewModel: model).defaultAppStorage(defaults), name: "memory-" + suffix, scheme: scheme)
                let palette = MonitorPalette(preference: preference, colorScheme: scheme)
                let cores = CPUCoreDetail(cores: (0..<32).map {
                    CPUCoreLoad(index: $0, usage: 20 + Double($0), kind: $0 < 8 ? .superCore : $0 < 24 ? .performance : .efficiency)
                }, performanceUsage: 38, efficiencyUsage: 16, superUsage: 60)
                _ = try await capture(CPUCoresDetail(detail: cores, theme: MonitorPanelTheme(palette: palette)),
                    name: "cores-" + suffix, scheme: scheme, width: 340, height: 260)
            }
        }
        for oldSnapshot in [false, true] {
            let failed = NativeReportViewModel(previewSnapshot: oldSnapshot ? snapshot() : nil,
                hardwareHasBattery: true, hardwareHasFans: true, loadFailed: true)
            let content = try await capture(NativeReportView(viewModel: failed, onReload: {}, onPrint: {}, onExport: {}),
                name: oldSnapshot ? "refresh-failed" : "first-read-failed", height: 800)
            #expect(content.contains(String(localized: "stats.report.read-failed")))
            #expect(content.contains(String(localized: "stats.report.retry")))
            #expect(failed.committedExportRange() == nil)
            failed.teardown()
        }
    }
}
