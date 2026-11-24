import Foundation
import Testing
@testable import HagimiMonitorDirect

@Suite("报表P0口径与联动回归测试")
struct ReportOverhaulTests {

    private func makeRow(
        t: Int64,
        n: Int = 60,
        cpuAvg: Double? = nil,
        memPressure: Double? = nil,
        memWarnS: Double? = nil,
        cpuThermal: Double? = nil,
        thFairS: Double? = nil,
        coverS: Double? = 60
    ) -> StatisticsRow {
        var row = StatisticsRow(t: t, n: n)
        row.cpuAvg = cpuAvg
        row.memPressureAvg = memPressure
        row.memWarnS = memWarnS
        row.cpuThermalAvg = cpuThermal
        row.thFairS = thFairS
        row.coverS = coverS
        return row
    }

    @Test func thermalScaleZeroToThreeMapsConsistentlyAcrossAllConsumers() {
        #expect(StatisticsDisplayFormat.thermalLevelIndex(nil) == nil)
        #expect(StatisticsDisplayFormat.thermalLevelIndex(0.0) == 0)
        #expect(StatisticsDisplayFormat.thermalLevelIndex(1.0) == 1)
        #expect(StatisticsDisplayFormat.thermalLevelIndex(2.0) == 2)
        #expect(StatisticsDisplayFormat.thermalLevelIndex(3.0) == 3)

        // 1.0 是中度 Fair(1)，绝不能再误判为 紧急(3)
        let fairLabel = StatisticsDisplayFormat.thermalStateLabel(1.0)
        let criticalLabel = StatisticsDisplayFormat.thermalStateLabel(3.0)
        #expect(fairLabel != criticalLabel)
        #expect(ReportDataExporter.fmtThermal(1.0).hasSuffix("(1)"))
        #expect(ReportDataExporter.fmtThermal(2.0).hasSuffix("(2)"))
    }

    @Test func healthScoreNeverRoundsUpToHundredWhenPressureExists() {
        #expect(StatisticsHealthScore.displayScore(100.0, hasPressureEvents: false) == 100)
        #expect(StatisticsHealthScore.displayScore(99.94, hasPressureEvents: true) == 99)
        #expect(StatisticsHealthScore.displayScore(99.94, hasPressureEvents: false) == 99)
        #expect(StatisticsHealthScore.displayScore(100.0, hasPressureEvents: true) == 99)
        #expect(StatisticsHealthScore.displayScore(84.6, hasPressureEvents: false) == 84)
    }

    @Test func systemQualityNoticeIsNotMaskedByLeadingSampleEstimate() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let row = makeRow(t: Int64(now.timeIntervalSince1970) - 3600, n: 60, cpuAvg: 25)
        let appIdentity = ReportAppIdentity(appKey: "bundle:com.example.App", name: "App", iconPNG: nil, hasStableIdentity: true)
        let dailyRow = StatisticsProcessStore.DailyAppRow(
            day: StatisticsProcessStore.dayKey(now, calendar: .current),
            appKey: "bundle:com.example.App",
            name: "App",
            cpuAvg: 12, cpuSamples: 5,
            gpuAvg: 0, gpuSamples: 0,
            memAvgBytes: 200_000_000, memSamples: 5,
            netDownBytes: 0, netUpBytes: 0,
            diskReadBytes: 0, diskWriteBytes: 0,
            cpuTier1: 0, cpuTier2: 0, cpuTier3: 0, cpuPeak: 15,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0, gpuPeak: 0,
            memTier1: 0, memTier2: 0, memTier3: 0, memPeak: 200_000_000
        )
        let snapshot = ReportSnapshot(
            capturedAt: now,
            meta: ReportMeta(deviceName: "Mac", modelName: "Mac16,1", osVersion: "macOS 27", recordDays: 1, appVersion: "1.6", isDirect: true),
            minutes: [row],
            hours: [],
            days: [],
            process: ReportProcessData(identities: ["bundle:com.example.App": appIdentity], dailyRows: [dailyRow], batteryHistory: [], alerts: []),
            hardware: nil
        )
        let model = ReportDataAggregator.aggregate(snapshot: snapshot, range: .today, now: now)
        #expect(model.quality.contains(.partialCoverage))
        #expect(model.quality.contains(.leadingSampleEstimate))
        #expect(model.systemQualityNotice == String(localized: "stats.quality.partial"))
        #expect(model.qualityNotice == String(localized: "stats.quality.partial"))
    }

    @Test func fanlessDetectionRecognizesAppleSiliconMacBookAirModels() {
        #expect(!ReportEnvironment.hasPhysicalFans(model: "Mac14,2"))
        #expect(!ReportEnvironment.hasPhysicalFans(model: "Mac15,12"))
        #expect(!ReportEnvironment.hasPhysicalFans(model: "Mac16,12"))
        #expect(!ReportEnvironment.hasPhysicalFans(model: "MacBookAir10,1"))
    }

    @Test func systemAppFilterMatchesBundleAndExecutablePrefixes() {
        let safari = ReportAppRankingItem(
            id: "1", appKey: "bundle:com.apple.Safari", name: "Safari",
            value: 10, peakValue: 10, valueText: "10", tierHint: nil, iconData: nil
        )
        let daemon = ReportAppRankingItem(
            id: "2", appKey: "systemExecutable:/usr/libexec/foo", name: "foo",
            value: 5, peakValue: 5, valueText: "5", tierHint: nil, iconData: nil
        )
        let userApp = ReportAppRankingItem(
            id: "3", appKey: "bundle:com.example.Editor", name: "Editor",
            value: 8, peakValue: 8, valueText: "8", tierHint: nil, iconData: nil
        )
        #expect(safari.isSystemApp)
        #expect(daemon.isSystemApp)
        #expect(!userApp.isSystemApp)
    }

    @Test func csvExportUsesEmptyStringForMissingNumericValues() {
        let row = StatisticsRow(t: 1_750_000_000, n: 10)
        let csv = ReportDataExporter.generateCSV(rows: [row], bucketSeconds: 60)
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 2)
        #expect(!lines[1].contains("—"))
    }

    @Test @MainActor func rangeSwitchDuringLoadDoesNotStallHardwareLoading() async throws {
        let model = NativeReportViewModel(
            recorder: nil,
            snapshotLoader: { _, _ in
                Thread.sleep(forTimeInterval: 0.08)
                return StatisticsReportSnapshotInput(minutes: [], hours: [], days: [], process: nil, systemSleepIntervals: [])
            }
        )
        defer { model.teardown() }
        model.load()
        model.selectRange(.week)
        for _ in 0..<400 {
            if !model.isLoading && !model.isHardwareLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isLoading)
        #expect(!model.isHardwareLoading)
        #expect(model.rangeModel?.range == .week)
    }

    @Test func chartSeriesSmoothingPreservesSegmentsAndReducesDensePoints() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        var pts: [ReportTimeSeriesPoint] = []
        for i in 0..<500 {
            let seg = i < 250 ? 0 : 1
            let gap = seg == 1 ? 3600.0 : 0.0
            pts.append(ReportTimeSeriesPoint(
                id: "p-\(i)",
                date: base.addingTimeInterval(Double(i * 60) + gap),
                seriesID: "cpu",
                segmentID: seg,
                value: Double(i % 50)
            ))
        }
        let series = ReportChartSeries.from(pts, seriesID: "cpu")
        #expect(series.segments.count == 2)
        #expect(series.pointCount == 500)

        let smoothed = series.smoothed(targetMaxPoints: 100)
        #expect(smoothed.segments.count == 2)
        #expect(smoothed.pointCount < 200)
    }
}
