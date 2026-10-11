import AppKit
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct AccessoryGridLayoutTests {
    @Test func productionFanGridFitsOddAndEvenCountsAtMinimumWidth() async throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/accessory-ui-implementation/screenshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in ["zh-Hans", "en"] {
            for scheme: ColorScheme in [.light, .dark] {
                var heights: [Int: CGFloat] = [:]
                for count in [2, 3, 4, 5] {
                    let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .vibrant, colorScheme: scheme))
                    let fans = (0..<count).map { index in
                        FanInfo(id: index, name: "Fan #\(index)", currentRPM: index.isMultiple(of: 2) ? 0 : 2345,
                                minRPM: 1000, maxRPM: 6000)
                    }
                    let view = FanList(fans: fans, theme: theme)
                        .padding(10).frame(width: MonitorConstants.panelMinWidth - 12)
                        .background(theme.rowGlassFill(for: .fan))
                        .background(scheme == .dark ? Color(nsColor: .darkGray) : Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: language))
                    let host = NSHostingView(rootView: view)
                    let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: MonitorConstants.panelMinWidth - 12, height: 300),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    panel.contentView = host; panel.orderFrontRegardless()
                    defer { panel.orderOut(nil); panel.contentView = nil }
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                    #expect(host.fittingSize.width <= MonitorConstants.panelMinWidth - 12 + 0.5)
                    #expect(host.fittingSize.height < 300)
                    heights[count] = host.fittingSize.height
                    host.frame.size.height = host.fittingSize.height
                    panel.setContentSize(host.frame.size)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: output.appendingPathComponent("fans-\(count)-\(language)-\(scheme).png"))
                }
                #expect(try #require(heights[2]) < #require(heights[3]))
                #expect(abs(try #require(heights[3]) - #require(heights[4])) < 1)
                #expect(try #require(heights[4]) < #require(heights[5]))
            }
        }
    }
}
