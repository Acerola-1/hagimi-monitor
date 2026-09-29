import SwiftUI

/// 游戏窗口顶部的单行 HUD；全部勾选项按目录顺序显示，不截断或省略读数。
struct GameHUDTopStripView: View {
    let snapshot: GameHUDSnapshot
    let fpsStats: GameHUDFPSStats?
    let enabledMetricIDs: Set<GameHUDMetricID>

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
                        .foregroundStyle(Color.white)
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
        .background(Color.black.opacity(0.72))
    }

    private var entries: [GameHUDMetricCatalog.Entry] {
        GameHUDMetricCatalog.displayEntries(enabledIDs: enabledMetricIDs)
    }

    private func title(for entry: GameHUDMetricCatalog.Entry) -> String {
        switch entry.id {
        case .fps: String(localized: "gamehud.view.fps")
        case .averageFPS: String(localized: "gamehud.view.average-fps")
        case .onePercentLow: String(localized: "gamehud.view.one-percent-low")
        case .frameTime: String(localized: "gamehud.view.frame-time")
        default: String(localized: entry.titleKey)
        }
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
            return snapshot.readings.first { $0.metricID == id.rawValue }?.value ?? "—"
        }
    }
}
