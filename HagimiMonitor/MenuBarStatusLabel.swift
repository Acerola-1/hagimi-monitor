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

    var body: some View {
        HStack(spacing: interCellSpacing) {
            ForEach(items) { item in
                cell(for: item)
            }
        }
        .font(labelFont)
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
    }

    /// 每个指标占一个独立的固定宽度单元:前缀(CPU / ↑↓ 等)固定在左侧,
    /// 数值放进按「最大可能值」测得的定宽框、右对齐。这样某个数值变宽/变窄
    /// 只在自己单元内变化,不会把相邻指标左右推挤——菜单栏整体宽度、各指标
    /// 位置都保持恒定。
    private func cell(for item: MenuBarMetricItem) -> some View {
        let parts = components(for: item)
        return HStack(spacing: parts.symbol.isEmpty ? 0 : symbolSpacing) {
            if !parts.symbol.isEmpty {
                Text(parts.symbol)
            }
            Text(parts.value)
                .frame(width: valueWidth(for: item.kind), alignment: .trailing)
        }
    }

    /// 把指标值拆成「固定前缀符号」+「数值」两部分。
    /// - 带文字前缀的(CPU/GPU/MEM…)前缀即 `menuBarPrefix`。
    /// - 网络无文字前缀,值以 ↑/↓ 箭头开头,箭头拆出作为固定符号。
    /// 数值一律 trim 掉格式化时补的空白,宽度交给定宽框统一控制。
    private func components(for item: MenuBarMetricItem) -> (symbol: String, value: String) {
        let prefix = item.kind.menuBarPrefix
        if !prefix.isEmpty {
            return (prefix, item.value.trimmingCharacters(in: .whitespaces))
        }
        if let first = item.value.first, first == "↑" || first == "↓" {
            let rest = item.value.dropFirst().trimmingCharacters(in: .whitespaces)
            return (String(first), String(rest))
        }
        return ("", item.value.trimmingCharacters(in: .whitespaces))
    }

    /// 数值框固定宽度:按该指标可能达到的最宽字符串测量(等宽数字字体),
    /// 保证数值在最大/最小值间切换时右对齐、右边缘不动。
    private func valueWidth(for kind: MenuBarMetricKind) -> CGFloat {
        let sample = reservedNumericValue(for: kind)
        let width = (sample as NSString).size(withAttributes: [.font: measuringFont]).width
        return ceil(width) + 2
    }

    private func reservedNumericValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryLevel:
            "100%"
        case .networkDownload, .networkUpload:
            "888M"
        case .cpuTemperature:
            "888°"
        case .storageFree:
            "888G"
        }
    }

    private var labelFont: Font {
        .system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    private var measuringFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
    }

    private var fontSize: CGFloat { 12 }

    /// 指标之间的间距。
    private var interCellSpacing: CGFloat { 6 }

    /// 前缀符号与数值之间的间距。
    private var symbolSpacing: CGFloat { 2 }
}
