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
            MenuBarMetricLabel(
                items: store.menuBarMetricItems,
                prefixStyle: store.settings.menuBarMetricPrefixStyle
            )
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
    var prefixStyle: MenuBarMetricPrefixStyle = .icon

    var body: some View {
        HStack(spacing: interCellSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                cell(for: item, isTrailing: index == items.count - 1)
            }
        }
        .font(labelFont)
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
    }

    /// 每个指标占一个独立的固定宽度单元:前缀(SF 图标 / CPU / ↑↓ 等)固定在左侧,
    /// 数值放进按「最大可能值」测得的定宽框、**左对齐**贴住前缀。短值时预留的
    /// 空白落在尾部,与指标间距合并成更大的「组间空隙」,视觉上数字始终跟自己的
    /// 前缀成一组。每格宽度仍固定,相邻指标位置不会左右抖动。
    /// 末位指标是整个菜单栏图标的右边缘,身后没有下一个指标可供分组,固定宽度
    /// 预留的尾部空白会直接变成图标右侧的空洞留白,故末位不做定宽预留,按实际
    /// 内容收紧,消除该处的空间浪费。
    private func cell(for item: MenuBarMetricItem, isTrailing: Bool) -> some View {
        HStack(spacing: symbolSpacing) {
            leading(for: item.kind)
            if isTrailing {
                Text(numericValue(for: item))
            } else {
                Text(numericValue(for: item))
                    .frame(width: valueWidth(for: item.kind), alignment: .leading)
            }
        }
    }

    /// 前缀视图:图标模式用 SF Symbol,文字模式用 CPU/GPU… 或网络的 ↑↓。
    @ViewBuilder
    private func leading(for kind: MenuBarMetricKind) -> some View {
        switch prefixStyle {
        case .icon:
            Image(systemName: kind.symbol)
        case .text:
            Text(textPrefix(for: kind))
        }
    }

    /// 文字前缀:带 `menuBarPrefix` 的直接用,网络无前缀则用方向箭头。
    private func textPrefix(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .networkDownload:
            "↓"
        case .networkUpload:
            "↑"
        default:
            kind.menuBarPrefix
        }
    }

    /// 纯数值:trim 掉格式化补的空白,并剥掉网络值里内嵌的 ↑/↓ 箭头
    /// (箭头由前缀部分统一呈现),宽度交给定宽框控制。
    private func numericValue(for item: MenuBarMetricItem) -> String {
        var value = Substring(item.value)
        if let first = value.first, first == "↑" || first == "↓" {
            value = value.dropFirst()
        }
        return value.trimmingCharacters(in: .whitespaces)
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

    /// 前缀与数值之间的间距(图标比文字略需留白)。
    private var symbolSpacing: CGFloat {
        prefixStyle == .icon ? 3 : 2
    }
}
