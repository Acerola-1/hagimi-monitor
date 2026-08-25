import AppKit

/// 逐格内衬网格的度量常量。
enum MetricGridMetrics {
    /// 逐格内衬网格的列间距。
    static let columnSpacing: CGFloat = 8
    /// 逐格内衬网格的行间距:小于列距——行高本身已含格内上下内衬,
    /// 行距同宽会显松。
    static let gridRowGap: CGFloat = 5
    static let rowSpacing: CGFloat = 6
    static let cellHStackSpacing: CGFloat = 6
    static let cellSpacerMinLength: CGFloat = 4
}

/// 指标格静态宽度基准:整行/半行登记、最坏值契约与测量字体。
/// 布局决策是「语言 × 登记表」的纯函数,不随采样值与面板宽度重排;
/// 半格预算按语言独立判定——zh 标签普遍两字,半行能容纳的指标比
/// en 多,同一指标在两语下的布局归属可以不同(语言在一次运行内
/// 不变,不构成跳动源)。登记依据是各语言 × 最坏值 × 最窄面板宽的
/// 构建期审计(HagimiMonitorTests/MetricWidthAuditTests)。
enum StaticMetricSizing {
    /// 半格内容宽,按最窄支持面板宽 300 推导:
    /// 300 − 两侧内边距 10×2 − 网格前导缩进 28 = 252,两列减 8 间距得
    /// 每列 122,再减格子左右内衬 8×2 = 106。按最窄档登记,
    /// 300~460 全区间判定一致成立,面板调整不触发重排。
    static let halfCellContentWidth: CGFloat = 106

    /// 格内横向占用:标签与数值之间的 HStack 间距 + Spacer 最小长度。
    static let cellHorizontalSpacing: CGFloat =
        MetricGridMetrics.cellHStackSpacing + MetricGridMetrics.cellSpacerMinLength

    /// 与渲染同规格的测量字体(SwiftUI .footnote 即 13pt;数字 mono bold、
    /// 单位/标签 medium)。运行时判定已不再测量,这组字体供构建期审计
    /// 与渲染口径对齐使用。
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    static let unitFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// 当前面板语言:与 String(localized:) 同源(Bundle 按用户偏好解析
    /// 出的首个可用本地化);切换语言需重启,运行期内恒定。
    static var panelLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    }

    /// 结构性整行(语言无关):布局形态超出「标签+值」文本宽度能覆盖的
    /// 范围。wifi-rssi 是标签+信号条+数值+单位四件套,信号条是固定宽度
    /// 部件;gateway-latency 与其语义配对,同排保持网络块纵列节奏。
    static let structuralFullRowMetricIDs: Set<String> = [
        "network.wifi-rssi", "network.gateway-latency"
    ]

    /// 各语言整行登记:键 "kind.name"。时长/地址/容量类长值两语一致
    /// 升整行;pressure/compressed 是 en 专属——en 标签加最坏值超半格
    /// 预算,zh 短标签半行放得下,各语言取各自最优布局。
    static let fullRowMetricIDsByLanguage: [String: Set<String>] = [
        "zh-Hans": [
            // 「888天88小时」级时长值约 86pt,标签再无压缩空间
            "cpu.uptime",
            // SSID 名称无界,整行 + 中部截断
            "network.wifi-ssid",
            // 15 字符 IPv4 地址即 117pt,半格放不下
            "network.ipv4",
            // IPv6 展开形态上界 39 字符
            "network.ipv6",
            // 公网地址可为 IPv6
            "network.public-ip",
            "network.ip-address",
            // 「8888 / 8888 mAh」单值即超出半格
            "battery.capacity"
        ],
        "en": [
            "cpu.uptime",
            "network.wifi-ssid",
            "network.ipv4",
            "network.ipv6",
            "network.public-ip",
            "network.ip-address",
            "battery.capacity",
            // 「Pressure」+「Critical」= 111pt 超预算
            "memory.pressure",
            // 「Compressed」标签 78pt,GB 级两位小数值放不下
            "memory.compressed"
        ]
    ]

    /// 整行判定:结构性登记与当前语言登记表的纯查表,与采样值无关。
    static func isFullRow(kind: MonitorKind, name: String, language: String = panelLanguage) -> Bool {
        let key = "\(kind.rawValue).\(name)"
        return structuralFullRowMetricIDs.contains(key)
            || fullRowMetricIDsByLanguage[language]?.contains(key) == true
    }
}

