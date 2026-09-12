import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 报表「运行状态」实时读数的取值规则。
///
/// 锁住三类取值纪律:主读数原样透传(不重复拼百分号)、速率指标取速率
/// (不取 summary 的接口名)、不列没有数据源的行。模块直接构造,不依赖采样器
/// 与硬件,专测 `HardwareLiveReadings.readings` 这一层。
@Suite("报表实时读数")
struct HardwareLiveReadingsTests {

    private func module(kind: MonitorKind, summary: String,
                        metrics: [(String, String)] = []) -> MonitorModule {
        MonitorModule(
            kind: kind,
            value: 0,
            summary: summary,
            metrics: metrics.map { MonitorMetric(name: $0.0, value: $0.1) },
            samples: []
        )
    }

    /// 主读数原样透传:采样器的 `percent()` 已带百分号,再拼一个就是 `12%%`。
    @Test func headlinePassesThroughWithoutAddingPercent() {
        let readings = HardwareLiveReadings.readings(for: module(kind: .cpu, summary: "12%"))
        #expect(readings?["hwLiveCpuUsage"] == "12%")
        #expect(readings?["hwLiveCpuUsage"]?.contains("%%") == false)
    }

    /// 桌面交流供电时电池 `summary` 是 `"ac-power"` 而不是百分数,不该被拼上百分号。
    @Test func headlineKeepsNonPercentSummaryIntact() {
        let readings = HardwareLiveReadings.readings(for: module(kind: .battery, summary: "ac-power"))
        #expect(readings?["hwLiveBatteryLevel"] == "ac-power")
    }

    /// 无数据占位不推那一行,让它留在网页上的「—」。
    @Test func placeholderSummaryIsDropped() {
        let readings = HardwareLiveReadings.readings(for: module(kind: .gpu, summary: "--"))
        #expect(readings?["hwLiveGpuUsage"] == nil)
    }

    /// 网络「下行」必须是速率:采样器的 `summary` 存的是接口名(「Wi-Fi」/「en0」)。
    @Test func networkDownloadComesFromRateMetricNotInterfaceName() {
        let readings = HardwareLiveReadings.readings(for: module(
            kind: .network, summary: "Wi-Fi",
            metrics: [("download", "1.2 MB/s"), ("upload", "240 KB/s")]))
        #expect(readings?["hwLiveDownload"] == "1.2 MB/s")
        #expect(readings?["hwLiveUpload"] == "240 KB/s")
    }

    /// GPU 不列温度行:GPUSampler 不产出 temperature 指标,列了也只会永远是「—」。
    @Test func gpuDoesNotAdvertiseADeadTemperatureRow() {
        let readings = HardwareLiveReadings.readings(for: module(
            kind: .gpu, summary: "43%",
            metrics: [("gpu-memory", "4.82 GB"), ("render", "8%"), ("tiler", "3%")]))
        // 键集合全量断言:GPU 没有温度数据源,列了也只会永远是「—」。
        #expect(Set((readings ?? [:]).keys) ==
            ["hwLiveGpuUsage", "hwLiveGpuMemory", "hwLiveRenderer", "hwLiveTiler"])
        #expect(readings?["hwLiveGpuMemory"] == "4.82 GB")
    }

    /// 枚举 id 要过本地化:中文界面不该露出 `fair`/`ac-power` 这类机器词。
    /// 只断言「不再是原 id」,不锁具体译文——测试环境的语言不固定。
    @Test func enumIdentifiersAreLocalized() {
        let cpu = HardwareLiveReadings.readings(for: module(
            kind: .cpu, summary: "12%", metrics: [("thermal-pressure", "fair")]))
        #expect(cpu?["hwLiveThermal"] != nil)
        #expect(cpu?["hwLiveThermal"] != "fair", "热压力应显示本地化文案,而不是采样器的 id")

        let battery = HardwareLiveReadings.readings(for: module(
            kind: .battery, summary: "96%", metrics: [("status", "on-battery")]))
        #expect(battery?["hwLiveBatteryState"] != "on-battery", "电池状态应显示本地化文案")
    }

    /// 占位模块整块不推:它上面的值不是真实读数。
    @Test func placeholderModuleProducesNothing() {
        #expect(HardwareLiveReadings.readings(for: .placeholder(kind: .cpu)) == nil)
    }
}
