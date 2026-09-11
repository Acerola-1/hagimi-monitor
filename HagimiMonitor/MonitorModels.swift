import Foundation
import SwiftUI
import Combine
import OSLog
import IOKit.ps

enum HaloRingSource: String, CaseIterable, Identifiable {
    case combined
    case cpu
    case gpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: String(localized: "ring-source.combined")
        case .cpu: String(localized: "ring-source.cpu")
        case .gpu: String(localized: "ring-source.gpu")
        case .memory: String(localized: "ring-source.memory")
        }
    }
}

enum MemoryPressureLevel: Int, Equatable {
    case normal = 0
    case warning = 1
    case critical = 2
    case unknown = 3

    var identifier: String {
        switch self {
        case .normal:
            "normal"
        case .warning:
            "warning"
        case .critical:
            "critical"
        case .unknown:
            "--"
        }
    }
}

enum MonitorSeverity {
    case calm
    case warning
    case critical

    var title: String {
        switch self {
        case .calm:
            String(localized: "severity.calm")
        case .warning:
            String(localized: "severity.warning")
        case .critical:
            String(localized: "severity.critical")
        }
    }
}

enum MonitorKind: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    /// 风扇:独立于 SystemMonitorSampler,数据由 FanSampler 注入,仅 fanAvailable 时存在。
    /// 可见性与其余模块一致走用户开关;无风扇机型由设置侧栏按 fanAvailable 隐藏入口。
    /// 声明顺序即设置侧栏顺序——放在 GPU 之后与面板侧 applyFanModule 的插入位
    /// (GPU 之后、内存之前)对齐,两处顺序共用这一个来源,不再各排各的。
    case fan
    case memory
    case storage
    case network
    case battery
    /// 蓝牙设备电量:独立于 SystemMonitorSampler,数据由 BluetoothBatterySampler 注入,
    /// 蓝牙开启时常驻(无连接设备时显示 0 台)。声明在 battery 之后,面板中落在电源行与
    /// 显示器区之间;可见性与其余模块一致走用户开关。
    case bluetooth

    var id: String { rawValue }

    /// 用户可开关的模块全集(含风扇)。无风扇机型由 SettingsSidebar 按
    /// fanAvailable 过滤掉风扇入口,不出现无效开关。
    static let userVisibleCases: [MonitorKind] = allCases

    /// SystemMonitorSampler 管线驱动的模块全集。风扇/蓝牙的输出是「设备列表」
    /// 而非「单模块值」,由各自独立采样器产出、MonitorStore 合成注入,不进采样
    /// 排期——排期会令无注册采样器的类目每秒空转报错。
    static let samplerBackedCases: [MonitorKind] = [.cpu, .gpu, .memory, .storage, .network, .battery]

    var title: String {
        switch self {
        case .cpu:
            String(localized: "kind.cpu")
        case .gpu:
            String(localized: "kind.gpu")
        case .memory:
            String(localized: "kind.memory")
        case .storage:
            String(localized: "kind.storage")
        case .network:
            String(localized: "kind.network")
        case .battery:
            String(localized: "kind.battery")
        case .fan:
            String(localized: "kind.fan")
        case .bluetooth:
            String(localized: "kind.bluetooth")
        }
    }

    var symbol: String {
        switch self {
        case .cpu:
            "cpu"
        case .gpu:
            "display"
        case .memory:
            "memorychip"
        case .storage:
            "internaldrive"
        case .network:
            "network"
        case .battery:
            "powerplug"
        case .fan:
            "fan.fill"
        case .bluetooth:
            // SF Symbols 无蓝牙符号(Apple 因商标原因不提供),symbolImage 改用
            // 自绘符文资产;symbol 保留耳机形仅作兜底。
            "headphones"
        }
    }

    /// 面板/设置侧栏实际渲染的图标。蓝牙模块用自绘符文模板资产,
    /// 其余模块用 SF Symbols。
    var symbolImage: Image {
        if self == .bluetooth {
            return Image("BluetoothGlyph")
        }
        return Image(systemName: symbol)
    }

    var availableMetrics: [MetricSwitch] {
        switch self {
        case .cpu:
            // 温度读数来自 SMC(IOServiceOpen AppleSMC),App Store 沙盒版被拒,
            // CPUSampler 只在 DISPLAY_CONTROL 下产出该指标。面板中温度与热压力
            // 合并为「热压力」整行(直连版展示「温度 / 热压力」);菜单栏温度选项
            // 独立读取温度指标,不受面板合并影响。
            // P/E 合并为单一指标「P/E 核」,值为「82% / 35%」。
            return [
                MetricSwitch(id: "system", title: String(localized: "metric.cpu.system"), isDefault: true),
                MetricSwitch(id: "user", title: String(localized: "metric.cpu.user"), isDefault: true),
                MetricSwitch(id: "idle", title: String(localized: "metric.cpu.idle"), isDefault: true),
                MetricSwitch(id: "process-count", title: String(localized: "metric.cpu.process-count"), isDefault: true),
                MetricSwitch(id: "uptime", title: String(localized: "metric.cpu.uptime"), isDefault: true),
                MetricSwitch(id: "thermal-pressure", title: String(localized: "metric.cpu.thermal-pressure"), isDefault: true),
                MetricSwitch(id: "core-split", title: String(localized: "metric.cpu.core-split"), isDefault: true),
            ]
        case .gpu:
            var metrics = [
                MetricSwitch(id: "gpu-memory", title: String(localized: "metric.gpu.gpu-memory"), isDefault: true),
                MetricSwitch(id: "allocated", title: String(localized: "metric.gpu.allocated"), isDefault: true),
                MetricSwitch(id: "render", title: String(localized: "metric.gpu.render"), isDefault: true),
                MetricSwitch(id: "tiler", title: String(localized: "metric.gpu.tiler"), isDefault: true),
            ]
            #if DIRECT_DISTRIBUTION
            // 时钟态常驻;限频与功耗上限只在偏离常态时占格,故默认开也不扰布局。
            metrics.append(MetricSwitch(id: "clock-state", title: String(localized: "metric.gpu.clock-state"), isDefault: true))
            metrics.append(MetricSwitch(id: "throttle", title: String(localized: "metric.gpu.throttle"), isDefault: true))
            metrics.append(MetricSwitch(id: "power-cap", title: String(localized: "metric.gpu.power-cap"), isDefault: true))
            #endif
            return metrics
        case .memory:
            var metrics = [
                MetricSwitch(id: "used", title: String(localized: "metric.memory.used"), isDefault: true),
                MetricSwitch(id: "pressure", title: String(localized: "metric.memory.pressure"), isDefault: true),
                MetricSwitch(id: "swap-used", title: String(localized: "metric.memory.swap-used"), isDefault: true),
                MetricSwitch(id: "total", title: String(localized: "metric.memory.total"), isDefault: true),
                MetricSwitch(id: "compressed", title: String(localized: "metric.memory.compressed"), isDefault: true),
            ]
            #if DIRECT_DISTRIBUTION
            metrics.append(MetricSwitch(id: "memory-bandwidth", title: String(localized: "metric.memory.memory-bandwidth"), isDefault: true))
            #endif
            return metrics
        case .storage:
            return [
                MetricSwitch(id: "used", title: String(localized: "metric.storage.used"), isDefault: true),
                MetricSwitch(id: "free", title: String(localized: "metric.storage.free"), isDefault: true),
                MetricSwitch(id: "total", title: String(localized: "metric.storage.total"), isDefault: true),
                MetricSwitch(id: "smart", title: String(localized: "metric.storage.smart"), isDefault: true),
            ]
        case .network:
            return [
                MetricSwitch(id: "ipv4", title: String(localized: "metric.network.ipv4"), isDefault: true),
                MetricSwitch(id: "ipv6", title: String(localized: "metric.network.ipv6"), isDefault: true),
                MetricSwitch(id: "public-ip", title: String(localized: "metric.network.public-ip"), isDefault: true),
                MetricSwitch(id: "wifi-rssi", title: String(localized: "metric.network.wifi-rssi"), isDefault: true),
                MetricSwitch(id: "gateway-latency", title: String(localized: "metric.network.gateway-latency"), isDefault: true),
                MetricSwitch(id: "wifi-ssid", title: String(localized: "metric.network.wifi-ssid"), isDefault: true),
            ]
        case .battery:
            var metrics = [
                // 充电功率在电源行以常驻 CHG pill 展示,不作为可开关的明细项。
                // 充电限制/低电量模式不进明细网格:前者只保留在功率流电池条的
                // 刻度线上,后者只保留行头图标着色(纯状态文本行信息量低)。
                MetricSwitch(id: "health", title: String(localized: "metric.battery.health"), isDefault: true),
                MetricSwitch(id: "cycle-count", title: String(localized: "metric.battery.cycle-count"), isDefault: true),
                MetricSwitch(id: "temperature", title: String(localized: "metric.battery.temperature"), isDefault: true),
                MetricSwitch(id: "power-loss", title: String(localized: "metric.battery.power-loss"), isDefault: true)
            ]
            #if DIRECT_DISTRIBUTION
            // IOReport 是私有 API，整机与分项功耗只在 Direct 版开放为明细开关。
            metrics.append(contentsOf: [
                MetricSwitch(id: "power", title: String(localized: "metric.battery.power"), isDefault: true),
                MetricSwitch(id: "display-power", title: String(localized: "metric.battery.display-power"), isDefault: true),
                MetricSwitch(
                    id: "cpu-power",
                    title: String(localized: "metric.battery.cpu-power"),
                    isDefault: true,
                    tip: String(localized: "settings.battery.cpu-power.tip")
                ),
                MetricSwitch(id: "gpu-power", title: String(localized: "metric.battery.gpu-power"), isDefault: true),
                MetricSwitch(
                    id: "ane-power",
                    title: String(localized: "metric.battery.ane-power"),
                    isDefault: true,
                    tip: String(localized: "settings.battery.ane-power.tip")
                )
            ])
            #endif
            metrics.append(contentsOf: [
                MetricSwitch(id: "voltage", title: String(localized: "metric.battery.voltage"), isDefault: true),
                MetricSwitch(id: "current", title: String(localized: "metric.battery.current"), isDefault: true),
                MetricSwitch(id: "cell-balance", title: String(localized: "metric.battery.cell-balance"), isDefault: true),
                // 剩余/满充容量合并为单一开关(展示为「剩余 / 满充 mAh」整行格)。
                MetricSwitch(id: "capacity", title: String(localized: "metric.battery.capacity"), isDefault: true),
                // 深度诊断指标（默认关闭，按需在设置中勾选开启）
                MetricSwitch(id: "cell-qmax", title: String(localized: "metric.battery.cell-qmax"), isDefault: false),
                MetricSwitch(id: "cell-resistance", title: String(localized: "metric.battery.cell-resistance"), isDefault: false),
                MetricSwitch(id: "thermal-limit-seconds", title: String(localized: "metric.battery.thermal-limit-seconds"), isDefault: false),
                MetricSwitch(id: "time-at-high-soc", title: String(localized: "metric.battery.time-at-high-soc"), isDefault: false)
            ])
            return metrics
        case .fan:
            // 风扇行无子指标开关,展开区直接显示所有风扇(由 FanList 渲染)。
            return []
        case .bluetooth:
            // 蓝牙行无子指标开关,展开区直接显示已连接设备列表(由 BluetoothDeviceList 渲染)。
            return []
        }
    }
}

