import SwiftUI

/// 游戏窗口顶部的单行 HUD；全部勾选项按目录顺序显示，不截断或省略读数。
struct GameHUDTopStripView: View {
    let snapshot: GameHUDSnapshot
    let fpsStats: GameHUDFPSStats?
    let enabledMetricIDs: Set<GameHUDMetricID>
    /// 背景透出程度(0...1)。只改变背景填充,文字与窗口 alpha 保持不变。
    var backgroundTransparency: Double = GameHUDBackgroundAppearance.defaultTransparency(for: .topStrip)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1, height: 13)
                }
                HStack(spacing: 4) {
                    Text(title(for: entry))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(value(for: entry.id))
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .frame(
                            minWidth: GameHUDMetricCatalog.topStripValueMinWidth(for: entry.id),
                            alignment: .trailing
                        )
                }
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: true)
        .shadow(
            color: .black.opacity(GameHUDBackgroundAppearance.textShadowOpacity(for: backgroundTransparency)),
            radius: 1.5,
            x: 0,
            y: 0.5
        )
        .background(
            GameHUDBackgroundAppearance.backgroundShape
                .fill(GameHUDBackgroundAppearance.backgroundColor(
                    for: .topStrip,
                    transparency: backgroundTransparency
                ))
        )
        .overlay {
            GameHUDBackgroundAppearance.backgroundShape
                .strokeBorder(
                    Color.white.opacity(GameHUDBackgroundAppearance.borderOpacity(for: backgroundTransparency)),
                    lineWidth: 0.75
                )
        }
    }

    private var entries: [GameHUDMetricCatalog.Entry] {
        GameHUDMetricCatalog.displayEntries(enabledIDs: enabledMetricIDs)
    }

    /// 等宽数字的内容变化共用尺寸，位数、单位或占位符变化时重新测量。
    var valueWidthSignatures: [String] {
        entries.map { entry in
            String(value(for: entry.id).map { $0.isASCII && $0.isNumber ? "0" : $0 })
        }
    }

    private func title(for entry: GameHUDMetricCatalog.Entry) -> String {
        String(localized: GameHUDMetricCatalog.compactTitleKey(for: entry.id))
    }

    private func value(for id: GameHUDMetricID) -> String {
        switch id {
        case .fps:
            return (fpsStats?.currentFPS ?? fpsStats?.averageFPS).map { String(format: "%.1f", $0) } ?? "—"
        case .averageFPS:
            return (fpsStats?.averageFPS ?? fpsStats?.currentFPS).map { String(format: "%.1f", $0) } ?? "—"
        case .onePercentLow:
            return fpsStats?.onePercentLow.map { String(format: "%.1f", $0) } ?? "—"
        case .frameTime:
            return fpsStats?.frameTimeMs.map { String(format: "%.1f ms", $0) } ?? "—"
        default:
            guard let reading = snapshot.readings.first(where: { $0.metricID == id.rawValue }) else {
                return "—"
            }
            return reading.compactValue ?? reading.value ?? "—"
        }
    }
}