extension StaticMetricSizing {
    /// 可测量格的最坏值契约:数字段与可选单位,对应 splitValueUnit
    /// 拆分后的渲染形态。最坏值覆盖各格式化函数自适应单位与固定小数位
    /// 下的最宽形态,时长类取两语中最宽的 zh 形态按保守方向审计;
    /// 超出登记口径的硬件极值(如 512GB 级内存的「490.11 GB」)由
    /// 渲染端 minimumScaleFactor 保险丝兜底。
    struct WorstValue {
        let number: String
        let unit: String?
    }

    /// 审计条目的形态归类:只登记「怎么测」;整行/半行的布局决策在
    /// fullRowMetricIDsByLanguage。
    enum CellLayout {
        /// 文本值格:附带最坏值契约;在每个判定为半行的语言里做预算
        /// 断言——从某语言的整行登记中移除后,该语言即开始审计,
        /// 放不下会被测试拦截,登记即布局决策。
        case measured(WorstValue)
        /// 枚举值格(如内存压力/SMART 状态):最坏值取各语言最长枚举文案
        case enumMeasured(valueKeys: [String])
        /// 网格外特殊形态:热压力合并行、core-split 的 P/E 瓦片取代、
        /// 行头/pill/功率流,不做预算断言
        case specialForm
    }

    /// 网格指标审计条目:指标网格可出现的全部指标的最坏值契约,
    /// 与 xcstrings 中 metric.(cpu|gpu|memory|storage|network|battery).*
    /// 键一一对应;新增指标未登记会被审计测试拦截。
    struct AuditEntry {
        let kind: MonitorKind
        let name: String
        let layout: CellLayout

        var labelKey: String { "metric.\(kind.rawValue).\(name)" }
    }