struct MetricSwitch: Identifiable, Hashable {
    let id: String
    let title: String
    let isDefault: Bool
    /// 设置页监测项目行的悬浮提示（如「部分机型尚不可用」）；nil 不渲染角标。
    var tip: String? = nil
}

/// 面板来源类型,用于引用计数式可见性判定。
enum PanelKind: Hashable {
    case menuBar
    case pinned
}

struct MonitorMetric: Identifiable, Equatable {
    let name: String
    let value: String
    var numericValue: Double?
    /// 值的单位后缀(如 "%"、"°C"、" W"):当 value 以它结尾时,明细网格把数值与
    /// 单位拆开渲染(数值主角化、单位弱化)。value 本身保持完整字符串,
    /// 复制/其他展示面语义不变;不设置时回退整串渲染。
    var unit: String? = nil

    var id: String { name }
}

/// 风扇运行状态。基于 RPM 与 min/max 范围判断,用于告警门控与面板着色。
/// 判断规则见 `FanInfo.status`。
enum FanStatus: Equatable, Comparable {
    /// 正常:RPM > 0 且未接近最大值(< 85% maxRPM)。
    case normal
    /// 警告:RPM 接近最大值(>= 85% maxRPM),散热压力高。
    case warning
    /// 故障:RPM = 0(停转)或 RPM > maxRPM(传感器读数异常)。
    case fault
    /// 未知:缺少 maxRPM 数据,无法判断。
    case unknown

    /// 状态严重度排序,用于取多风扇中最差状态。unknown 排在 normal 之下(无法判断 ≠ 正常)。
    var rank: Int {
        switch self {
        case .unknown: return 0
        case .normal: return 1
        case .warning: return 2
        case .fault: return 3
        }
    }

    /// 映射到全局 MonitorSeverity,复用面板已有的着色/标题体系。
    var severity: MonitorSeverity {
        switch self {
        case .normal, .unknown: return .calm
        case .warning: return .warning
        case .fault: return .critical
        }
    }

    var title: String {
        switch self {
        case .normal: String(localized: "fan.status.normal")
        case .warning: String(localized: "fan.status.warning")
        case .fault: String(localized: "fan.status.fault")
        case .unknown: String(localized: "fan.status.unknown")
        }
    }

    static func < (lhs: FanStatus, rhs: FanStatus) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// 单个风扇读数。由 FanSampler 从 SMC F0Ac/F0Mn/F0Mx 等键读出。
/// 面板展开区按此数组渲染多风扇列表;菜单栏只取 max(currentRPM)。
struct FanInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let currentRPM: Int
    let minRPM: Int
    let maxRPM: Int

    /// 根据当前 RPM 与 min/max 范围判断风扇运行状态。
    /// - RPM = 0 → fault(停转;有风扇的 Mac 在唤醒时 RPM 至少 ~1000)
    /// - RPM > maxRPM → fault(传感器读数异常)
    /// - RPM >= 85% maxRPM → warning(接近满载,散热压力高)
    /// - maxRPM <= 0 → unknown(SMC 未提供上限,无法判断)
    /// - 其余 → normal
    var status: FanStatus {
        if maxRPM <= 0 { return .unknown }
        if currentRPM == 0 { return .fault }
        if currentRPM > maxRPM { return .fault }
        if Double(currentRPM) >= Double(maxRPM) * 0.85 { return .warning }
        return .normal
    }

    /// 取多个风扇中最差的状态(用于整体风扇系统健康度)。
    static func overallStatus(of fans: [FanInfo]) -> FanStatus {
        guard let worst = fans.map(\.status).max() else { return .unknown }
        return worst
    }
}

/// 单个逻辑 CPU 的瞬时负载,供展开区逐核环形图渲染。
struct CPUCoreLoad: Identifiable, Equatable {
    let index: Int
    /// 0-100 占用百分比。
    let usage: Double
    /// true=性能核(P),false=能效核(E)。
    let isPerformance: Bool

    var id: Int { index }
}

/// CPU 逐核负载与 P/E 分组占用(仅 CPU 模块有值):逐核环形图 +
/// 分组占用两行展示的数据源。分组占用与 core-split 指标同口径
/// (tick 差值聚合),独立存放供展开区直接渲染。
struct CPUCoreDetail: Equatable {
    let cores: [CPUCoreLoad]
    let performanceUsage: Double
    let efficiencyUsage: Double?
}

