import AppKit
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct AirPodsLayoutTests {
    @Test func productionDeviceListRendersCompleteComponentsAtMinimumWidth() async throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tmp/airpods-ui-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in ["zh-Hans", "en"] {
            for scheme: ColorScheme in [.light, .dark] {
                let theme = MonitorPanelTheme(palette: MonitorPalette(preference: .balanced, colorScheme: scheme))
                let devices = [
                    BluetoothDeviceInfo(address: "test-1", name: "Very Long AirPods Name for Complete Display", type: .headphones, batteryLevel: 100, components: [.init(kind: .left, level: 100, isCharging: true), .init(kind: .right, level: 100, isCharging: true), .init(kind: .case, level: 100, isCharging: true)], isCharging: true),
                    BluetoothDeviceInfo(address: "test-2", name: "AirPods", type: .headphones, batteryLevel: 0, components: [.init(kind: .right, level: 0, isCharging: false)], batterySource: .advertisement),
                    BluetoothDeviceInfo(address: "test-3", name: "Apple Watch", type: .watch, batteryLevel: nil)
                ]
                let view = BluetoothDeviceList(devices: devices, theme: theme)
                    .padding(10).frame(width: MonitorConstants.panelMinWidth)
                    .background(scheme == .dark ? Color(nsColor: .darkGray) : Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: language))
                let host = NSHostingView(rootView: view)
                let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: MonitorConstants.panelMinWidth, height: 350), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.contentView = host
                panel.orderFrontRegardless()
                defer { panel.orderOut(nil); panel.contentView = nil }
                host.frame.size = CGSize(width: MonitorConstants.panelMinWidth, height: 350)
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width <= MonitorConstants.panelMinWidth + 0.5)
                #expect(host.fittingSize.height <= 350)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("airpods-\(language)-\(scheme).png"))
            }
        }
    }
}
