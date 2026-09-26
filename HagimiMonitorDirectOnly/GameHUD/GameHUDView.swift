import SwiftUI

/// Game HUD 卡片的固定尺寸与容量契约(见 spec:内容稳定)。
/// 布局随勾选条目数确定,临时缺值显示 `—` 不改变尺寸;勾选数变化时
/// 高度按行数收敛,不逐帧抖动。
nonisolated enum GameHUDViewContract {

    /// 排版对齐官方 Metal HUD 与微星小飞机风格:等宽字体、白字右对齐两列、
    /// 紧凑行距 + 分组留白、纯黑半透明底。
    struct Metrics {
        static let cardWidth: CGFloat = 260
        static let rowHeight: CGFloat = 22
        static let verticalPadding: CGFloat = 12
        static let rowSpacing: CGFloat = 5
        static let maxRows = 16
        static let font: CGFloat = 13
    }

    /// 卡片尺寸:宽度固定;高度 = 上下内边距 + 头部与各项指标行(含行内高度与间距) + 分割线。
    /// 高度精确自适应已勾选的指标项数，缺值显示 `—` 占位，绝不因数据就绪与否发生二次跳变。
    static func size(for enabledIDs: Set<GameHUDMetricID>, fpsStats: GameHUDFPSStats? = nil) -> CGSize {
        let entries = GameHUDMetricCatalog.availableEntries().filter { enabledIDs.contains($0.id) }
        let hardwareEntries = entries.filter { $0.id != .fps && $0.id != .averageFPS && $0.id != .onePercentLow && $0.id != .frameTime }

        let showFPS = enabledIDs.contains(.fps)
        let showAvg = enabledIDs.contains(.averageFPS)
        let showLow = enabledIDs.contains(.onePercentLow)
        let showFrameTime = enabledIDs.contains(.frameTime)

        var rows = 1 + hardwareEntries.count // 头部 (chip/macOS) + 硬件指标行
        if showFPS { rows += 1 }
        if showAvg { rows += 1 }
        if showLow { rows += 1 }
        if showFrameTime { rows += 1 }

        // 每行有效高度为 17pt，行间距 5pt。
        // R 行 + 间隔的总高度正好为 R * rowHeight (22pt)。
        // 加上 1pt 细分割线以及上下各 verticalPadding (12pt)。
        let height = Metrics.verticalPadding * 2 + CGFloat(rows) * Metrics.rowHeight + 1
        return CGSize(width: Metrics.cardWidth, height: height)
    }

    /// 兼容重载
    static func size(for enabledIDs: Set<GameHUDMetricID>, hasFPS: Bool) -> CGSize {
        return size(for: enabledIDs, fpsStats: nil)
    }
}

/// 硬件 HUD 卡片视图:紧凑行。卡片底固定为半透明黑
/// (浮在任意游戏画面上,与探针验证的样式一致),文字固定用深色外观的
/// 令牌值——黑底必须配浅色文字,不随系统外观切换,否则浅色模式黑底黑字。
struct GameHUDView: View {
    let snapshot: GameHUDSnapshot
    /// 帧率统计(系统探针或 SCK 测得);nil = 样本不足,显示 `—` 占位保证尺寸一次性初始化。
    var fpsStats: GameHUDFPSStats?
    /// 用户勾选的全部 HUD 指标集合(用于精确判断 FPS / AVG / 1% Low / 各硬件行显隐)。
    var enabledMetricIDs: Set<GameHUDMetricID> = GameHUDMetricCatalog.defaultEnabledIDs()

    var body: some View {
        VStack(alignment: .leading, spacing: GameHUDViewContract.Metrics.rowSpacing) {
            // 头部:芯片 / macOS 版本(左标签右数值,同官方 HUD 头部)。
            metricRow(label: chipName, value: macOSVersion)
            // 顶部与属性间的细分割线，强化视觉分层
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
            // 核心指标: FPS、AVG 与 1% Low (微星小飞机/游戏加加风格紧凑布局, 保留 1 位小数; 缺值显示 — 稳定占位, 一次性初始化)
            if enabledIDs.contains(.fps) {
                let valueStr = (fpsStats?.currentFPS ?? fpsStats?.averageFPS).map {
                    String(localized: "gamehud.view.fps-unit-decimal \(String(format: "%.1f", max(0, $0)))")
                } ?? "—"
                metricRow(
                    label: String(localized: "gamehud.view.fps"),
                    value: valueStr
                )
            }
            if enabledIDs.contains(.averageFPS) {
                let valueStr = (fpsStats?.averageFPS ?? fpsStats?.currentFPS).map {
                    String(localized: "gamehud.view.fps-unit-decimal \(String(format: "%.1f", max(0, $0)))")
                } ?? "—"
                metricRow(
                    label: String(localized: "gamehud.view.average-fps"),
                    value: valueStr
                )
            }
            if enabledIDs.contains(.onePercentLow) {
                let valueStr = fpsStats?.onePercentLow.map {
                    String(localized: "gamehud.view.fps-unit-decimal \(String(format: "%.1f", max(0, $0)))")
                } ?? "—"
                metricRow(
                    label: String(localized: "gamehud.view.one-percent-low"),
                    value: valueStr
                )
            }
            if enabledIDs.contains(.frameTime) {
                let valueStr = fpsStats?.frameTimeMs.map {
                    String(format: "%.1f ms", $0)
                } ?? "—"
                metricRow(
                    label: String(localized: "gamehud.view.frame-time"),
                    value: valueStr
                )
            }
            ForEach(displayRows) { row in
                metricRow(label: row.title, value: row.value)
            }
        }
        .padding(.vertical, GameHUDViewContract.Metrics.verticalPadding)
        .padding(.horizontal, 14)
        .frame(width: GameHUDViewContract.Metrics.cardWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.68))
        )
    }

    /// 官方 HUD 风格的行:等宽字体,左标签、右数值,同为白色同字号。
    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: GameHUDViewContract.Metrics.font, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: GameHUDViewContract.Metrics.font, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
        }
        .frame(height: GameHUDViewContract.Metrics.rowHeight - GameHUDViewContract.Metrics.rowSpacing)
    }

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// 芯片型号(如 "Apple M4"):sysctl machdep.cpu.brand_string 精简。
    private var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        let full = String(cString: name)
        return full
    }

    private var enabledIDs: Set<GameHUDMetricID> {
        enabledMetricIDs
    }

    private struct DisplayRow: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private var displayRows: [DisplayRow] {
        let hardware = snapshot.readings.filter {
            $0.metricID != GameHUDMetricID.fps.rawValue &&
            $0.metricID != GameHUDMetricID.averageFPS.rawValue &&
            $0.metricID != GameHUDMetricID.onePercentLow.rawValue &&
            $0.metricID != GameHUDMetricID.frameTime.rawValue
        }
        return hardware.map { reading in
            let title = title(for: reading)
            let value = reading.value ?? "—"
            return DisplayRow(id: reading.metricID, title: title, value: value)
        }
    }

    /// 标题取目录 key 本地化;value 为 nil 的行同样保留标题(spec:保留行)。
    private func title(for reading: GameHUDReading) -> String {
        guard let id = GameHUDMetricID(rawValue: reading.metricID) else {
            return reading.metricID
        }
        let entry = GameHUDMetricCatalog.availableEntries().first { $0.id == id }
        return String(localized: entry?.titleKey ?? String.LocalizationValue(reading.metricID))
    }
}