struct MonitorModule: Identifiable, Equatable {
    let kind: MonitorKind
    var context: String? = nil
    var value: Double
    var summary: String
    var metrics: [MonitorMetric]
    var samples: [Double]
    var pressure: MemoryPressureLevel? = nil
    /// 连续内存压力百分比(0-100,口径同活动监视器压力图),仅内存模块有值。
    var pressureValue: Double? = nil
    /// 压力百分比历史序列,与 samples 同法滚动积累,供压力模式下的迷你曲线使用。
    var pressureSamples: [Double] = []
    /// 多风扇读数(仅风扇模块有值)。面板展开区按此数组渲染所有风扇;
    /// 菜单栏只取 max(currentRPM)。独立于 metrics 字段,避免冲撞统一采样契约。
    var fans: [FanInfo]? = nil
    /// 已连接蓝牙设备(仅蓝牙模块有值)。面板展开区按此数组渲染设备电量列表;
    /// 独立于 metrics 字段,避免冲撞统一采样契约。
    var bluetoothDevices: [BluetoothDeviceInfo]? = nil
    /// 逐核负载与 P/E 分组占用(仅 CPU 模块且拓扑可识别时有值)。
    /// 面板展开区据此渲染逐核环形图,独立于 metrics 字段。
    var cpuCoreDetail: CPUCoreDetail? = nil
    /// 分应用能耗排名(仅 Direct 版且能读到同用户进程时有值)。
    /// 电源展开区的「排名」分页按此渲染前 5 名列表,独立于 metrics 字段。
    var processEnergy: ProcessEnergyBreakdown? = nil
    /// 采样失败/未产出时的占位模块标记:数值无真实数据源,
    /// 统计入库据此过滤,避免把兜底值当作真实读数写入历史。
    var isPlaceholder: Bool = false

    var id: MonitorKind { kind }

    var severity: MonitorSeverity {
        switch kind {
        case .cpu, .gpu, .memory, .storage:
            if value >= MonitorConstants.criticalThreshold { return .critical }
            if value >= MonitorConstants.warningThreshold { return .warning }
            return .calm
        case .network:
            if value >= MonitorConstants.networkWarningThreshold { return .warning }
            return .calm
        case .battery:
            // 缺失帧(isPlaceholder)不参与阈值判定:value 沿用上一帧,不得据此报红。
            if isPlaceholder { return .calm }
            if metrics.first(where: { $0.name == MonitorMetricKey.type })?.value == MonitorMetricKey.acPower {
                return .calm
            }
            if value <= MonitorConstants.batteryCriticalThreshold { return .critical }
            if value <= MonitorConstants.batteryWarningThreshold { return .warning }
            return .calm
        case .fan:
            // 风扇无严重度概念(没有"过载"阈值);永远 calm,避免误报警。
            return .calm
        case .bluetooth:
            // 取上报电量设备中的最低值着色(阈值复用电池口径);全部未上报
            // 电量时 value=0 但无低电语义,判 calm 不误报。
            let levels = (bluetoothDevices ?? []).compactMap(\.batteryLevel)
            guard let lowest = levels.min() else { return .calm }
            if Double(lowest) <= MonitorConstants.batteryCriticalThreshold { return .critical }
            if Double(lowest) <= MonitorConstants.batteryWarningThreshold { return .warning }
            return .calm
        }
    }

    nonisolated static func placeholder(kind: MonitorKind) -> MonitorModule {
        MonitorModule(
            kind: kind,
            context: nil,
            value: 0,
            summary: "--",
            metrics: [
                MonitorMetric(name: "current", value: "--"),
                MonitorMetric(name: "average", value: "--"),
                MonitorMetric(name: "peak", value: "--")
            ],
            samples: Array(repeating: 0, count: 28),
            isPlaceholder: true
        )
    }
}

/// 采样指标 name 的跨文件契约键。采样器产出与消费方(severity 判定等)共享,
/// 任一端改名编译器即报错,避免裸字符串断约后的静默降级(如电池交流供电判成 critical)。
enum MonitorMetricKey {
    static let type = "type"
    static let acPower = "ac-power"
    /// 电池模块 type 的缺失态取值:IOPS 接口不可信,读数不参与 UI/统计消费。
    static let batteryUnavailable = "battery-unavailable"
}

final class MonitorStore: ObservableObject {
    let settings: MonitorSettings

    @Published private(set) var modules: [MonitorModule]
    @Published var topMemoryProcesses: [TopMemoryProcess] = []
    @Published var topCPUProcesses: [TopCPUProcess] = []
    @Published var topGPUProcesses: [TopGPUProcess] = []
    @Published var topDiskProcesses: [TopDiskProcess] = []
    @Published var topNetworkProcesses: [TopNetworkProcess] = []
    var selectedKind: MonitorKind = .cpu

    /// 菜单栏负载环的 30fps 平滑动画状态,独立发布(而非 MonitorStore 自身的
    /// @Published),避免 MonitorPanelView 等只用 `@ObservedObject` 订阅整个 store、
    /// 却从不读取该值的视图,在负载爬升/回落期间被拖着以 30fps 重算整棵视图树。
    let loadAnimator = MenuBarLoadAnimator()

    /// 展开动画的单一进度驱动器。独立 ObservableObject(与 loadAnimator 同思路):
    /// 仅动画的 ~0.15s 内逐显示帧发布相位,平时不发布;相位由各 CollapsibleDetail
    /// 按 key 自读,宿主行与面板其余部分不受逐帧重算拖累。每个面板实例持有各自的
    /// 驱动器(菜单栏面板与钉住面板并存时展开态互不牵动)。
    /// 面板是否可见,用于按需启停进程采样。
    @Published private(set) var isPanelVisible = false

    /// 历史统计记录器:把每秒采样帧聚合成分钟行落库(见 StatisticsRecorder)。
    /// 设置页「数据统计」与网页报表共用其数据。
    let statisticsRecorder = StatisticsRecorder()

    /// 可见面板来源集合。任一来源可见时 isPanelVisible 为真,仅当集合为空时为假。
    private var visiblePanelKinds: Set<PanelKind> = []

    /// 展开/收起动画截止时刻;窗口期内的采样结果推迟应用(见 applySamplingResult)。
    /// 由 `beginExpansionAnimation` 在每次展开/收起起点置位。
    private var expansionAnimationDeadline = Date.distantPast

    private var allModules: [MonitorModule]
    private let refreshSchedule = MonitorRefreshSchedule()
    private var timerCancellable: AnyCancellable?
    private var procSampleTimer: AnyCancellable?
    /// 电源状态(交流/电池、充电与否)变化通知源。插拔电源时系统即时回调,
    /// 立刻重采电池模块,让菜单栏图标(充电闪电)与充电功率无需等下一个 2s 采样周期。
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private let sampler = SystemMonitorSampler()
    private let samplingQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.sampling", qos: .utility)
    private let procSampleQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.proc-sample", qos: .utility)
    /// nettop 单次实测数十~数百毫秒,单独一条串行队列,避免阻塞磁盘/GPU 等
    /// 毫秒级快照的出数。无锁前提:队列上的每个游标快照只被这一条队列读写。
    private let nettopQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.nettop-sample", qos: .utility)
    private var cancellables: Set<AnyCancellable> = []
    private var isSampling = false
    private var pendingSampleKinds: Set<MonitorKind> = []
    /// 风扇采样器(独立于 SystemMonitorSampler,因为它读 SMC 而非 Mach,
    /// 且输出是「多风扇列表」而非「单模块值」)。
    private let fanSampler = FanSampler()
    /// 当前所有风扇读数。fans 为空 = 该机无风扇 / 读取失败 / 面板未启动采样。
    /// 由 fanSampler.$fans Combine sink 同步更新。
    @Published private(set) var fans: [FanInfo] = []
    /// 风扇系统整体状态(由 FanSampler 发布,告警服务与面板着色订阅)。
    @Published private(set) var fanStatus: FanStatus = .unknown
    /// 目标机型是否有风扇(由 FNum 启动时一次性检测决定)。
    /// UI 用此值决定:面板是否插入风扇行、设置选单是否显示风扇选项。
    var fanAvailable: Bool { fanSampler.available }
    /// 蓝牙采样器(独立于 SystemMonitorSampler:数据源是 system_profiler 探针,
    /// 输出是「设备列表」而非「单模块值」)。
    private let bluetoothSampler = BluetoothBatterySampler()
    /// 当前已连接蓝牙设备。由 bluetoothSampler.$devices Combine sink 同步更新。
    @Published private(set) var bluetoothDevices: [BluetoothDeviceInfo] = []
    /// 蓝牙控制器三态。由 bluetoothSampler.$controllerOn sink 同步更新;
    /// unknown(数据源尚未确认)时面板保留蓝牙占位行,只有 off 才移除行。
    @Published private(set) var bluetoothControllerState: BluetoothControllerState = .unknown