    static let auditInventory: [AuditEntry] = [
        // CPU(percent() 内嵌百分号,unit 不标注)
        AuditEntry(kind: .cpu, name: "system", layout: .measured(WorstValue(number: "100%", unit: nil))),
        AuditEntry(kind: .cpu, name: "user", layout: .measured(WorstValue(number: "100%", unit: nil))),
        AuditEntry(kind: .cpu, name: "idle", layout: .measured(WorstValue(number: "100%", unit: nil))),
        AuditEntry(kind: .cpu, name: "uptime", layout: .measured(WorstValue(number: "888天88小时", unit: nil))),
        AuditEntry(kind: .cpu, name: "thermal-pressure", layout: .specialForm),
        AuditEntry(kind: .cpu, name: "core-split", layout: .specialForm),
        // GPU(bytes() 千进制两位小数,最宽形态在百 GB 内)
        AuditEntry(kind: .gpu, name: "gpu-memory", layout: .measured(WorstValue(number: "99.99 GB", unit: nil))),
        AuditEntry(kind: .gpu, name: "allocated", layout: .measured(WorstValue(number: "99.9 GB", unit: nil))),
        AuditEntry(kind: .gpu, name: "render", layout: .measured(WorstValue(number: "100%", unit: nil))),
        AuditEntry(kind: .gpu, name: "tiler", layout: .measured(WorstValue(number: "100%", unit: nil))),
        AuditEntry(kind: .gpu, name: "temperature", layout: .measured(WorstValue(number: "100", unit: "°C"))),
        // 内存(used/swap/compressed 为任意小数,契约覆盖 ≤128GB 常规内存;
        // total 为整 GiB;swap 用短标签(en「Swap」/zh「交换」)换得半行)
        AuditEntry(kind: .memory, name: "used", layout: .measured(WorstValue(number: "99.99 GB", unit: nil))),
        AuditEntry(kind: .memory, name: "pressure", layout: .enumMeasured(valueKeys: [
            "memory-pressure.normal", "memory-pressure.warning", "memory-pressure.critical"
        ])),
        AuditEntry(kind: .memory, name: "swap-used", layout: .measured(WorstValue(number: "99.99 GB", unit: nil))),
        AuditEntry(kind: .memory, name: "total", layout: .measured(WorstValue(number: "512 GB", unit: nil))),
        AuditEntry(kind: .memory, name: "compressed", layout: .measured(WorstValue(number: "99.99 GB", unit: nil))),
        AuditEntry(kind: .memory, name: "usage", layout: .specialForm),
        // 存储(bytes() 千进制,内置磁盘上界 8TB 输出 "8,000 GB")
        AuditEntry(kind: .storage, name: "used", layout: .measured(WorstValue(number: "8,000 GB", unit: nil))),
        AuditEntry(kind: .storage, name: "free", layout: .measured(WorstValue(number: "8,000 GB", unit: nil))),
        AuditEntry(kind: .storage, name: "total", layout: .measured(WorstValue(number: "8,000 GB", unit: nil))),
        AuditEntry(kind: .storage, name: "smart", layout: .enumMeasured(valueKeys: ["storage-smart.verified", "storage-smart.failing"])),
        // 网络(bytesPerSecond 整串渲染;万兆以内最宽 "9.9 GB/s";
        // 地址/SSID 为无界长值,登记最宽已知形态)
        AuditEntry(kind: .network, name: "upload", layout: .measured(WorstValue(number: "9.9 GB/s", unit: nil))),
        AuditEntry(kind: .network, name: "download", layout: .measured(WorstValue(number: "9.9 GB/s", unit: nil))),
        AuditEntry(kind: .network, name: "wifi-rssi", layout: .measured(WorstValue(number: "-100 dBm", unit: nil))),
        AuditEntry(kind: .network, name: "gateway-latency", layout: .measured(WorstValue(number: "999 ms", unit: nil))),
        AuditEntry(kind: .network, name: "wifi-ssid", layout: .measured(WorstValue(number: "Network-Name-5GHz", unit: nil))),
        AuditEntry(kind: .network, name: "ipv4", layout: .measured(WorstValue(number: "255.255.255.255", unit: nil))),
        AuditEntry(kind: .network, name: "ipv6", layout: .measured(WorstValue(number: "0000:0000:0000:0000:0000:0000:0000:0000", unit: nil))),
        AuditEntry(kind: .network, name: "public-ip", layout: .measured(WorstValue(number: "0000:0000:0000:0000:0000:0000:0000:0000", unit: nil))),
        AuditEntry(kind: .network, name: "ip-address", layout: .measured(WorstValue(number: "0000:0000:0000:0000:0000:0000:0000:0000", unit: nil))),
        // 电池
        AuditEntry(kind: .battery, name: "health", layout: .measured(WorstValue(number: "100", unit: "%"))),
        AuditEntry(kind: .battery, name: "cycle-count", layout: .measured(WorstValue(number: "88888", unit: nil))),
        AuditEntry(kind: .battery, name: "temperature", layout: .measured(WorstValue(number: "100", unit: "°C"))),
        AuditEntry(kind: .battery, name: "power-loss", layout: .measured(WorstValue(number: "888.8", unit: "W"))),
        AuditEntry(kind: .battery, name: "voltage", layout: .measured(WorstValue(number: "88.88", unit: "V"))),
        AuditEntry(kind: .battery, name: "current", layout: .measured(WorstValue(number: "8888", unit: "mA"))),
        AuditEntry(kind: .battery, name: "capacity", layout: .measured(WorstValue(number: "8888 / 8888 mAh", unit: nil))),
        AuditEntry(kind: .battery, name: "status", layout: .specialForm),
        AuditEntry(kind: .battery, name: "adapter", layout: .specialForm),
        AuditEntry(kind: .battery, name: "power", layout: .specialForm),
        AuditEntry(kind: .battery, name: "charging-power", layout: .specialForm),
        AuditEntry(kind: .battery, name: "type", layout: .specialForm)
    ]
}
