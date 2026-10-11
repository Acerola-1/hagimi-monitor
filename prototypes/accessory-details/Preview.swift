import AppKit
import SwiftUI

private enum Design: String, CaseIterable { case grouped, rows }
private enum Scene: String, CaseIterable { case screenshot, complete, multiple }
private struct DemoFan: Identifiable {
    let id: Int
    let name: String
    let rpm: Int
}
private struct DemoPart: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let level: Int?
    var charging = false
}
private struct DemoDevice: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let subtitle: String
    let parts: [DemoPart]
}

private struct PreviewPanel: View {
    let design: Design
    let scene: Scene
    let dark: Bool
    let english: Bool
    let width: CGFloat
    private var palette: MonitorPalette {
        MonitorPalette(preference: .vibrant, colorScheme: dark ? .dark : .light)
    }
    private func l(_ chinese: String, _ englishText: String) -> String { english ? englishText : chinese }
    private var fans: [DemoFan] {
        switch scene {
        case .screenshot:
            return [.init(id: 0, name: l("左侧风扇", "Left Fan"), rpm: 0),
                    .init(id: 1, name: l("右侧风扇", "Right Fan"), rpm: 0)]
        case .complete:
            return [.init(id: 0, name: l("左侧风扇", "Left Fan"), rpm: 1320),
                    .init(id: 1, name: l("右侧风扇", "Right Fan"), rpm: 1480)]
        case .multiple:
            return [.init(id: 0, name: l("左侧风扇", "Left Fan"), rpm: 0),
                    .init(id: 1, name: l("右侧风扇", "Right Fan"), rpm: 2460),
                    .init(id: 2, name: l("辅助风扇", "Auxiliary Fan"), rpm: 1840),
                    .init(id: 3, name: l("机箱风扇", "Chassis Fan"), rpm: 0)]
        }
    }
    private var devices: [DemoDevice] {
        let parts: [DemoPart] = [
            .init(id: "left", symbol: "airpod.left", name: l("左耳", "Left"), level: scene == .screenshot ? 100 : 99, charging: scene != .screenshot),
            .init(id: "right", symbol: "airpod.right", name: l("右耳", "Right"), level: scene == .screenshot ? nil : 97),
            .init(id: "case", symbol: "airpods.chargingcase", name: l("充电仓", "Case"), level: scene == .screenshot ? nil : 65)
        ]
        var result = [DemoDevice(id: "airpods", name: "AirPods", symbol: "headphones", subtitle: l("耳机", "Headphones"), parts: parts)]
        if scene == .multiple {
            result[0] = .init(id: "airpods", name: l("我的 AirPods Pro", "My AirPods Pro"), symbol: "headphones", subtitle: l("耳机", "Headphones"), parts: parts)
            result.append(.init(id: "watch", name: "Apple Watch", symbol: "applewatch", subtitle: l("手表", "Watch"), parts: [.init(id: "battery", symbol: "battery.100percent", name: l("电量", "Battery"), level: nil)]))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(palette.captionText).frame(width: 4, height: 4)
                Text("SYSTEM · PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                Spacer()
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
            }
            .foregroundStyle(palette.captionText).padding(.horizontal, 10).padding(.vertical, 8)
            staticRow("cpu", symbol: "cpu", name: "CPU", value: "12%", kind: .cpu)
            staticRow("gpu", symbol: "display", name: "GPU", value: "55%", kind: .gpu)
            module(kind: .fan, symbol: "fanblades.fill", name: l("风扇", "Fans"), value: "\(fans.map(\.rpm).max() ?? 0) RPM") {
                if design == .grouped { fanGrid } else { fanRows }
            }
            staticRow("memory", symbol: "memorychip", name: l("内存", "Memory"), value: l("正常", "Normal"), kind: .memory)
            module(kind: .bluetooth, symbol: "antenna.radiowaves.left.and.right", name: l("蓝牙", "Bluetooth"), value: english ? "\(devices.count) device\(devices.count == 1 ? "" : "s")" : "\(devices.count) 台设备") {
                VStack(spacing: 6) { ForEach(devices) { device in deviceGroup(device) } }
            }
            Text(l("设计预览 · 示例数据", "Design preview · Sample data"))
                .font(.system(size: 10)).foregroundStyle(palette.captionText)
                .padding(.top, 4).padding(.bottom, 8)
        }
        .padding(6)
        .frame(width: width)
        .background(VisualEffect(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: MonitorConstants.panelCornerRadius))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func staticRow(_ id: String, symbol: String, name: String, value: String, kind: MonitorKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(palette.moduleTint(for: kind)).frame(width: 18)
            Text(name + ":").font(.system(.callout).weight(.medium))
            Text(value).font(.system(.callout, design: .monospaced).weight(.semibold))
            Spacer(minLength: 0)
            MiniChart(color: palette.moduleTint(for: kind)).frame(width: MonitorConstants.panelChartWidth, height: MonitorConstants.panelChartHeight)
        }
        .foregroundStyle(palette.primaryText).padding(.horizontal, 10)
        .frame(height: MonitorConstants.panelRowHeaderHeight)
        .background(rowSurface(kind))
        .clipShape(RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius))
    }

    private func module<C: View>(kind: MonitorKind, symbol: String, name: String, value: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(palette.moduleTint(for: kind)).frame(width: 18)
                Text(name + ":").font(.system(.callout).weight(.medium))
                Text(value).font(.system(.callout, design: .monospaced).weight(.semibold)).fixedSize()
                Spacer(minLength: 0)
                if kind == .fan {
                    MiniChart(color: palette.moduleTint(for: kind)).frame(width: MonitorConstants.panelChartWidth, height: MonitorConstants.panelChartHeight)
                } else {
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(palette.captionText)
                }
            }
            .foregroundStyle(palette.primaryText).padding(.horizontal, 10)
            .frame(height: MonitorConstants.panelRowHeaderHeight)
            content().padding(.horizontal, 10).padding(.bottom, 10)
        }
        .background(rowSurface(kind))
        .clipShape(RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius))
    }

    private func rowSurface(_ kind: MonitorKind) -> some View {
        ZStack {
            VisualEffect(material: .menu, blending: .withinWindow)
            palette.rowGlassFill(for: kind)
            Color.white.opacity(palette.cardBrightenOpacity)
        }
    }
    private func innerSurface(_ kind: MonitorKind) -> some View {
        RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius / 2)
            .fill(palette.trackFill)
    }
    private var fanGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<(fans.count + 1) / 2, id: \.self) { index in
                if index > 0 { Divider().overlay(palette.rowSeparator(for: .fan)) }
                HStack(spacing: 0) {
                    ForEach(Array(fans.dropFirst(index * 2).prefix(2))) { fan in
                        if fan.id % 2 == 1 { Rectangle().fill(palette.rowSeparator(for: .fan)).frame(width: 1).padding(.vertical, 10) }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "fanblades.fill").foregroundStyle(palette.moduleTint(for: .fan))
                                Text(fan.name).foregroundStyle(palette.secondaryText)
                            }.font(.system(size: 11, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            rpm(fan.rpm, size: 17)
                            HStack(spacing: 4) {
                                Circle().fill(fan.rpm == 0 ? palette.captionText.opacity(0.55) : palette.moduleTint(for: .fan)).frame(width: 4, height: 4)
                                Text(fan.rpm == 0 ? l("停转", "Stopped") : l("运行中", "Running"))
                            }.font(.system(size: 10, weight: .medium)).foregroundStyle(palette.captionText)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.background(innerSurface(.fan))
    }
    private var fanRows: some View {
        VStack(spacing: 0) {
            ForEach(fans) { fan in
                if fan.id > 0 { Divider().overlay(palette.rowSeparator(for: .fan)).padding(.horizontal, 10) }
                HStack(spacing: 9) {
                    Image(systemName: "fanblades.fill").foregroundStyle(palette.moduleTint(for: .fan)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fan.name).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.primaryText)
                        Text(fan.rpm == 0 ? l("停转", "Stopped") : l("运行中", "Running")).font(.system(size: 10)).foregroundStyle(palette.captionText)
                    }
                    Spacer(minLength: 5)
                    rpm(fan.rpm, size: 13)
                }.padding(.horizontal, 10).padding(.vertical, 8)
            }
        }.background(innerSurface(.fan))
    }
    private func rpm(_ value: Int, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)").font(.system(size: size, weight: .semibold, design: .monospaced))
            Text("RPM").font(.system(size: 10, weight: .medium)).foregroundStyle(palette.captionText)
        }.foregroundStyle(palette.valueText).fixedSize()
    }
    private func deviceGroup(_ device: DemoDevice) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: device.symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.moduleTint(for: .bluetooth))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(palette.badgeFill(for: .bluetooth)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.primaryText)
                    Text(device.subtitle).font(.system(size: 10)).foregroundStyle(palette.captionText)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(10)
            if device.parts.count > 1 {
                Rectangle().fill(palette.rowSeparator(for: .bluetooth)).frame(height: 1).padding(.horizontal, 10)
            }
            if design == .grouped && device.parts.count > 1 {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(device.parts) { part in
                        if part.id != "left" { Rectangle().fill(palette.rowSeparator(for: .bluetooth)).frame(width: 1, height: 42).padding(.vertical, 10) }
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                symbol(part.symbol).font(.system(size: 11)).foregroundStyle(palette.moduleTint(for: .bluetooth).opacity(part.level == nil ? 0.5 : 1))
                                Text(part.name).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.captionText)
                            }.fixedSize()
                            level(part, size: 14)
                            BatteryTrack(level: part.level, color: palette.severityTint(for: .calm), track: palette.trackFill).frame(height: 3)
                        }.padding(.horizontal, 8).padding(.vertical, 10).frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(device.parts) { part in
                        HStack(spacing: 7) {
                            symbol(part.symbol).font(.system(size: 12)).foregroundStyle(palette.moduleTint(for: .bluetooth).opacity(part.level == nil ? 0.5 : 1)).frame(width: 18)
                            Text(part.name).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.captionText).fixedSize()
                            Spacer(minLength: 4)
                            BatteryTrack(level: part.level, color: palette.severityTint(for: .calm), track: palette.trackFill).frame(width: 50, height: 3)
                            level(part, size: 13).frame(minWidth: 54, alignment: .trailing)
                        }.padding(.horizontal, 10).padding(.vertical, 7)
                    }
                }.padding(.bottom, 3)
            }
        }.background(innerSurface(.bluetooth))
    }
    private func symbol(_ value: String) -> Image {
        Image(systemName: NSImage(systemSymbolName: value, accessibilityDescription: nil) == nil ? "headphones" : value)
    }
    private func level(_ part: DemoPart, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            if part.charging { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(palette.severityTint(for: .calm)) }
            Text(part.level.map { "\($0)%" } ?? "—").font(.system(size: size, weight: .semibold, design: .monospaced))
                .foregroundStyle(part.level == nil ? palette.captionText : palette.valueText)
        }.fixedSize()
    }
}