    init() {
        let settings = MonitorSettings()
        let initialModules = MonitorKind.allCases.map(MonitorModule.placeholder)
        self.settings = settings
        allModules = initialModules
        modules = initialModules.filter { settings.isVisible($0.kind) }
        advance(kinds: MonitorKind.samplerBackedCases)
        refreshSchedule.markRefreshed(MonitorKind.samplerBackedCases, at: Date())
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.modules = self.visibleModules(from: self.allModules)
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        timerCancellable = Timer.publish(every: refreshSchedule.tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advance()
            }

        startPowerSourceMonitoring()

        // 进程采样定时器自 init 常驻:TOP 列表在打开面板/展开行之前即绑好,
        // 展开即刻落真实数据,无需等基线建立。统一为单个定时器串行驱动
        // 各类目采样,避免多个独立定时器导致的密集触发;采样在后台串行队列,
        // 沙盒版全程进程内读,直连版每周期另 spawn 一轮 ps/nettop。
        startProcSampleTimer()
        refreshProcesses(for: enabledProcessKinds(), allowClear: false)

        settings.$memoryShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$cpuShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$diskShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$networkShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        // 风扇采样:仅在面板可见时启用,避免无谓的 SMC 读取。
        fanSampler.$fans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newFans in
                guard let self else { return }
                settleAfterExpansion { self.fans = newFans }
            }
            .store(in: &cancellables)

