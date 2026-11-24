import AppKit
import Foundation

/// 报表运行环境与设备形态信息，统一供原生报表窗口、聚合器及导出模块使用。
nonisolated enum ReportEnvironment: Sendable {
    /// 设备形态分类（用于顶栏与摘要显示自适应系统图标）。
    enum FormFactor: Sendable, Equatable {
        case laptop
        case macMini
        case macStudio
        case iMac
        case macPro
        case desktop

        var symbolName: String {
            switch self {
            case .laptop: return "laptopcomputer"
            case .macMini: return "macmini"
            case .macStudio: return "macstudio"
            case .iMac: return "desktopcomputer"
            case .macPro: return "macpro.gen3"
            case .desktop: return "desktopcomputer"
            }
        }
    }

    /// 是否为非沙盒直连分发构建（Direct）。
    static var isDirect: Bool {
        #if DIRECT_DISTRIBUTION
        return true
        #else
        return false
        #endif
    }

    static func deviceName() -> String {
        if let name = Host.current().localizedName, !name.isEmpty {
            return name
        }
        let hostName = ProcessInfo.processInfo.hostName
        return hostName.split(separator: ".").first.map(String.init) ?? "Mac"
    }

    static func modelName() -> String {
        HardwareSysctl.string("hw.model") ?? "Mac"
    }

    /// 已知采用全被动无风扇散热的 Apple Silicon MacBook Air 型号表。
    private static let fanlessAppleSiliconAirModels: Set<String> = [
        "Mac14,2",  // M2 MacBook Air 13"
        "Mac14,15", // M2 MacBook Air 15"
        "Mac15,12", // M3 MacBook Air 13"
        "Mac15,13", // M3 MacBook Air 15"
        "Mac16,12", // M4 MacBook Air 13"
        "Mac16,13", // M4 MacBook Air 15"
    ]

    /// 判断机器是否具备物理主动风扇。
    /// 已知被动散热型号（MacBookAir / Apple Silicon Air 标识 / 硬件产品名）优先直接判定无风扇；
    /// 未知型号在直连环境下辅以 SMC 实测风扇计数校验。
    static func hasPhysicalFans(model: String, hardware: HardwareInventory? = nil) -> Bool {
        if model.localizedCaseInsensitiveContains("MacBookAir")
            || fanlessAppleSiliconAirModels.contains(model) {
            return false
        }
        if let hardware {
            let identityFacts = hardware.categories
                .first(where: { $0.id == "this-mac" })?
                .groups.first(where: { $0.id == "identity" })?
                .facts ?? []
            for fact in identityFacts {
                if let val = fact.value,
                   val.localizedCaseInsensitiveContains("MacBook Air") {
                    return false
                }
            }
        }
        #if DIRECT_DISTRIBUTION
        if let reader = SMCReader(), let count = reader.fanCount(), count > 0 {
            return true
        }
        #endif
        return true
    }

    /// 根据电池存在性与型号信息解析设备形态。
    static func formFactor(hasBattery: Bool, model: String, hardware: HardwareInventory? = nil) -> FormFactor {
        if hasBattery || model.localizedCaseInsensitiveContains("MacBook")
            || fanlessAppleSiliconAirModels.contains(model) {
            return .laptop
        }
        let lowerModel = model.lowercased()
        let marketingName = hardware?.categories
            .first(where: { $0.id == "this-mac" })?
            .groups.first(where: { $0.id == "identity" })?
            .facts.compactMap(\.value)
            .joined(separator: " ")
            .lowercased() ?? ""
        if lowerModel.contains("macmini") || marketingName.contains("mac mini") {
            return .macMini
        }
        if lowerModel.contains("macstudio") || marketingName.contains("mac studio") {
            return .macStudio
        }
        if lowerModel.contains("imac") || marketingName.contains("imac") {
            return .iMac
        }
        if lowerModel.contains("macpro") || marketingName.contains("mac pro") {
            return .macPro
        }
        return .desktop
    }
}

/// 原生报表打开时要定位的模块。视图模型将枚举 case 映射为初始选中的模块。
enum StatisticsReportAnchor: Sendable, Equatable {
    case memory
    case thermal
    case apps
}

/// 报表打开上下文：携带时间范围、目标模块、应用、指标及事件，确保跨页面跳转时状态对齐。
struct StatisticsReportContext: Sendable, Equatable {
    var range: StatisticsOverviewRange?
    var anchor: StatisticsReportAnchor?
    var appKey: String?
    var metric: ProcessAlertEpisode.Metric?
    var eventID: UUID?

    init(
        range: StatisticsOverviewRange? = nil,
        anchor: StatisticsReportAnchor? = nil,
        appKey: String? = nil,
        metric: ProcessAlertEpisode.Metric? = nil,
        eventID: UUID? = nil
    ) {
        self.range = range
        self.anchor = anchor
        self.appKey = appKey
        self.metric = metric
        self.eventID = eventID
    }
}

/// 报表打开流程：设置页按钮与 App 菜单共用。直接唤起原生报表窗口。
@MainActor
enum StatisticsReportFlow {
    static func open(recorder: StatisticsRecorder, anchor: StatisticsReportAnchor? = nil) {
        open(recorder: recorder, context: StatisticsReportContext(anchor: anchor))
    }

    static func open(recorder: StatisticsRecorder, context: StatisticsReportContext) {
        ReportWindowPresenter.open(recorder: recorder, context: context)
    }
}
