import Foundation
import Testing
@testable import HagimiMonitorDirect

/// U02 / 7.2：应用详情的逐日趋势按日汇总给出，不伪造更细的时间分辨，
/// 空值不补零，范围外日期不入序列。
struct AppTrendSeriesTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func row(dayOffset: Int, cpuAvg: Double, cpuSamples: Int = 60,
                     memBytes: Double = 1e9, memSamples: Int = 60,
                     netBytes: Double = 1e9) -> StatisticsProcessStore.DailyAppRow {
        let day = StatisticsProcessStore.dayKey(
            t0.addingTimeInterval(Double(dayOffset) * 86400), calendar: .current)
        return StatisticsProcessStore.DailyAppRow(
            day: day, appKey: "bundle:com.example.App", name: "App",
            cpuAvg: cpuAvg, cpuSamples: cpuSamples,
            gpuAvg: 40, gpuSamples: 60,
            memAvgBytes: memBytes, memSamples: memSamples,
            netDownBytes: netBytes, netUpBytes: 0,
            diskReadBytes: 0, diskWriteBytes: 0,
            cpuTier1: 0, cpuTier2: 0, cpuTier3: 0, cpuPeak: cpuAvg,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0, gpuPeak: 40,
            memTier1: 0, memTier2: 0, memTier3: 0, memPeak: memBytes
        )
    }

    @Test func seriesIsAscendingByDay() {
        let rows = [row(dayOffset: -2, cpuAvg: 30), row(dayOffset: 0, cpuAvg: 10), row(dayOffset: -1, cpuAvg: 20)]
        let series = ReportDataAggregator.appTrendSeries(
            dailyRows: rows, appKey: "bundle:com.example.App", metric: .cpu,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400)
        )
        #expect(series.count == 3)
        // 升序，便于直接画折线。
        #expect(series[0].value == 30)
        #expect(series[1].value == 20)
        #expect(series[2].value == 10)
        #expect(series[0].date < series[1].date)
        #expect(series[1].date < series[2].date)
    }

    @Test func otherAppsAndOutOfRangeDaysAreExcluded() {
        let inRange = row(dayOffset: -1, cpuAvg: 25)
        let outOfRange = row(dayOffset: -30, cpuAvg: 90)
        var otherApp = row(dayOffset: -1, cpuAvg: 50)
        otherApp = StatisticsProcessStore.DailyAppRow(
            day: otherApp.day, appKey: "bundle:com.example.Other", name: "Other",
            cpuAvg: 50, cpuSamples: 60, gpuAvg: 0, gpuSamples: 0,
            memAvgBytes: 0, memSamples: 0, netDownBytes: 0, netUpBytes: 0,
            diskReadBytes: 0, diskWriteBytes: 0,
            cpuTier1: 0, cpuTier2: 0, cpuTier3: 0, cpuPeak: 50,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0, gpuPeak: 0,
            memTier1: 0, memTier2: 0, memTier3: 0, memPeak: 0
        )
        let series = ReportDataAggregator.appTrendSeries(
            dailyRows: [inRange, outOfRange, otherApp],
            appKey: "bundle:com.example.App", metric: .cpu,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400)
        )
        #expect(series.count == 1)
        #expect(series.first?.value == 25)
    }

    @Test func zeroSamplesAreOmittedNotZeroFilled() {
        // 该日没有 CPU 样本：不能补成 0，否则趋势图会出现假的低点。
        let rows = [row(dayOffset: -1, cpuAvg: 0, cpuSamples: 0), row(dayOffset: -2, cpuAvg: 40)]
        let series = ReportDataAggregator.appTrendSeries(
            dailyRows: rows, appKey: "bundle:com.example.App", metric: .cpu,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400)
        )
        #expect(series.count == 1)
        #expect(series.first?.value == 40)
    }

    @Test func metricSelectionChangesTheValue() {
        let rows = [row(dayOffset: -1, cpuAvg: 30, memBytes: 5e9, netBytes: 2e9)]
        let memory = ReportDataAggregator.appTrendSeries(
            dailyRows: rows, appKey: "bundle:com.example.App", metric: .memory,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400))
        let network = ReportDataAggregator.appTrendSeries(
            dailyRows: rows, appKey: "bundle:com.example.App", metric: .network,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400))
        #expect(memory.first?.value == 5e9)
        #expect(network.first?.value == 2e9)
    }

    @Test func unknownAppYieldsEmptySeries() {
        let series = ReportDataAggregator.appTrendSeries(
            dailyRows: [row(dayOffset: -1, cpuAvg: 30)],
            appKey: "bundle:com.example.Missing", metric: .cpu,
            from: t0.addingTimeInterval(-3 * 86400), to: t0.addingTimeInterval(86400)
        )
        #expect(series.isEmpty)
    }
}