        // 风扇状态订阅:同步到 store.fanStatus,供面板着色与告警服务使用。
        fanSampler.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self else { return }
                settleAfterExpansion { self.fanStatus = newStatus }
            }
            .store(in: &cancellables)

        // 风扇后台采样:启动即常驻,不随面板显隐启停。
        // 原因:告警服务需在面板关闭时也能检测风扇异常(停转/过载)并通知用户。
        // SMC 读取(FNum/F0Ac)极轻量(单次 IOConnectCall),2s 周期对功耗无感。
        fanSampler.start()
        FanAlertService.shared.attach(to: fanSampler)

        // 蓝牙设备电量:独立采样器(IOBluetooth 连断事件驱动 + profiler 10s 兜底
        // 轮询,高成本源后台执行),结果经 Combine 回主线程。
        bluetoothSampler.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDevices in
                guard let self else { return }
                settleAfterExpansion { self.bluetoothDevices = newDevices }
            }
            .store(in: &cancellables)

        bluetoothSampler.$controllerOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                settleAfterExpansion { self.bluetoothControllerState = state }
            }
            .store(in: &cancellables)

        // 蓝牙采样随模块可见性启停:行被用户隐藏后,10s profiler 探针与
        // BLE 常驻连接只有成本;蓝牙无风扇那样的后台告警刚需,不适用「启动
        // 即常驻」。重新勾选时 start() 幂等重建全部管线。
        settings.$visibleKinds
            .map { $0.contains(.bluetooth) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.bluetoothSampler.start()
                    if self.visiblePanelKinds.isEmpty == false {
                        self.bluetoothSampler.activateBLE()
                    }
                } else {
                    self.bluetoothSampler.stop()
                }
            }
            .store(in: &cancellables)

        if settings.isVisible(.bluetooth) {
            bluetoothSampler.start()
        }

        startStatisticsProcessSampling()
    }

    // MARK: - 统计进程采样

    /// 统计专用 TOP 应用采样定时器(面板无关常驻):60s 一次、始终包含系统进程,
    /// 结果交 StatisticsRecorder 聚合落 SwiftData。与面板进程采样共用同一条串行队列;
    /// 增量类目(磁盘/网络/GPU 与沙盒 CPU)各走独立游标,保证 60s 统计窗口不被面板 2s 采样截断。
    /// 随「数据统计」开关启停:关闭时不做进程采样,也不积累分钟累加器。
    private var statsProcTimer: AnyCancellable?
    private let statsDiskCursor = DiskSnapshotCursor()
    private let statsGPUCursor = GPUDeltaCursor()
    #if DIRECT_DISTRIBUTION
    private let statsNetworkCursor = NetworkDeltaCursor()
    #else
    private let statsCPUCursor = CPUDeltaCursor()
    #endif

    private var statisticsSamplingActive = false

    private func startStatisticsProcessSampling() {
        guard statisticsRecorder.processStore != nil else { return }
        // 以持久化值对齐初始状态:关闭态启动时补一次 suspend,让 recorder 的
        // 默认 recordingActive=true 落回关闭;订阅用 dropFirst 只处理切换。
        let enabled = settings.statisticsEnabled
        statisticsSamplingActive = enabled
        settings.$statisticsEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setStatisticsSampling(enabled)
            }
            .store(in: &cancellables)
        if enabled {
            installStatisticsProcessTimer()
        } else {
            statisticsRecorder.suspend()
        }
    }

    /// 开关切换:开启时重装定时器并补一次水位维护(关闭期间积累的水位由
    /// maintain 全量重扫自然补齐);关闭时撤销定时器并丢弃进行中的分钟累加,
    /// 让「停止记录」立刻干净生效,不再写入半个未关闭的分钟。
    private func setStatisticsSampling(_ enabled: Bool) {
        guard statisticsRecorder.processStore != nil else { return }
        if enabled {
            guard !statisticsSamplingActive else { return }
            statisticsSamplingActive = true
            statisticsRecorder.resume()
            installStatisticsProcessTimer()
        } else {
            statisticsSamplingActive = false
            statsProcTimer = nil
            statisticsRecorder.suspend()
        }
    }

    private func installStatisticsProcessTimer() {
        statsProcTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sampleProcessesForStatistics()
            }
    }

    private func sampleProcessesForStatistics() {
        let recorder = statisticsRecorder
        let gpuCursor = statsGPUCursor
        #if DIRECT_DISTRIBUTION
        let diskCursor = statsDiskCursor
        let networkCursor = statsNetworkCursor
        #else
        let cpuCursor = statsCPUCursor
        #endif
        let sampleFast: () -> Void = {
            #if DIRECT_DISTRIBUTION
            // 直连版 CPU 来自 ps,无基线,与面板不存在共享问题。
            let cpu = enrichCPU(sampleTopCPUProcesses(limit: 12, includeSystemProcesses: true))
            #else
            let cpu = enrichCPU(cpuCursor.sample(limit: 12, includeSystemProcesses: true))
            #endif
            let memory = enrich(sampleTopMemoryProcesses(includeSystemProcesses: true))
            let gpu = enrichGPU(gpuCursor.sample(limit: 12, includeSystemProcesses: true))
            #if DIRECT_DISTRIBUTION
            let disk = enrichDisk(diskCursor.sampleTopDiskProcesses(includeSystemProcesses: true))
            #else
            let disk: [TopDiskProcess] = []
            #endif
            DispatchQueue.main.async {
                recorder.recordProcesses(cpu: cpu, memory: memory, gpu: gpu, network: [], disk: disk, at: Date())
            }
        }
        procSampleQueue.async(execute: sampleFast)
        #if DIRECT_DISTRIBUTION
        // nettop 独占 nettopQueue,单次实测数十~数百毫秒;速率为窗口均值,×60s 近似为分钟字节量
        let sampleNetwork: () -> Void = {
            let network = enrichNetwork(networkCursor.sample(limit: 5, includeSystemProcesses: true))
            DispatchQueue.main.async {
                recorder.recordProcesses(cpu: [], memory: [], gpu: [], network: network, disk: [], at: Date())
            }
        }
        nettopQueue.async(execute: sampleNetwork)
        #endif
    }

    /// 面板出现时调用（菜单栏面板便捷封装）。
    func panelDidAppear() {
        panelDidAppear(.menuBar)
    }

    /// 面板消失时调用（菜单栏面板便捷封装）。
    func panelDidDisappear() {
        panelDidDisappear(.menuBar)
    }

    /// 面板出现时调用:记录来源。进程采样自 init 常驻,不随面板可见性启停。
    func panelDidAppear(_ kind: PanelKind) {
        let wasEmpty = visiblePanelKinds.isEmpty
        visiblePanelKinds.insert(kind)
        // CoreBluetooth 的系统授权弹窗推迟到面板首次可见时触发,不打断应用
        // 启动;已授权则幂等补挂监视(覆盖运行期授权变化)。
        bluetoothSampler.activateBLE()
        if wasEmpty {
            loadAnimator.setPanelVisible(true)
            isPanelVisible = true
        }
    }

    /// 面板消失时调用:移除来源。TOP 列表与采样常驻,隐藏期不清空、不停表,
    /// 下次打开/展开即刻有数据。
    func panelDidDisappear(_ kind: PanelKind) {
        visiblePanelKinds.remove(kind)
        if visiblePanelKinds.isEmpty {
            isPanelVisible = false
            loadAnimator.setPanelVisible(false)
        }
    }

    /// 由 SwiftUI 侧在每次展开/收起起点调用:置位动画截止时刻。
    /// 窗口期内的采样结果推迟到动画结束后再刷 UI,避免 1-3s 节奏的模块刷新恰好
    /// 撞进 ~0.15s 展开动画、拖动整棵视图树重算造成掉帧。
    func beginExpansionAnimation() {
        expansionAnimationDeadline = Date().addingTimeInterval(MonitorConstants.panelExpansionSettleTime)
        // 动画窗口内同步停更负载环 30fps 相位,不与展开动画抢主线程。
        loadAnimator.suspend(until: expansionAnimationDeadline)
    }

    /// 是否处于展开/收起动画窗口期。功率流等 GPU 重型流光在窗口内停更,
    /// 让出动画期间的渲染余量(外接屏扩放负载时尤为关键)。
    var isExpansionAnimating: Bool {
        Date() < expansionAnimationDeadline
    }

    /// 把一个 @Published 应用动作推迟到展开/收起动画窗口结束再执行,窗口外直接执行。
    /// 窗口内刷新会拖着面板视图树在动画帧间重算,造成肉眼可见的顿挫;
    /// 推迟到弹簧收尾后再刷,主队列 FIFO 保证多次推迟的顺序不乱。
    /// (调试对照:HAGIMI_NODEFER_SAMPLING=1 时关闭推迟,用于帧探针 A/B 对比。)
    private func deferUntilExpansionSettles(_ action: @escaping () -> Void) {
        let deferDisabled = ProcessInfo.processInfo.environment["HAGIMI_NODEFER_SAMPLING"] != nil
        guard !deferDisabled, Date() < expansionAnimationDeadline else {
            action()
            return
        }
        let delay = expansionAnimationDeadline.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // 重检:连点期间 deadline 被后续 toggle 推后,原定时点可能仍落在新窗口内,
            // 此时再推迟一次而不是强行应用,避免 @Published 刷新撞弹簧动画帧。
            if Date() < self.expansionAnimationDeadline {
                let next = self.expansionAnimationDeadline.timeIntervalSinceNow
                DispatchQueue.main.asyncAfter(deadline: .now() + next) {
                    action()
                }
            } else {
                action()
            }
        }
    }

    /// 当前设置里已开启进程列表的类目集合。
    /// GPU 列表的数据源是 IORegistry 只读属性(AGX user client 的 AppUsage);
    /// CPU/内存列表走 sysctl + proc_pidinfo(TASKINFO),均被沙盒放行,
    /// 这三类双渠道均可采样;存储/网络依赖 proc_pid_rusage/nettop 等他进程
    /// 接口,沙盒下被拒,仅直连版启用。
    private func enabledProcessKinds() -> Set<MonitorKind> {
        var enabled = Set<MonitorKind>()
        if settings.showGPUProcesses { enabled.insert(.gpu) }
        if settings.showMemoryProcesses { enabled.insert(.memory) }
        if settings.showCPUProcesses { enabled.insert(.cpu) }
        #if DIRECT_DISTRIBUTION
        if settings.showDiskProcesses { enabled.insert(.storage) }
        if settings.showNetworkProcesses { enabled.insert(.network) }
        #endif
        return enabled
    }

    /// 计算实际需要采样的进程类目:展开集合与「设置里开启的进程列表」集合的交集。
    /// 纯函数,便于单测。
    static func activeProcessKinds(expanded: Set<MonitorKind>, enabled: Set<MonitorKind>) -> Set<MonitorKind> {
        expanded.intersection(enabled)
    }

    /// 启动进程采样定时器(2 秒间隔)。
    private func startProcSampleTimer() {
        guard procSampleTimer == nil else { return }
        procSampleTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAllProcesses()
            }
    }

    /// 刷新设置里开启的进程列表(不论是否展开)。由 2 秒定时器驱动。
    /// 定时周期拥有完整测量窗口,结果权威,允许用空结果清列表(真实空闲时列表
    /// 应诚实变空);init 首采一次性禁用清空(见调用处)。
    private func refreshAllProcesses() {
        refreshProcesses(for: enabledProcessKinds())
    }

    /// 对指定类目采样(仅限其中设置已开启的列表)。快速采样(磁盘/GPU/CPU/内存)
    /// 在 procSampleQueue、nettop 在 nettopQueue 各自串行执行(串行是各游标
    /// 快照无锁安全的前提),全部完成后回主线程更新 @Published 属性——命中
    /// 展开/收起动画窗口时推迟到弹簧收尾(见 deferUntilExpansionSettles)。
    /// allowClear=false 时空结果不覆盖已有列表(init 首采用)。
    private func refreshProcesses(
        for kinds: Set<MonitorKind>,
        allowClear: Bool = true
    ) {
        let enabled = enabledProcessKinds()

        let active = Self.activeProcessKinds(expanded: kinds, enabled: enabled)
        guard !active.isEmpty else { return }

        let memoryIncludeSystem = settings.memoryShowSystemProcesses
        let cpuIncludeSystem = settings.cpuShowSystemProcesses
        let gpuIncludeSystem = settings.gpuShowSystemProcesses
        let diskIncludeSystem = settings.diskShowSystemProcesses
        let networkIncludeSystem = settings.networkShowSystemProcesses

        let group = DispatchGroup()
        var memoryProcesses: [TopMemoryProcess]?
        var cpuProcesses: [TopCPUProcess]?
        var gpuProcesses: [TopGPUProcess]?
        var diskProcesses: [TopDiskProcess]?
        var networkProcesses: [TopNetworkProcess]?

        // 采样设置里已开启的列表(不论是否展开)。注意:增量类目(磁盘/网络/GPU
        // 与沙盒 CPU)的 TOP 采样各自维护差分快照计算增量,快照按消费方分离为游标、每消费方各持
        // 一个实例(面板 panel*Cursor / 统计 stats*Cursor,磁盘为 DiskSnapshotCursor;
        // 沙盒 CPU 为 CPUDeltaCursor;网络/GPU 为 NetworkDeltaCursor/GPUDeltaCursor),
        // 其线程安全依赖「每份快照只被固定一条串行队列读写」——CPU/磁盘/GPU 在
        // procSampleQueue、网络在 nettopQueue,并发化任一条会引入难复现的数据竞争。
        if active.contains(.memory) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopMemoryProcesses(includeSystemProcesses: memoryIncludeSystem)
                // enrich 使用 NSRunningApplication(pid:) 初始化,只读属性,后台线程安全。
                memoryProcesses = enrich(raw)
                group.leave()
            }
        }

        if active.contains(.cpu) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopCPUProcesses(includeSystemProcesses: cpuIncludeSystem)
                cpuProcesses = enrichCPU(raw)
                group.leave()
            }
        }

        if active.contains(.gpu) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopGPUProcesses(includeSystemProcesses: gpuIncludeSystem)
                gpuProcesses = enrichGPU(raw)
                group.leave()
            }
        }

        if active.contains(.storage) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopDiskProcesses(includeSystemProcesses: diskIncludeSystem)
                diskProcesses = enrichDisk(raw)
                group.leave()
            }
        }

        if active.contains(.network) {
            group.enter()
            nettopQueue.async {
                let raw = sampleTopNetworkProcesses(includeSystemProcesses: networkIncludeSystem)
                networkProcesses = enrichNetwork(raw)
                group.leave()
            }
        }

        // 全部采样完成后,在主线程更新 @Published 属性。命中展开/收起动画窗口时
        // 推迟到弹簧收尾(与模块采样同规则),避免整表替换撞动画帧、拖视图树重算。
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.deferUntilExpansionSettles {
                // 采样常驻:结果不论面板可见与否都发布,隐藏期列表也保持
                // 鲜活,展开即刻渲染最近一期常驻结果。
                func publish<T>(_ kind: MonitorKind, _ result: [T]?, assign: ([T]) -> Void) {
                    guard let result else { return }
                    if !result.isEmpty || allowClear { assign(result) }
                }
                publish(.memory, memoryProcesses) { self.topMemoryProcesses = $0 }
                publish(.cpu, cpuProcesses) { self.topCPUProcesses = $0 }
                publish(.gpu, gpuProcesses) { self.topGPUProcesses = $0 }
                publish(.storage, diskProcesses) { self.topDiskProcesses = $0 }
                publish(.network, networkProcesses) { self.topNetworkProcesses = $0 }
            }
        }
    }

    /// 设置变化时立即重采一期;采样常驻,不受面板可见性限制。
    private func refreshAllProcessesIfNeeded() {
        refreshAllProcesses()
    }

    deinit {
        timerCancellable?.cancel()
        procSampleTimer?.cancel()
        statsProcTimer?.cancel()
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        cancellables.removeAll()
    }

    /// 注册电源状态变化通知:插拔适配器/充电状态翻转时立即重采电池。
    /// 回调在主运行循环触发(与采样定时器同线程),故可直接调 advance,无数据竞争。
    /// C 函数指针回调不能捕获上下文,通过 context 传入 self 的非持有指针。
    private func startPowerSourceMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<MonitorStore>.fromOpaque(ctx).takeUnretainedValue().powerSourceDidChange()
        }, context)?.takeRetainedValue() else {
            AppLogger.sampler.warning("Failed to create power source notification run loop source")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceRunLoopSource = source
    }

    /// 电源状态变化时立即重采电池,不影响其他模块的既定节奏。
    private func powerSourceDidChange() {
        advance(kinds: [.battery])
    }

    var selectedModule: MonitorModule {
        allModules.first { $0.kind == selectedKind }
            ?? allModules.first
            ?? MonitorModule.placeholder(kind: selectedKind)
    }

    var combinedComputeLoad: Double {
        let cpuValue = allModules.first { $0.kind == .cpu }?.value ?? 0
        let gpuValue = allModules.first { $0.kind == .gpu }?.value ?? 0
        let memoryPressure = allModules.first { $0.kind == .memory }?.pressure ?? .unknown
        return ComputeLoadModel.combined(
            cpuValue: cpuValue,
            gpuValue: gpuValue,
            memoryPressure: memoryPressure
        )
    }

    var haloRingLoadLevel: MenuBarComputeLoadLevel {
        ComputeLoadModel.loadLevel(for: combinedComputeLoad)
    }

    var menuBarMetricItems: [MenuBarMetricItem] {
        settings.menuBarMetricKinds.map { kind in
            MenuBarMetricItem(kind: kind, value: menuBarMetricValue(for: kind))
        }
    }

    func previewMenuBarMetricItems() -> [MenuBarMetricItem] {
        settings.menuBarMetricKinds.map { kind in
            MenuBarMetricItem(kind: kind, value: previewMenuBarMetricValue(for: kind))
        }
    }

    private func menuBarMetricValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.cpu))
        case .gpuUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.gpu))
        case .memoryUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.memory))
        case .memoryPressure:
            // 连续压力百分比,口径同面板压力曲线(活动监视器压力图)。
            return MenuBarMetricFormatter.fixedPercentage(allModules.first { $0.kind == .memory }?.pressureValue)
        case .batteryLevel:
            // IOPS 缺失帧显示 " --%"(与数值缺失的既有格式一致),不消费沿用值。
            guard let battery = allModules.first(where: { $0.kind == .battery }), !battery.isPlaceholder else {
                return MenuBarMetricFormatter.fixedPercentage(nil)
            }
            return MenuBarMetricFormatter.fixedPercentage(battery.value)
        case .networkDownload:
            return MenuBarMetricFormatter.throughput(metricValue("download", in: .network), direction: "↓")
        case .networkUpload:
            return MenuBarMetricFormatter.throughput(metricValue("upload", in: .network), direction: "↑")
        case .cpuTemperature:
            return MenuBarMetricFormatter.temperature(metricValue("temperature", in: .cpu))
        case .storageFree:
            return MenuBarMetricFormatter.capacity(metricValue("free", in: .storage))
        case .systemPower:
            return MenuBarMetricFormatter.power(metricValue("power", in: .battery))
        case .fanSpeed:
            // 取多风扇的 max RPM;fans 为空(无风扇 / 未采样)走 unavailable 占位。
            return MenuBarMetricFormatter.fanRPM(fans.map { $0.currentRPM }.max())
        // 分项功耗/总线带宽由采样串行队列推进并发布到模块指标，菜单栏只读
        // 已发布数值：不在主线程触发 IOReport 采样，也消除跨线程共享状态。
        case .gpuPower:
            #if DIRECT_DISTRIBUTION
            return MenuBarMetricFormatter.power(metricValue("gpu-power", in: .battery))
            #else
            return MenuBarMetricFormatter.unavailable
            #endif
        case .memoryBandwidth:
            #if DIRECT_DISTRIBUTION
            return MenuBarMetricFormatter.bandwidth(metricValue("memory-bandwidth", in: .memory))
            #else
            return MenuBarMetricFormatter.unavailable
            #endif
        case .displayRefreshRate:
            // 公开 CG API,沙盒可用,双渠道同源。
            return MenuBarMetricFormatter.refreshRate(DisplayTelemetryReader.readBuiltInRefreshRate())
        case .displayPower:
            #if DIRECT_DISTRIBUTION
            return MenuBarMetricFormatter.displayPower(metricValue("display-power", in: .battery))
            #else
            return MenuBarMetricFormatter.unavailable
            #endif
        }
    }

    private func previewMenuBarMetricValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage:
            "35%"
        case .gpuUsage:
            "34%"
        case .gpuPower:
            "  5W"
        case .memoryUsage:
            "61%"
        case .memoryPressure:
            "23%"
        case .memoryBandwidth:
            "9.4G"
        case .batteryLevel:
            "76%"
        case .networkDownload:
            "↓2.4M"
        case .networkUpload:
            "↑320K"
        case .cpuTemperature:
            " 88°"
        case .storageFree:
            "128G"
        case .displayRefreshRate:
            "120Hz"
        case .displayPower:
            " 1.5W"
        case .systemPower:
            " 12W"
        case .fanSpeed:
            "3200"
        }
    }

    private func moduleValue(_ kind: MonitorKind) -> Double? {
        allModules.first { $0.kind == kind }?.value
    }

    private func metricValue(_ name: String, in kind: MonitorKind) -> Double? {
        allModules.first { $0.kind == kind }?.metrics.first { $0.name == name }?.numericValue
    }

    private func advance() {
        let kinds = refreshSchedule.dueKinds(at: Date())
        guard !kinds.isEmpty else {
            return
        }
        advance(kinds: kinds)
    }

    private func advance(kinds: some Sequence<MonitorKind>) {
        let requestedKinds = Set(kinds)
        guard !requestedKinds.isEmpty else {
            return
        }

        if isSampling {
            pendingSampleKinds.formUnion(requestedKinds)
            return
        }

        isSampling = true
        runSampling(kinds: requestedKinds)
    }

    private func runSampling(kinds: Set<MonitorKind>) {
        let previousModules = allModules
        sampler.sampleAsync(kinds: kinds, previousModules: previousModules, on: samplingQueue) { [weak self] result in
            guard let self else { return }
            self.applySamplingResult(result)
        }
    }

    /// 动画窗口期内的 @Published 应用推迟:展开/收起弹簧动画的 ~0.5s 衰减期内,把非主采样的
    /// 独立采样器(风扇/蓝牙)刷新同样排空,给逐帧动画让出主线程余量——主采样已按
    /// 同一 deadline 推迟,这里补齐剩余会拖动面板子树重算的指标,外接屏扩放渲染
    /// 负载时余量越少越易掉帧。
    private func settleAfterExpansion(_ apply: @escaping () -> Void) {
        let deadline = expansionAnimationDeadline
        if Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow) { [weak self] in
                guard let self else { apply(); return }
                if Date() < self.expansionAnimationDeadline {
                    let next = self.expansionAnimationDeadline.timeIntervalSinceNow
                    DispatchQueue.main.asyncAfter(deadline: .now() + next, execute: apply)
                } else {
                    apply()
                }
            }
        } else {
            apply()
        }
    }

    private func applySamplingResult(_ result: Result<SystemMonitorSnapshot, SamplingError>) {
        switch result {
        case .success(let snapshot):
            // 展开/收起动画窗口期内推迟应用,与 TOP 列表发布同规则
            // (见 deferUntilExpansionSettles)。
            deferUntilExpansionSettles { [weak self] in
                self?.applySamplingSuccess(snapshot)
            }

        case .failure(let error):
            let message = "Sampling failed: \(error.description)"
            AppLogger.sampler.error("\(message, privacy: .public)")
            AppLogStore.shared.error(message, category: "sampler")
        }

        if pendingSampleKinds.isEmpty {
            isSampling = false
        } else {
            let kinds = pendingSampleKinds
            pendingSampleKinds.removeAll()
            runSampling(kinds: kinds)
        }
    }

    /// 应用一次成功采样的结果到发布属性。
    private func applySamplingSuccess(_ snapshot: SystemMonitorSnapshot) {
        // 采样值未变时跳过重新赋值:避免空转触发 @Published,拖动
        // MonitorPanelView 等 @ObservedObject 订阅方做无意义的重算。
        if allModules != snapshot.modules {
            allModules = snapshot.modules
        }
        // 注入风扇模块:仅在 fanAvailable 时插入,位置固定在 GPU 之后、内存之前。
        // FanSampler 独立于 SystemMonitorSampler 管线(读 SMC 而非 Mach),此处
        // 把它的输出合成成 MonitorModule.fan 填入 allModules。
        applyFanModule()
        // 注入蓝牙模块:蓝牙开启即插入(常驻),位置固定在电池之后。
        applyBluetoothModule()
        let newVisibleModules = visibleModules(from: allModules)
        if modules != newVisibleModules {
            modules = newVisibleModules
        }
        updateMenuBarTargetComputeLoad()
        if statisticsSamplingActive {
            statisticsRecorder.record(modules: allModules, fans: fans, at: Date())
        }
    }



    private func updateMenuBarTargetComputeLoad() {
        loadAnimator.updateTarget(combinedComputeLoad)
    }

    /// 把 FanSampler 的输出合成成 .fan MonitorModule,插入到 allModules:
    /// - fanAvailable == false:无模块可插入,直接返回(panel 不会显示风扇行)
    /// - fanAvailable == true:替换 allModules 中的 .fan 占位 / 新插入到 GPU 之后、内存之前
    /// 风扇 RPM 历史用 [Double] 装进 samples,供 sparkline 使用。
    private func applyFanModule() {
        // 先读取旧 fan 模块的 RPM 历史(必须在 removeAll 之前,否则丢失累计采样)。
        let previousSamples = allModules.first(where: { $0.kind == .fan })?.samples ?? []
        // 移除已存在的 .fan 占位 / 旧数据
        allModules.removeAll { $0.kind == .fan }
        guard fanAvailable else { return }

        let currentFans = fans
        let maxRPM = currentFans.map(\.currentRPM).max() ?? 0
        // 面板展示带 RPM 单位;菜单栏走 MenuBarMetricFormatter.fanRPM() 不受影响。
        let summary = maxRPM > 0 ? "\(maxRPM) RPM" : "—"
        // 累计 RPM 历史(滚动窗口与 sparklineMaxPoints 对齐)。
        let newSamples = Array((previousSamples + [Double(maxRPM)]).suffix(MonitorConstants.sparklineMaxPoints))

        var fanModule = MonitorModule(
            kind: .fan,
            value: Double(maxRPM),
            summary: summary,
            metrics: [],
            samples: newSamples
        )
        fanModule.fans = currentFans

        // 插入到 GPU 之后、内存之前(若 allModules 中无 GPU/内存则追加到末尾)
        if let gpuIdx = allModules.firstIndex(where: { $0.kind == .gpu }) {
            // 找 GPU 之后的第一个非 fan 项插入(避免重复)
            let insertIdx = allModules[(gpuIdx + 1)...].firstIndex(where: { $0.kind != .fan }) ?? allModules.endIndex
            allModules.insert(fanModule, at: min(insertIdx, allModules.endIndex))
        } else {
            allModules.append(fanModule)
        }
    }

    /// 把 BluetoothBatterySampler 的输出合成成 .bluetooth MonitorModule,插入到
    /// allModules 的电池之后(面板中落在电源行与显示器区之间):
    /// - 蓝牙确认关闭:不插入模块,面板行消失
    /// - 蓝牙开启即常驻(无连接设备时显示 0 台,与风扇「无硬件才隐藏」的
    ///   门控不同:蓝牙开关是瞬态,隐藏会让用户误以为功能消失)
    /// - 数据源尚未确认(unknown):保留占位行,与其他模块启动期占位一致;
    ///   「尚未确认」不是「已关闭」,按关闭处理会让行在启动竞态下消失又出现
    /// - summary = 设备数,value = 上报电量设备中的最低值(均未上报时为 0,
    ///   severity 已对无电量情形判 calm 不误报)
    private func applyBluetoothModule() {
        allModules.removeAll { $0.kind == .bluetooth }
        guard bluetoothControllerState != .off else { return }

        let isConfirmed = bluetoothControllerState == .on
        let lowestLevel = bluetoothDevices.compactMap(\.batteryLevel).min()

        var bluetoothModule = MonitorModule(
            kind: .bluetooth,
            value: isConfirmed ? Double(lowestLevel ?? 0) : 0,
            summary: isConfirmed
                ? String(localized: "bluetooth.summary.count \(bluetoothDevices.count)")
                : "--",
            metrics: [],
            samples: []
        )
        if isConfirmed {
            bluetoothModule.bluetoothDevices = bluetoothDevices
        }

        if let batteryIdx = allModules.firstIndex(where: { $0.kind == .battery }) {
            allModules.insert(bluetoothModule, at: batteryIdx + 1)
        } else {
            allModules.append(bluetoothModule)
        }
    }

    private func visibleModules(from modules: [MonitorModule]) -> [MonitorModule] {
        // 风扇模块仅 fanAvailable 时被 applyFanModule 插入;插入后与其余模块
        // 一致走 settings.visibleKinds 用户开关(设置页可隐藏风扇行)。
        modules.filter { settings.isVisible($0.kind) }
    }
}

