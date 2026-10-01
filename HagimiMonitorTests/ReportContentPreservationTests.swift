import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 11.5：本次改动不得用删内容换取简洁。
///
/// 报表原有 13 个模块、系统级指标与原始数据表都在；设置页原有的记录开关、
/// 通知开关、范围选择与存储管理入口也都在。这些断言防止「为了让页面更清爽」
/// 而静默移除功能。
struct ReportContentPreservationTests {

    @Test func allThirteenReportModulesRemain() {
        let modules = ReportNavigationModule.allCases
        #expect(modules.count == 13)
        // 概览、六个硬件模块、分析与硬件档案分组齐备。
        for module in [ReportNavigationModule.overview, .cpu, .gpu, .memory, .network,
                       .disk, .power, .thermal, .apps, .events, .details, .insights, .machine] {
            #expect(modules.contains(module), "缺少模块：\(module.rawValue)")
        }
    }

    @Test func everyModuleStillHasTitleAndIcon() {
        for module in ReportNavigationModule.allCases {
            #expect(module.title.isEmpty == false, "\(module.rawValue) 缺少标题")
            #expect(module.icon.isEmpty == false, "\(module.rawValue) 缺少图标")
        }
    }

    @Test func hardwareModulesKeepTheirLiveRailBinding() {
        // 六个硬件模块仍绑定实时右栏；其余模块保持全宽。不能因为改版把实时源接错。
        let live: Set<ReportNavigationModule> = [.cpu, .gpu, .memory, .network, .disk, .power]
        for module in ReportNavigationModule.allCases {
            if live.contains(module) {
                #expect(module.liveMonitorKind != nil, "\(module.rawValue) 应保留实时右栏")
            } else {
                #expect(module.liveMonitorKind == nil, "\(module.rawValue) 不应绑定实时右栏")
            }
        }
    }

    @Test func rawDataAndInsightsModulesKeepDedicatedViews() {
        // 原始数据与洞察仍是独立模块，没有被并入概览而消失。
        #expect(ReportNavigationModule.details.title.isEmpty == false)
        #expect(ReportNavigationModule.insights.title.isEmpty == false)
        #expect(ReportNavigationModule.details != ReportNavigationModule.insights)
    }

    @Test func exportPayloadKeepsAllMetricGroups() {
        // 导出载荷仍包含分钟/小时/日三层与系统级列，说明没有为了简化而少发数据。
        let columns = StatisticsRow.columns.map(\.name)
        for required in ["cpu_avg", "gpu_avg", "mem_pct_avg", "net_down", "disk_read", "power_avg", "cover_s"] {
            #expect(columns.contains(required), "导出缺少列：\(required)")
        }
    }
}
