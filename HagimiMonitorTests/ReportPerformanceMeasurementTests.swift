import Foundation
import Testing
@testable import HagimiMonitorDirect

/// P03：报表聚合的可复现测量。
///
/// 记录真实数据规模下的聚合耗时，供后续对比；这些数字是当前机器上的实测值，
/// 不作为其他硬件或未来版本的通用承诺。
struct ReportPerformanceMeasurementTests {
    private func makeSnapshot(appCount: Int, hours: Int) -> ReportSnapshot {
        let now = Date()
        var rows: [StatisticsRow] = []
        for index in 0..<hours {
            var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            func set(_ name: String, _ value: Double) {
                if let i = StatisticsRow.columns.firstIndex(where: { $0.name == name }) { values[i] = value }
            }
            let t = Int64(now.timeIntervalSince1970) - Int64(index) * 3600
            set("cpu_avg", 20 + Double(index % 30))
            set("cpu_max", 60 + Double(index % 35))
            set("gpu_avg", 25 + Double(index % 25))
            set("mem_pct_avg", 55 + Double(index % 20))
            set("mem_used_avg", 9 * 1_073_741_824)
            set("net_down", 1.2e9)
            set("net_up", 3.4e8)
            set("disk_read", 4.5e10)
            set("disk_write", 2.1e10)
            set("power_avg", 12)
            set("cover_s", 3600)
            rows.append(StatisticsRow(t: t, n: 3600, values: values))
        }

        // 应用日行：模拟较多应用的排行聚合规模。
        var dailyRows: [StatisticsProcessStore.DailyAppRow] = []
        var identities: [String: ReportAppIdentity] = [:]
        for appIndex in 0..<appCount {
            let key = "bundle:com.example.app\(appIndex)"
            identities[key] = ReportAppIdentity(appKey: key, name: "App \(appIndex)", iconPNG: nil, hasStableIdentity: true)
            let day = StatisticsProcessStore.dayKey(now, calendar: .current) - Int64(appIndex % 5)
            dailyRows.append(StatisticsProcessStore.DailyAppRow(
                day: day, appKey: key, name: "App \(appIndex)",
                cpuAvg: Double(appIndex % 80), cpuSamples: 60,
                gpuAvg: Double(appIndex % 60), gpuSamples: 60,
                memAvgBytes: Double(appIndex) * 1e8, memSamples: 60,
                netDownBytes: 1e9, netUpBytes: 1e8,
                diskReadBytes: 1e10, diskWriteBytes: 1e9,
                cpuTier1: 10, cpuTier2: 5, cpuTier3: 2, cpuPeak: 90,
                gpuTier1: 8, gpuTier2: 3, gpuTier3: 1, gpuPeak: 70,
                memTier1: 5, memTier2: 2, memTier3: 1, memPeak: 5e9
            ))
        }

        return ReportSnapshot(
            capturedAt: now,
            meta: ReportMeta(deviceName: "Test", modelName: "Mac16,1", osVersion: "macOS 27.0",
                             recordDays: 60, appVersion: "1.6.1", isDirect: true),
            minutes: [],
            hours: rows,
            days: [],
            process: ReportProcessData(
                identities: identities,
                dailyRows: dailyRows,
                batteryHistory: [],
                alerts: []
            ),
            hardware: nil,
            systemSleepIntervals: []
        )
    }

    private func measure(_ label: String, iterations: Int = 5, work: () -> Void) -> Double {
        // 先跑一次预热，避免把首次的惰性初始化算进结果。
        work()
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            work()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            best = min(best, elapsed)
        }
        record(label: label, milliseconds: best, iterations: iterations)
        return best
    }

    /// 测量结果写入仓库 tmp 目录：测试日志不便抓取标准输出，落到文件才可复现与对比。
    private func record(label: String, milliseconds: Double, iterations: Int) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tmp/statistics-metric", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("report-perf.txt")
        let line = "\(label)\t\(String(format: "%.1f", milliseconds)) ms\tbest of \(iterations)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }

    @Test func weekAggregationWithRealisticAppCount() {
        let snapshot = makeSnapshot(appCount: 150, hours: 24 * 7)
        let best = measure("week/150 apps") {
            _ = ReportDataAggregator.aggregate(snapshot: snapshot, range: .week)
        }
        // 阈值取一个宽松上界：只用来发现数量级退化，不当作 SLA。
        #expect(best < 500)
    }

    @Test func monthAggregationWithManyApps() {
        let snapshot = makeSnapshot(appCount: 400, hours: 24 * 30)
        let best = measure("month/400 apps") {
            _ = ReportDataAggregator.aggregate(snapshot: snapshot, range: .month)
        }
        #expect(best < 1500)
    }

    @Test func rankingFilterScalesWithManyApps() {
        let entries = (1...400).map { index in
            ReportAppRankingItem(
                id: "app\(index)", appKey: "bundle:com.example.app\(index)",
                name: "App \(index)", value: Double(401 - index), peakValue: Double(index),
                valueText: "\(index)", tierHint: nil, iconData: nil
            )
        }
        let best = measure("ranking filter/400 apps", iterations: 20) {
            _ = ReportAppRankingFilter.apply(to: entries, includeSystemApps: true, query: "app2", sortOrder: .value)
            _ = ReportAppRankingFilter.visible(entries: entries, showsAll: true, focusedAppKey: nil,
                                               expandedLimit: ReportAppRankingFilter.renderBatch)
        }
        #expect(best < 50)
    }
}
