import Foundation

/// 报表「运行状态」组的实时读数。
///
/// 报表是静态快照(打开时生成一次),但右栏的「运行状态」组要跟着每秒刷新,
/// 所以由 App 侧按 `(模块, 标签)` 推给网页。这里只负责从 `MonitorStore` 取当前值
/// 并做成人可读的字符串。
///
/// 三条纪律:
/// ① **只推真的读到的**。缺失的键不出现在结果里,网页上那一行保持 “—”,
///    不拿 0 或上一帧的值冒充;
/// ② **主读数原样透传** `summary`——各采样器的 `percent()` 已经带了百分号,
///    这里再拼一个会得到 `12%%`,桌面电池模块则会出现 `ac-power%`;
/// ③ 枚举 id(fair/serious/ac-power)要过本地化,别把机器词端到中文界面上。
/// 行名是文案短键(`stats.r.hwLive*`),与前端 `HW_LIVE_ROWS` 一一对应、显示时由
/// 前端 `t()` 解析——两侧同改,推送与匹配都走 key,不走显示文本。
enum HardwareLiveReadings {

    /// 返回 `["cpu": ["hwLiveCpuUsage": "12%", ...], ...]`(键为文案短键)。
    static func snapshot(from store: MonitorStore) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for module in store.modules {
            guard let readings = readings(for: module) else { continue }
            result[key(for: module.kind)] = readings
        }
        return result
    }

    /// 模块 → 前端作用域 id。与 `HardwareSection.js` 的 `HW_MODULES` 对齐。
    private static func key(for kind: MonitorKind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        case .memory: return "memory"
        case .network: return "network"
        case .storage: return "disk"
        case .battery: return "power"
        case .fan: return "fan"
        case .bluetooth: return "bluetooth"
        }
    }

    /// 单个模块的实时行。`internal` 供 `HardwareLiveReadingsTests` 直接构造
    /// 模块断言取值规则——summary/metric 的语义坑(百分号、接口名 vs 速率)
    /// 只有对着真实模块值才测得出来,采样器侧测不到这层。
    static func readings(for module: MonitorModule) -> [String: String]? {
        // 占位模块(采样失败/未产出)整块不推:它上面的值不是真实读数。
        guard !module.isPlaceholder else { return nil }

        func metric(_ name: String) -> String? {
            guard let value = module.metrics.first(where: { $0.name == name })?.value,
                  value != "--" else { return nil }
            return value
        }
        /// 模块主读数。`summary` 已是显示态(百分比自带 %,桌面电池是 "ac-power"),
        /// 原样透传;只把「无数据」的两个占位形态滤掉。
        func headline() -> String? {
            let text = module.summary
            return (text.isEmpty || text == "--") ? nil : text
        }

        switch module.kind {
        case .cpu:
            return compact([
                "hwLiveCpuUsage": headline(),
                "hwLiveThermal": metric("thermal-pressure").map { localized("thermal-pressure", $0) },
                "hwLiveProcessCount": metric("process-count"),
                "hwLiveIdle": metric("idle"),
            ])
        case .gpu:
            // 不列「核心温度」:GPUSampler 不产出 temperature 指标,那一行只会永远是 “—”。
            return compact([
                "hwLiveGpuUsage": headline(),
                "hwLiveGpuMemory": metric("gpu-memory"),
                "hwLiveRenderer": metric("render"),
                "hwLiveTiler": metric("tiler"),
            ])
        case .memory:
            return compact([
                "hwLiveMemUsed": headline(),
                "hwLiveCompressed": metric("compressed"),
                "hwLiveSwap": metric("swap-used"),
                "hwLivePressure": metric("pressure-level").map { localized("memory-pressure", $0) },
            ])
        case .storage:
            return compact([
                "hwLiveDiskUsed": headline(),
                "hwLiveDiskFree": metric("free"),
                "hwLiveDiskRead": metric("disk-read-rate"),
                "hwLiveDiskWrite": metric("disk-write-rate"),
            ])
        case .network:
            // 下行/上行是速率指标;`summary` 存的是接口名(「Wi-Fi」/「en0」),不是速率。
            return compact([
                "hwLiveDownload": metric("download"),
                "hwLiveUpload": metric("upload"),
                "hwLiveSignal": metric("wifi-rssi"),
            ])
        case .battery:
            return compact([
                "hwLiveBatteryLevel": headline(),
                "hwLiveBatteryState": metric("status").map { localized("battery-state", $0) },
                "hwLiveBatteryTemp": metric("temperature"),
            ])
        case .fan, .bluetooth:
            // 风扇/蓝牙不进报表右栏(没有对应模块块),不推。
            return nil
        }
    }

    /// 采样器给的是枚举 id(热压力 fair/serious、电池状态 ac-power),直接上屏会在
    /// 中文界面露出英文机器词。按键约定找同源文案,查不到就原样返回——
    /// 宁可露出 id,也不要编一个可能不对的中文。
    private static func localized(_ group: String, _ id: String) -> String {
        let key = "\(group).\(id)"
        let text = String(localized: String.LocalizationValue(key))
        return text == key ? id : text
    }

    /// 去掉取不到的键——缺失就让它留在网页上的 “—”,不要用空串覆盖。
    /// 行顺序由前端的 `HW_LIVE_ROWS` 决定,这里只做「标签 → 值」的映射。
    private static func compact(_ pairs: [String: String?]) -> [String: String] {
        var result: [String: String] = [:]
        for (label, value) in pairs {
            if let value, !value.isEmpty { result[label] = value }
        }
        return result
    }
}