/// 菜单栏负载环的 30fps 平滑动画状态。从 MonitorStore 拆出独立发布,详见
/// `MonitorStore.loadAnimator` 处的说明。
final class MenuBarLoadAnimator: ObservableObject {
    @Published private(set) var displayedComputeLoad = 0.0

    private var targetComputeLoad = 0.0
    private var smoothingTimerCancellable: AnyCancellable?
    /// 任一监控面板可见时，菜单栏环只随采样低频更新；避免 30fps 状态项
    /// 重绘持续触发透明毛玻璃窗口与桌面的屏幕合成。
    private var panelVisible = false
    /// 展开动画窗口截止时刻:窗口内暂停 30fps 推进,动画结束后恢复平滑。
    private var suspensionDeadline = Date.distantPast

    func updateTarget(_ target: Double) {
        guard ComputeLoadModel.shouldUpdateMenuBarTarget(
            currentTarget: targetComputeLoad,
            nextTarget: target
        ) else {
            return
        }
        targetComputeLoad = target
        if panelVisible {
            publishTargetImmediately()
            return
        }
        ensureSmoothingTimer()
    }

    /// 可见期保留准确读数，但把菜单栏动画从 30fps 降为采样驱动（通常 1fps）。
    /// 面板收起后恢复原平滑策略；若可见期已追上目标则不会额外启动计时器。
    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if visible {
            smoothingTimerCancellable?.cancel()
            smoothingTimerCancellable = nil
            publishTargetImmediately()
        } else if Self.quantizeLoad(targetComputeLoad) != displayedComputeLoad {
            ensureSmoothingTimer()
        }
    }

    /// 暂停平滑推进至指定时刻(用于展开动画窗口),动画结束后自然恢复。
    func suspend(until deadline: Date) {
        suspensionDeadline = deadline
    }

    private func advanceSmoothing() {
        guard Date() >= suspensionDeadline else { return }
        let next = ComputeLoadModel.smoothedDisplayValue(
            current: displayedComputeLoad,
            target: targetComputeLoad
        )
        let quantized = Self.quantizeLoad(next)
        if quantized != displayedComputeLoad {
            displayedComputeLoad = quantized
        }
        let quantizedTarget = Self.quantizeLoad(targetComputeLoad)
        if abs(displayedComputeLoad - quantizedTarget) <= MonitorConstants.menuBarLoadSmoothStopThreshold {
            if displayedComputeLoad != quantizedTarget {
                displayedComputeLoad = quantizedTarget
            }
            smoothingTimerCancellable?.cancel()
            smoothingTimerCancellable = nil
        }
    }

    private static func quantizeLoad(_ load: Double) -> Double {
        min(100.0, max(0.0, load)).rounded()
    }

    private func ensureSmoothingTimer() {
        guard !panelVisible, smoothingTimerCancellable == nil else { return }
        smoothingTimerCancellable = Timer.publish(every: MonitorConstants.menuBarLoadSmoothFrameInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceSmoothing()
            }
    }

    private func publishTargetImmediately() {
        let target = Self.quantizeLoad(targetComputeLoad)
        if displayedComputeLoad != target {
            displayedComputeLoad = target
        }
    }

    deinit {
        smoothingTimerCancellable?.cancel()
    }
}

