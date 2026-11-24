import AppKit
import Foundation
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite("Menu bar metric layout")
struct MenuBarMetricLayoutTests {

    private var sevenMetricSample: [MenuBarMetricItem] {
        [
            MenuBarMetricItem(kind: .cpuUsage, value: " 19%"),
            MenuBarMetricItem(kind: .cpuTemperature, value: " 75°"),
            MenuBarMetricItem(kind: .gpuUsage, value: " 71%"),
            MenuBarMetricItem(kind: .fanSpeed, value: "2492"),
            MenuBarMetricItem(kind: .displayRefreshRate, value: "120Hz"),
            MenuBarMetricItem(kind: .storageFree, value: "549G"),
            MenuBarMetricItem(kind: .memorySwapUsed, value: "540M")
        ]
    }

    @Test("splitValueUnit separates single-char and Hz units while leaving bare placeholders intact")
    func splitsUnitsAndPreservesBarePlaceholders() {
        #expect(MenuBarMetricWidthEngine.splitValueUnit("120Hz") == ("120", "Hz"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("--Hz") == ("--", "Hz"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("549G") == ("549", "G"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("540M") == ("540", "M"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("75°") == ("75", "°"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("19%") == ("19", "%"))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("2492") == ("2492", ""))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("--") == ("--", ""))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("%") == ("%", ""))
        #expect(MenuBarMetricWidthEngine.splitValueUnit("Hz") == ("Hz", ""))
    }

    @Test("All menu bar metric symbols are distinct and valid SF Symbols")
    func metricSymbolsAreUniqueAndValid() {
        let symbols = MenuBarMetricKind.allCases.map(\.symbol)
        #expect(Set(symbols).count == MenuBarMetricKind.allCases.count)
        for kind in MenuBarMetricKind.allCases {
            #expect(
                NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil,
                "Missing SF Symbol \(kind.symbol) for \(kind.rawValue)"
            )
        }
    }

    @Test("All metric text prefixes are non-empty in runtime and English catalog")
    func prefixesAreNonEmpty() throws {
        for kind in MenuBarMetricKind.allCases {
            #expect(!MenuBarMetricWidthEngine.textPrefix(for: kind).isEmpty)
        }

        let xcstringsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")
        let data = try Data(contentsOf: xcstringsURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        let refreshEntry = try #require(strings["menu-bar-metric-prefix.display-refresh-rate"])
        let locations = try #require(refreshEntry["localizations"] as? [String: [String: Any]])

        for locale in ["en", "zh-Hans"] {
            let value = ((locations[locale]?["stringUnit"] as? [String: Any])?["value"] as? String) ?? ""
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("Horizontal layouts lock totalWidth and maintain minimum inter-pair separation")
    func horizontalLayoutWidthStabilityAndMinimumGap() {
        let lowLoad = [
            MenuBarMetricItem(kind: .cpuUsage, value: "  4%"),
            MenuBarMetricItem(kind: .cpuTemperature, value: " 39°"),
            MenuBarMetricItem(kind: .gpuUsage, value: "  2%"),
            MenuBarMetricItem(kind: .fanSpeed, value: " 800"),
            MenuBarMetricItem(kind: .displayRefreshRate, value: " 60Hz"),
            MenuBarMetricItem(kind: .storageFree, value: "549G"),
            MenuBarMetricItem(kind: .memorySwapUsed, value: "  0B")
        ]
        let maxLoad = [
            MenuBarMetricItem(kind: .cpuUsage, value: "100%"),
            MenuBarMetricItem(kind: .cpuTemperature, value: "105°"),
            MenuBarMetricItem(kind: .gpuUsage, value: "100%"),
            MenuBarMetricItem(kind: .fanSpeed, value: "6200"),
            MenuBarMetricItem(kind: .displayRefreshRate, value: "120Hz"),
            MenuBarMetricItem(kind: .storageFree, value: "549G"),
            MenuBarMetricItem(kind: .memorySwapUsed, value: "12.8G")
        ]

        for style in [MenuBarMetricLayoutStyle.icon, .text] {
            let lowLayout = MenuBarMetricWidthEngine.horizontalLayout(for: lowLoad, layout: style)
            let highLayout = MenuBarMetricWidthEngine.horizontalLayout(for: maxLoad, layout: style)
            #expect(lowLayout.totalWidth == highLayout.totalWidth)
            #expect(highLayout.gap >= MenuBarMetricWidthEngine.minInterPairGap(for: style))
            #expect(lowLayout.gap > MenuBarMetricWidthEngine.symbolSpacing * 2.5)
        }
        #expect(MenuBarMetricWidthEngine.minInterPairGap(for: .icon) == 7)
        #expect(MenuBarMetricWidthEngine.minInterPairGap(for: .text) == 8)
    }

    @Test("Compact column widths cover prefix and split units within 22pt menu bar height")
    func compactWidthsAndRenderedHeightFitMenuBar() throws {
        #expect(MenuBarMetricWidthEngine.compactInterCellSpacing == 7)

        let worstSamples: [MenuBarMetricKind: String] = [
            .cpuUsage: "100%",
            .gpuUsage: "100%",
            .memoryUsage: "100%",
            .memoryPressure: "100%",
            .batteryLevel: "100%",
            .cpuTemperature: "888°",
            .fanSpeed: "9999",
            .displayRefreshRate: "120Hz",
            .storageFree: "888G",
            .memorySwapUsed: "888G",
            .systemPower: "888W",
            .gpuPower: "888W",
            .displayPower: "99.9W",
            .memoryBandwidth: "888G",
            .networkDownload: "888M",
            .networkUpload: "888M"
        ]

        for kind in MenuBarMetricKind.allCases {
            let cellWidth = MenuBarMetricWidthEngine.compactCellWidth(for: kind)
            let prefixWidth = MenuBarMetricWidthEngine.measuredTextWidth(
                of: MenuBarMetricWidthEngine.textPrefix(for: kind),
                font: MenuBarMetricWidthEngine.compactLabelFont
            )
            let sampleWidth = MenuBarMetricWidthEngine.measuredCompactValueWidth(
                of: try #require(worstSamples[kind])
            )
            #expect(cellWidth >= ceil(max(prefixWidth, sampleWidth)))
        }

        for style in MenuBarMetricLayoutStyle.allCases {
            let view = MenuBarMetricLabel(items: sevenMetricSample, style: .menuBar, layoutStyle: style)
                .padding(.horizontal, 2)
                .fixedSize()
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let cgImage = try #require(renderer.cgImage)
            let pointHeight = CGFloat(cgImage.height) / 2.0
            #expect(cgImage.width > 0)
            #expect(pointHeight <= 22.0, "Layout \(style.rawValue) exceeded 22pt height: \(pointHeight)")
        }
    }
}
