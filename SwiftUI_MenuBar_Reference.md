# macOS 26 原生菜单栏监控应用 — SwiftUI 实现参考

> 目标:macOS 26+ 独占,充分利用 Liquid Glass、`MenuBarExtra`、Swift Charts、Observation 框架、System APIs。
> 本文档为对照 Web 原型(CPU / GPU / Memory / Storage / Network / Battery)的原生实现指南。

---

## 1. 项目搭建

```
Xcode 26 → File → New → Project → macOS → App
  Product Name:   GlassMonitor
  Interface:      SwiftUI
  Language:       Swift
  Minimum Deploy: macOS 26.0
```

`Info.plist` 关键设置:

```xml
<key>LSUIElement</key><true/>            <!-- 隐藏 Dock 图标,纯菜单栏 App -->
<key>NSSupportsAutomaticTermination</key><true/>
```

`GlassMonitor.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.system-monitoring</key><true/>
```

---

## 2. 应用入口 — `MenuBarExtra` + Liquid Glass

```swift
import SwiftUI

@main
struct GlassMonitorApp: App {
    @State private var monitor = SystemMonitor()   // @Observable,见 §4

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environment(monitor)
                .frame(width: 320)
                .background(.clear)               // 让 Liquid Glass 透出
        } label: {
            MenuBarLabel(cpu: monitor.cpu.usage)
        }
        .menuBarExtraStyle(.window)               // window 样式才能用自定义 SwiftUI
    }
}
```

> macOS 26 的 `MenuBarExtra(.window)` 弹窗默认即为 Liquid Glass 容器,**不要**再叠加 `.ultraThinMaterial`,会破坏玻璃折射。

---

## 3. 设计系统(对应 Web 原型 tokens)

```swift
enum Palette {
    static let cpu  = Color(hex: 0xFF7A45)   // 暖橙
    static let gpu  = Color(hex: 0xB57BFF)   // 紫
    static let mem  = Color(hex: 0x4DA3FF)   // 蓝
    static let disk = Color(hex: 0x32C896)   // 青
    static let net  = Color(hex: 0x5AC8FA)   // 天蓝
    static let batt = Color(hex: 0x34C759)   // 绿
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255)
    }
}
```

明暗模式自动跟随系统(SwiftUI 默认行为)。如需为玻璃面板增加色温差异:

```swift
@Environment(\.colorScheme) private var scheme
var tint: Color { scheme == .dark ? .blue.opacity(0.12) : .orange.opacity(0.10) }
```

---

## 4. 数据层 — `@Observable` + Async Stream

```swift
import Observation
import Darwin

@Observable
final class SystemMonitor {
    var cpu  = CPUStats()
    var gpu  = GPUStats()
    var mem  = MemoryStats()
    var disk = DiskStats()
    var net  = NetworkStats()
    var batt = BatteryStats()

    init() { Task { await loop() } }

    private func loop() async {
        for await _ in AsyncTimerSequence(interval: .seconds(1)) {
            cpu  = CPUSampler.sample()
            mem  = MemorySampler.sample()
            disk = DiskSampler.sample()
            net  = NetworkSampler.sample()
            batt = BatterySampler.sample()
            gpu  = await GPUSampler.sample()
        }
    }
}
```

### 关键采样 API