enum ComputeLoadModel {
    static func combined(
        cpuValue: Double,
        gpuValue: Double,
        memoryPressure: MemoryPressureLevel = .normal,
        sharpness: Double = MonitorConstants.computeLoadSoftmaxSharpness
    ) -> Double {
        let cpu = min(100, max(0, cpuValue))
        let gpu = min(100, max(0, gpuValue))
        let memory = memoryPressureScore(memoryPressure)
        return softmaxAggregate([cpu, gpu, memory], sharpness: sharpness)
    }

    /// 归一化 LSE（softmax mean）：结果严格落在 [mean, max] 之间。
    /// sharpness(k)→0 趋近均值，→∞ 趋近最大值；体现「多个子系统同时吃紧 = 整体更糟」。
    /// 减去 max 做指数平移以避免溢出。
    static func softmaxAggregate(_ values: [Double], sharpness k: Double) -> Double {
        guard let maxValue = values.max(), !values.isEmpty else {
            return 0
        }
        guard k > 0 else {
            return values.reduce(0, +) / Double(values.count)
        }
        let expSum = values.reduce(0.0) { $0 + exp(k * ($1 - maxValue)) }
        return maxValue + log(expSum / Double(values.count)) / k
    }

    static func memoryPressureScore(_ pressure: MemoryPressureLevel) -> Double {
        switch pressure {
        case .normal:
            return 0
        case .warning:
            return 50
        case .critical:
            return 85
        case .unknown:
            return 0
        }
    }

