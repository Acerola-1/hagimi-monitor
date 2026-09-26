import Foundation

/// Game HUD 硬件指标的稳定标识。存储用字符串与主面板指标 ID 解耦:
/// HUD 目录跨渠道能力不同,直接复用主面板勾选键会把「渠道不可读项」
/// 与「用户选择」搅在一起;映射到真实采样 ID 的规则集中在 catalog。
nonisolated enum GameHUDMetricID: String, CaseIterable, Sendable {
    /// 实时帧率 (FPS)。
    case fps
    /// 平均帧率 (Average FPS)。
    case averageFPS
    /// 1% 最低帧率 (1% Low FPS)。
    case onePercentLow
    /// 实时帧生成时间 (Frame Time, ms)。
    case frameTime
    /// 整机 CPU 占用(system+user 总口径)。
    case cpuUsage
    /// CPU 温度(官网版 SMC;沙盒被拒不出现在目录)。
    case cpuTemperature
    /// CPU 分项功耗(官网版 IOReport)。
    case cpuPower
    /// GPU Render 占用。
    case gpuRender
    /// GPU Tiler 占用。
    case gpuTiler
    /// GPU 分项功耗(官网版 IOReport)。
    case gpuPower
    /// GPU 驱动聚合内存(IOAccelerator "In use system memory")。
    /// 统一内存架构下没有独立显存,这是驱动聚合用量,文案不称「显存」。
    case gpuMemory
    /// 风扇转速(官网版 SMC)。
    case fanSpeed
    /// 整机内存已用量。
    case memoryUsed
    /// 整机功耗;真实可读时才可选,不代表游戏进程独占功耗。
    case systemPower
}

/// Game HUD 指标目录:渠道决定「本机有能力」,快照决定「本次有无值」。
///
/// 目录顺序即 HUD 与设置页展示顺序:
/// FPS 组(FPS → 平均帧 → 1% Low → 帧生成时间) → CPU 组(CPU 占用 → CPU 温度 → CPU 功耗) → GPU 组(GPU 功耗 → 显存占用) → 散热与整机(风扇转速 → 整机内存 → 整机功耗)。
nonisolated enum GameHUDMetricCatalog {

    struct Entry: Identifiable, Equatable, Sendable {
        let id: GameHUDMetricID
        let kind: MonitorKind
        /// 标题本地化 key;与主面板同语义的指标复用既有 key,不新增同义词。
        let titleKey: String.LocalizationValue
    }

    /// 当前渠道可用的条目,顺序即 HUD 展示顺序:FPS/AVG/1% Low/帧时间 → CPU 组 → GPU 组 → 散热与整机。
    /// 沙盒(App Store):CPU 占用 + 内存 + GPU 内存;整机功耗真实产出时可选。
    /// 官网版追加 FPS、平均帧、1% Low、帧生成时间、SMC CPU 温度与风扇转速、IOReport CPU/GPU 分项功耗。
    static func availableEntries() -> [Entry] {
        var entries: [Entry] = []
        #if DIRECT_DISTRIBUTION
        entries.append(Entry(id: .fps, kind: .gpu, titleKey: "gamehud.metric.fps"))
        entries.append(Entry(id: .averageFPS, kind: .gpu, titleKey: "gamehud.metric.average-fps"))
        entries.append(Entry(id: .onePercentLow, kind: .gpu, titleKey: "gamehud.metric.one-percent-low"))
        entries.append(Entry(id: .frameTime, kind: .gpu, titleKey: "gamehud.metric.frame-time"))
        #endif
        entries.append(Entry(id: .cpuUsage, kind: .cpu, titleKey: "gamehud.metric.cpu-usage"))
        #if DIRECT_DISTRIBUTION
        entries.append(Entry(id: .cpuTemperature, kind: .cpu, titleKey: "menu-bar-metric.cpu-temperature"))
        entries.append(Entry(id: .cpuPower, kind: .battery, titleKey: "gamehud.metric.cpu-power"))
        #endif
        #if DIRECT_DISTRIBUTION
        entries.append(Entry(id: .gpuPower, kind: .battery, titleKey: "gamehud.metric.gpu-power"))
        #endif
        entries.append(Entry(id: .gpuMemory, kind: .gpu, titleKey: "gamehud.metric.gpu-memory"))
        #if DIRECT_DISTRIBUTION
        entries.append(Entry(id: .fanSpeed, kind: .fan, titleKey: "gamehud.metric.fan-speed"))
        #endif
        entries.append(Entry(id: .memoryUsed, kind: .memory, titleKey: "gamehud.metric.memory-used"))
        entries.append(Entry(id: .systemPower, kind: .battery, titleKey: "gamehud.metric.system-power"))
        return entries
    }

    /// 默认勾选:FPS、平均帧、1% Low、帧时间、CPU/GPU 占用与内存。
    static func defaultEnabledIDs() -> Set<GameHUDMetricID> {
        var ids: Set<GameHUDMetricID> = [.cpuUsage, .memoryUsed, .gpuMemory]
        #if DIRECT_DISTRIBUTION
        ids.insert(.fps)
        ids.insert(.averageFPS)
        ids.insert(.onePercentLow)
        ids.insert(.frameTime)
        ids.insert(.gpuPower)
        ids.insert(.fanSpeed)
        #endif
        return ids
    }

    /// 把已勾选 ID 过滤为当前渠道真实可读的集合。
    /// 渠道不可读(能力缺失)与「本次采样 nil」在此分流:前者直接不出现在
    /// 快照里,后者进快照但 `value == nil` 显示 `—`。
    static func readableIDs(from enabled: Set<GameHUDMetricID>) -> Set<GameHUDMetricID> {
        let available = Set(availableEntries().map(\.id))
        return enabled.intersection(available)
    }
}