private struct BatteryTrack: View {
    let level: Int?
    let color: Color
    let track: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if let level { Capsule().fill(color).frame(width: geometry.size.width * CGFloat(level) / 100) }
            }
        }
    }
}
private struct MiniChart: View {
    let color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: g.size.height)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)) }
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.6)
            Path { p in
                p.move(to: CGPoint(x: 1, y: g.size.height - 2))
                p.addLine(to: CGPoint(x: g.size.width * 0.6, y: g.size.height - 2))
                p.addLine(to: CGPoint(x: g.size.width * 0.72, y: g.size.height - 4))
                p.addLine(to: CGPoint(x: g.size.width - 2, y: g.size.height - 2))
            }.stroke(color, lineWidth: 1)
        }
    }
}
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material; view.blendingMode = blending; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material; view.blendingMode = blending }
}

private struct PreviewWorkbench: View {
    @State private var design = Design.grouped
    @State private var scene = Scene.screenshot
    @State private var dark = false
    @State private var english = false
    @State private var width: CGFloat = 340
    private func l(_ zh: String, _ en: String) -> String { english ? en : zh }
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            PreviewPanel(design: design, scene: scene, dark: dark, english: english, width: width)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 18) {
                Text(l("风扇与蓝牙明细", "Accessory details")).font(.title3.weight(.semibold))
                Text(l("两种归属布局，一次预览一套。", "Two layouts, one preview at a time.")).font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l("布局方案", "Layout")).font(.headline)
                    Picker(l("布局方案", "Layout"), selection: $design) {
                        Text(l("A · 分组网格", "A · Grouped grid")).tag(Design.grouped)
                        Text(l("B · 归属列表", "B · Grouped rows")).tag(Design.rows)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(l("数据场景", "Scenario")).font(.headline)
                    Picker(l("数据场景", "Scenario"), selection: $scene) {
                        Text(l("截图同态 · 0 RPM / 部件缺失", "Screenshot · stopped / missing")).tag(Scene.screenshot)
                        Text(l("运行与完整电量", "Running / all batteries")).tag(Scene.complete)
                        Text(l("四个风扇 / 多设备", "Four fans / multiple devices")).tag(Scene.multiple)
                    }.labelsHidden()
                }
                Picker(l("面板宽度", "Panel width"), selection: $width) {
                    Text("300 pt").tag(CGFloat(300)); Text("340 pt").tag(CGFloat(340)); Text("460 pt").tag(CGFloat(460))
                }.pickerStyle(.segmented).labelsHidden()
                Toggle(l("深色外观", "Dark appearance"), isOn: $dark)
                Toggle("English", isOn: $english)
                Divider()
                Text(design == .grouped ? l("A 把同一设备的部件收进一个浅底容器；左右风扇与耳机三部件用等分网格表达归属。", "A groups parts in one inset surface, with equal columns for fans and earphone components.") : l("B 保留纵向阅读，用设备标题与共同底色将明细包起来；更适合长名称和多设备。", "B keeps vertical reading, grouping details under one device title and surface."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(l("停转只显示中性文字；未上报电量显示 —。此窗口使用示例数据，不改变正式应用。", "Stopped is neutral; missing battery stays —. Sample data only; the production app is unchanged."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.frame(width: 250)
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 710), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        main.title = "Hagimi · 风扇与蓝牙 UI 方案"
        main.contentView = NSHostingView(rootView: PreviewWorkbench())
        main.center(); main.makeKeyAndOrderFront(nil)
        window = main
        NSApp.activate(ignoringOtherApps: true)
        if let output = ProcessInfo.processInfo.environment["HAGIMI_ACCESSORY_PREVIEW_EXPORT"] {
            Task { await export(to: URL(fileURLWithPath: output)) }
        }
    }
    private func export(to directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for design in Design.allCases {
                for scene in Scene.allCases {
                for dark in [false, true] {
                    for english in [false, true] {
                        let width: CGFloat = 300
                        let host = NSHostingView(rootView: PreviewPanel(design: design, scene: scene, dark: dark, english: english, width: width))
                        let panel = NSPanel(contentRect: NSRect(x: 10, y: 10, width: width, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        panel.contentView = host; panel.orderFrontRegardless()
                        host.frame.size = CGSize(width: width, height: 480)
                        try await Task.sleep(for: .milliseconds(200))
                        host.layoutSubtreeIfNeeded()
                        let height = host.fittingSize.height
                        host.frame.size = CGSize(width: width, height: height)
                        panel.setContentSize(host.frame.size)
                        host.layoutSubtreeIfNeeded()
                        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                            bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                            if let data = bitmap.representation(using: .png, properties: [:]) {
                                let scenarioSuffix = scene == .screenshot ? "" : "-\(scene.rawValue)"
                                try data.write(to: directory.appendingPathComponent("\(design.rawValue)-\(dark ? "dark" : "light")-\(english ? "en" : "zh")\(scenarioSuffix).png"))
                            }
                        }
                        panel.orderOut(nil); panel.contentView = nil
                    }
                }
                }
            }
        } catch { print("Preview capture failed: \(error)") }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main private struct PreviewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PreviewDelegate()
        app.delegate = delegate
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "退出 UI 预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = menu
        withExtendedLifetime(delegate) { app.run() }
    }
}