    static func loadLevel(for load: Double) -> MenuBarComputeLoadLevel {
        // 阈值按 softmax 聚合(k=0.08)的值分布校准：单瓶颈天花板≈86，
        // 故 stressed 下探到 78 以让「单子系统近满/双高/内存critical」触红。
        switch load {
        case ..<25: return .idle
        case ..<50: return .working
        case ..<78: return .busy
        default: return .stressed
        }
    }

    static func smoothedDisplayValue(
        current: Double,
        target: Double,
        factor: Double = MonitorConstants.menuBarLoadSmoothFactor,
        minStep: Double = MonitorConstants.menuBarLoadSmoothMinStep
    ) -> Double {
        let clampedCurrent = min(100, max(0, current))
        let clampedTarget = min(100, max(0, target))
        let delta = clampedTarget - clampedCurrent
        let distance = abs(delta)

        if distance <= minStep {
            return clampedTarget
        }

        // ease-out: proportional step, fast start, slow finish.
        let step = max(minStep, distance * factor)
        return clampedCurrent + (delta > 0 ? step : -step)
    }

    static func shouldUpdateMenuBarTarget(
        currentTarget: Double,
        nextTarget: Double,
        threshold: Double = MonitorConstants.menuBarLoadChangeThreshold
    ) -> Bool {
        abs(min(100, max(0, nextTarget)) - min(100, max(0, currentTarget))) >= threshold
    }
}

final class MonitorRefreshSchedule {
    let tickInterval: TimeInterval

    private let intervals: [MonitorKind: TimeInterval]
    private var lastRefreshDates: [MonitorKind: Date] = [:]

    init(
        tickInterval: TimeInterval = 1,
        intervals: [MonitorKind: TimeInterval] = [
            .cpu: 1, .gpu: 2, .memory: 3,
            .storage: 10, .network: 1, .battery: 2
        ]
    ) {
        self.tickInterval = tickInterval
        self.intervals = intervals
    }

    func dueKinds(at date: Date) -> [MonitorKind] {
        // 只对采样管线类目排期:风扇/蓝牙由独立采样器驱动(见 samplerBackedCases)。
        let dueKinds = MonitorKind.samplerBackedCases.filter { kind in
            let interval = intervals[kind] ?? tickInterval
            guard let lastRefreshDate = lastRefreshDates[kind] else {
                return true
            }

            return date.timeIntervalSince(lastRefreshDate) >= interval
        }
        markRefreshed(dueKinds, at: date)
        return dueKinds
    }

    func markRefreshed(_ kinds: some Sequence<MonitorKind>, at date: Date) {
        for kind in kinds {
            lastRefreshDates[kind] = date
        }
    }
}