| 指标 | API |
|------|-----|
| CPU | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` |
| Memory | `host_statistics64(HOST_VM_INFO64)` + `vm_statistics64` |
| Disk | `URL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])` |
| Network | `getifaddrs()` 读 `if_data.ifi_obytes / ifi_ibytes` 计算速率 |
| Battery | `IOPSCopyPowerSourcesInfo()` + `IOPSGetPowerSourceDescription()` |
| GPU | `IOReportCreateSubscription` + `IOReport` 通道 `GPU Stats`(macOS 26 支持 Apple Silicon GPU 利用率读取) |

完整采样实现可参考 [iStats](https://github.com/exelban/stats) 与 Apple `powermetrics` 的开源对照。

---

## 5. 菜单栏图标 — 微型 Live Sparkline

```swift
struct MenuBarLabel: View {
    let cpu: Double  // 0...1
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
            Text("\(Int(cpu * 100))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}
```

> 需要彩色脉冲点时,使用 `SF Symbol` 的 `.palette` 渲染模式 + `.symbolEffect(.pulse)`(macOS 26 内建)。

---

## 6. 主面板 — 紧凑玻璃行

```swift
struct DashboardView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        VStack(spacing: 6) {
            MetricRow(icon: "cpu",                   label: "CPU",     tint: Palette.cpu,
                      value: m.cpu.usage,  detail: "\(Int(m.cpu.usage * 100))%",
                      samples: m.cpu.history)
            MetricRow(icon: "cpu.fill",              label: "GPU",     tint: Palette.gpu,
                      value: m.gpu.usage,  detail: "\(Int(m.gpu.usage * 100))%",
                      samples: m.gpu.history)
            MetricRow(icon: "memorychip",            label: "Memory",  tint: Palette.mem,
                      value: m.mem.ratio,  detail: m.mem.pretty)
            MetricRow(icon: "internaldrive",         label: "Storage", tint: Palette.disk,
                      value: m.disk.ratio, detail: m.disk.pretty)
            NetworkRow(stats: m.net)
            BatteryRow(stats: m.batt)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))   // macOS 26 Liquid Glass
    }
}
```

### 单行组件

```swift
struct MetricRow: View {
    let icon: String
    let label: String
    let tint: Color
    let value: Double          // 0...1
    let detail: String
    var samples: [Double] = []

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if !samples.isEmpty {
                Sparkline(samples: samples, tint: tint)
                    .frame(width: 56, height: 18)
            }

            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(0.08)),
                     in: .rect(cornerRadius: 14))
    }
}
```

> `glassEffect(_:in:)` 是 macOS 26 新增 API,自带高光、折射、动态模糊。**不要**再嵌套 `Material`。

---

## 7. Sparkline(Swift Charts)

```swift
import Charts

struct Sparkline: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(samples.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(
                    colors: [tint.opacity(0.5), tint.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", i), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(.init(lineWidth: 1.2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartPlotStyle { $0.background(.clear) }
    }
}
```

---

## 8. 网络与电池行(双数值展示)

```swift
struct NetworkRow: View {
    let stats: NetworkStats
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi").foregroundStyle(Palette.net).frame(width: 18)
            Text("Network").font(.system(size: 12, weight: .medium))
            Spacer()
            Label(stats.upPretty,   systemImage: "arrow.up")
                .labelStyle(.titleAndIcon).font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Label(stats.downPretty, systemImage: "arrow.down")
                .labelStyle(.titleAndIcon).font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .glassEffect(.regular.tint(Palette.net.opacity(0.08)),
                     in: .rect(cornerRadius: 14))
    }
}
```

电池行同构,使用 `bolt.fill` / `battery.100` 系列 SF Symbol,并在充电时加 `.symbolEffect(.variableColor.iterative)`。

---

## 9. 动效原则

- **不要** 自己写 `.animation(.spring)` 包整个面板。`@Observable` + 数值变化会自动触发隐式动画。
- 数值滚动:`Text("\(value)").contentTransition(.numericText(value: value))`
- 玻璃面板出现:`.transition(.glassAppear)`(macOS 26)
- 脉冲点:`.symbolEffect(.pulse, options: .repeating)`

---

## 10. 性能预算

| 项 | 目标 |
|----|------|
| CPU 占用(空闲) | < 0.3% |
| 内存常驻 | < 30 MB |
| 采样间隔 | 1 s(网络/CPU),5 s(磁盘/电池) |
| GPU IOReport 订阅 | 单次创建,App 生命周期复用 |

---

## 11. 发布

- 签名:Developer ID Application
- 公证:`xcrun notarytool submit ...`
- 分发:DMG(`create-dmg`)或 Homebrew Cask
- 需要在系统设置中启用 "登录时打开",通过 `SMAppService.mainApp.register()` 实现

---

## 12. 参考资源

- WWDC25 *Meet Liquid Glass on macOS*
- WWDC25 *What's new in MenuBarExtra*
- Apple Sample: *Adopting Liquid Glass*
- 开源参考:[Stats](https://github.com/exelban/stats)、[MonitorControl](https://github.com/MonitorControl/MonitorControl)

祝开发顺利 🚀
