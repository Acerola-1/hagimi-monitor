import AppKit
import Foundation
import PDFKit
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
            },
            hardwareLoader: { _ in
                HardwareInventory(categories: [], rails: [:], capturedAt: Date())
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

        let smoothed = series.smoothed(targetMaxPoints: 100, referencePointCount: pts.count)
        #expect(smoothed.segments.count == 2)
        #expect(smoothed.pointCount < 200)
    }

    @Test func pressureHistoryKeepsTheRecentMinuteTailSeparateFromClosedHours() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let hourStart = Int64(now.timeIntervalSince1970) - 5400
        let minuteStart = Int64(now.timeIntervalSince1970) - 60

        var hour = makeRow(t: hourStart, n: 3600, memWarnS: 10, coverS: 3600)
        hour.validMemS = 3600
        var normal = makeRow(t: minuteStart, memWarnS: 0)
        normal.memNormalS = 60
        normal.validMemS = 60
        var active = normal
        active.memWarnS = 60
        active.memNormalS = 0
        var mixed = normal
        mixed.memWarnS = 10
        mixed.memNormalS = 50

        let recovered = ReportDataAggregator.deriveAlertEvents(
            rows: [hour], source: .hours, now: now, recentMinuteRows: [normal]
        )
        #expect(recovered.first?.state == .recovered)

        let noMinute = ReportDataAggregator.deriveAlertEvents(rows: [hour], source: .hours, now: now)
        #expect(noMinute.first?.state == .interrupted)

        let events = ReportDataAggregator.deriveAlertEvents(
            rows: [hour], source: .hours, now: now, recentMinuteRows: [active]
        )
        try #require(events.count == 2)
        #expect(events[0].start == Date(timeIntervalSince1970: TimeInterval(minuteStart)))
        #expect(events[0].state == .ongoing)
        #expect(events[1].state == .interrupted)

        hour.memWarnS = 0
        let recentOnly = ReportDataAggregator.deriveAlertEvents(
            rows: [hour], source: .hours, now: now, recentMinuteRows: [active]
        )
        #expect(recentOnly.count == 1)
        #expect(recentOnly.first?.state == .ongoing)

        let mixedOnly = ReportDataAggregator.deriveAlertEvents(rows: [mixed], source: .minutes, now: now)
        #expect(mixedOnly.first?.state == .interrupted)
        let mixedTail = ReportDataAggregator.deriveAlertEvents(
            rows: [hour], source: .hours, now: now, recentMinuteRows: [mixed]
        )
        #expect(mixedTail.first?.state == .interrupted)
    }

    @Test func livePressureUsesOnlyFreshDomainObservationsAndResetsOnRecovery() {
        var observations = ReportLivePressureObservations()
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        observations.record(memoryLevel: 1, thermalLevel: nil, freshKinds: [.memory], at: start)
        observations.record(memoryLevel: 1, thermalLevel: 3, freshKinds: [.memory], at: start.addingTimeInterval(10))
        #expect(observations.current(at: start.addingTimeInterval(10))?.kind == .memory)
        #expect(observations.current(at: start.addingTimeInterval(10))?.durationSeconds == 10)
        #expect(observations.current(at: start.addingTimeInterval(11))?.durationSeconds == 10)

        observations.record(memoryLevel: 1, thermalLevel: nil, freshKinds: [.gpu], at: start.addingTimeInterval(38))
        #expect(observations.current(at: start.addingTimeInterval(41)) == nil)
        observations.record(memoryLevel: 2, thermalLevel: nil, freshKinds: [.memory], at: start.addingTimeInterval(42))
        #expect(observations.current(at: start.addingTimeInterval(42))?.durationSeconds == 0)
        observations.record(memoryLevel: 0, thermalLevel: nil, freshKinds: [.memory], at: start.addingTimeInterval(44))
        #expect(observations.current(at: start.addingTimeInterval(44)) == nil)
    }

    @Test @MainActor func pdfExportPaginatesToA4IncludesTrendsAndAllThirtyEvents() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // 构造隔桶交替的 30 段压力事件（共 60 个小时桶），以及完整负载/内存曲线
        var hourRows: [StatisticsRow] = []
        for idx in 0..<60 {
            let t = Int64(now.timeIntervalSince1970) - Int64((60 - idx) * 3600)
            var r = makeRow(
                t: t,
                n: 3600,
                cpuAvg: 25 + Double(idx % 40),
                memPressure: idx.isMultiple(of: 2) ? 72 : 15,
                memWarnS: idx.isMultiple(of: 2) ? 900 : 0,
                coverS: 3600
            )
            r.gpuAvg = 18 + Double(idx % 20)
            r.memPctAvg = 65 + Double(idx % 15)
            r.validMemS = 3600
            r.memNormalS = idx.isMultiple(of: 2) ? 2700 : 3600
            hourRows.append(r)
        }

        let meta = ReportMeta(
            deviceName: "Test Mac",
            modelName: "Mac16,1",
            osVersion: "macOS 27.0",
            recordDays: 7,
            appVersion: "1.6.1",
            isDirect: true
        )
        let snapshot = ReportSnapshot(
            capturedAt: now,
            meta: meta,
            minutes: [],
            hours: hourRows,
            days: [],
            process: nil,
            hardware: nil,
            systemSleepIntervals: []
        )
        let model = ReportDataAggregator.aggregate(snapshot: snapshot, range: .week, now: now)
        #expect(model.events.count == 30)

        let pdfData = ReportExportService.renderPDFData(model: model, meta: meta, hardware: nil)
        let doc = try #require(PDFDocument(data: pdfData))
        #expect(doc.pageCount > 1)

        let firstPage = try #require(doc.page(at: 0))
        let box = firstPage.bounds(for: .mediaBox)
        #expect(abs(box.width - 595.28) < 1.0)
        #expect(abs(box.height - 841.89) < 1.0)

        let extractedText = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string?.precomposedStringWithCompatibilityMapping }
            .joined(separator: "\n")
        #expect(extractedText.contains("#1"))
        #expect(extractedText.contains("#30"))
        #expect(extractedText.contains(String(localized: "report.print.trends", defaultValue: "负载与压力趋势")))

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: output) }
        let operation = try #require(ReportExportService.makePrintOperation(model: model, meta: meta, hardware: nil))
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.printInfo.jobDisposition = .save
        operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        try #require(operation.run())
        let printed = try #require(PDFDocument(url: output))
        #expect(printed.pageCount == doc.pageCount)
        let printedText = (0..<printed.pageCount)
            .compactMap { printed.page(at: $0)?.string?.precomposedStringWithCompatibilityMapping }
            .joined(separator: "\n")
        let eventNumbers = Set(printedText.matches(of: /#[0-9]+/).map { String($0.output) })
        #expect((1...30).allSatisfy { eventNumbers.contains("#\($0)") })
        #expect(printedText.contains(String(localized: "report.print.trends", defaultValue: "负载与压力趋势")))
    }

    @Test func chartHoverDoesNotCrossGapsOrBorrowDifferentTimestamps() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        // CPU 有两段数据，中间隔 3 小时缺口：10:00..10:20 与 13:20..13:30
        let cpuPts = [
            ReportTimeSeriesPoint(id: "c1", date: t0, seriesID: "cpu", segmentID: 0, value: 20),
            ReportTimeSeriesPoint(id: "c2", date: t0.addingTimeInterval(600), seriesID: "cpu", segmentID: 0, value: 30),
            ReportTimeSeriesPoint(id: "c3", date: t0.addingTimeInterval(1200), seriesID: "cpu", segmentID: 0, value: 40),
            ReportTimeSeriesPoint(id: "c4", date: t0.addingTimeInterval(12000), seriesID: "cpu", segmentID: 1, value: 55),
            ReportTimeSeriesPoint(id: "c5", date: t0.addingTimeInterval(12600), seriesID: "cpu", segmentID: 1, value: 65)
        ]
        // GPU 在 10:10 后停止采样，10:20 没有记录
        let gpuPts = [
            ReportTimeSeriesPoint(id: "g1", date: t0, seriesID: "gpu", segmentID: 0, value: 10),
            ReportTimeSeriesPoint(id: "g2", date: t0.addingTimeInterval(600), seriesID: "gpu", segmentID: 0, value: 15)
        ]
        let cpuSeries = ReportChartSeries.from(cpuPts, seriesID: "cpu")
        let gpuSeries = ReportChartSeries.from(gpuPts, seriesID: "gpu")

        // 1. 悬停在 2 小时缺口正中：绝不能跨缺口吸附并展示任何读数
        let gapHover = ReportChartHoverResolver.resolve(
            target: t0.addingTimeInterval(6000),
            series: [("cpu", cpuSeries), ("gpu", gpuSeries)]
        )
        #expect(gapHover == nil)

        // 2. 悬停在 10:20（仅 CPU 有值）：绝不能借用 GPU 10:10 的旧值
        let at1020 = ReportChartHoverResolver.resolve(
            target: t0.addingTimeInterval(1200),
            series: [("cpu", cpuSeries), ("gpu", gpuSeries)]
        )
        #expect(at1020 != nil)
        #expect(at1020?.values["cpu"] == 40)
        #expect(at1020?.values["gpu"] == nil)

        // 3. 悬停在 10:10（同一时间桶两者都有）：两条曲线同时命中
        let at1010 = ReportChartHoverResolver.resolve(
            target: t0.addingTimeInterval(600),
            series: [("cpu", cpuSeries), ("gpu", gpuSeries)]
        )
        #expect(at1010?.values["cpu"] == 30)
        #expect(at1010?.values["gpu"] == 15)
    }

    @Test func chartHoverUsesTheSamplingIntervalForSingletonsAndASharedSmoothingGrid() {
        let start = Date(timeIntervalSince1970: 1_750_003_200)
        func point(_ index: Int, id: String, segment: Int = 0) -> ReportTimeSeriesPoint {
            ReportTimeSeriesPoint(
                id: "\(id)-\(index)", date: start.addingTimeInterval(Double(index * 60)),
                seriesID: id, segmentID: segment, value: Double(index)
            )
        }

        let sparse = ReportChartSeries.from([point(0, id: "cpu"), point(240, id: "cpu", segment: 1)], seriesID: "cpu")
        #expect(ReportChartHoverResolver.resolve(
            target: start.addingTimeInterval(7_200), series: [("cpu", sparse)]
        ) == nil)
        #expect(ReportChartHoverResolver.resolve(
            target: start.addingTimeInterval(20), series: [("cpu", sparse)]
        )?.values["cpu"] == 0)

        let cpu = ReportChartSeries.from((0..<500).map { point($0, id: "cpu") }, seriesID: "cpu")
            .smoothed(referencePointCount: 500)
        let gpu = ReportChartSeries.from((0..<350).map { point($0, id: "gpu") }, seriesID: "gpu")
            .smoothed(referencePointCount: 500)
        let hover = ReportChartHoverResolver.resolve(
            target: start.addingTimeInterval(5_490), series: [("cpu", cpu), ("gpu", gpu)]
        )
        #expect(hover?.values["cpu"] == hover?.values["gpu"])
        #expect(hover?.values.count == 2)
    }

    @Test func pressureInsightOnlyAttributesOverlappingAppAlerts() {
        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let mondayStart = cal.date(byAdding: .day, value: -4, to: now)!
        let tMonday = Int64(mondayStart.timeIntervalSince1970)
        let fridayStart = cal.date(byAdding: .day, value: -1, to: now)!

        var memRow = makeRow(t: tMonday, n: 3600, memPressure: 78, memWarnS: 1200, coverS: 3600)
        memRow.validMemS = 3600
        var recoveredRow = makeRow(t: tMonday + 3600, n: 3600, memPressure: 10, memWarnS: 0, coverS: 3600)
        recoveredRow.validMemS = 3600

        let mondayAppEpisode = ProcessAlertEpisode(
            appKey: "bundle:com.example.OverlapApp",
            name: "OverlapApp",
            metric: .memory,
            startedAt: mondayStart.addingTimeInterval(300),
            lastSeenAt: mondayStart.addingTimeInterval(1500),
            endedAt: mondayStart.addingTimeInterval(1500),
            peakUsage: 4000,
            averageUsage: 3500,
            continuousHighSeconds: 1200,
            eventSpanSeconds: 1200,
            observationCount: 20,
            segments: [.init(start: mondayStart.addingTimeInterval(300), end: mondayStart.addingTimeInterval(1500), averageValue: 3500)],
            endReason: .recovered,
            state: .recovered,
            tier1Seconds: 1200,
            tier2Seconds: 0,
            tier3Seconds: 0,
            iconPNG: nil,
            notified: false
        )

        let fridayAppEpisode = ProcessAlertEpisode(
            appKey: "bundle:com.example.FridayOnly",
            name: "FridayOnly",
            metric: .cpu,
            startedAt: fridayStart,
            lastSeenAt: fridayStart.addingTimeInterval(2400),
            endedAt: fridayStart.addingTimeInterval(2400),
            peakUsage: 95,
            averageUsage: 90,
            continuousHighSeconds: 2400,
            eventSpanSeconds: 2400,
            observationCount: 40,
            segments: [.init(start: fridayStart, end: fridayStart.addingTimeInterval(2400), averageValue: 90)],
            endReason: .recovered,
            state: .recovered,
            tier1Seconds: 0,
            tier2Seconds: 2400,
            tier3Seconds: 0,
            iconPNG: nil,
            notified: false
        )

        let boundary = mondayStart.addingTimeInterval(3600)
        let boundaryEnd = boundary.addingTimeInterval(120)
        let boundaryApp = ProcessAlertEpisode(
            appKey: "bundle:com.example.BoundaryOnly",
            name: "BoundaryOnly",
            metric: .memory,
            startedAt: boundary,
            lastSeenAt: boundaryEnd,
            endedAt: boundaryEnd,
            peakUsage: 5000,
            averageUsage: 4000,
            continuousHighSeconds: 120,
            segments: [.init(start: boundary, end: boundaryEnd, averageValue: 4000)],
            state: .recovered
        )

        let dummyDaily = StatisticsProcessStore.DailyAppRow(
            day: StatisticsProcessStore.dayKey(mondayStart, calendar: cal),
            appKey: "bundle:com.example.OverlapApp",
            name: "OverlapApp",
            cpuAvg: 10, cpuSamples: 10,
            gpuAvg: 0, gpuSamples: 0,
            memAvgBytes: 3_500_000_000, memSamples: 10,
            netDownBytes: 0, netUpBytes: 0,
            diskReadBytes: 0, diskWriteBytes: 0,
            cpuTier1: 0, cpuTier2: 0, cpuTier3: 0, cpuPeak: 15,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0, gpuPeak: 0,
            memTier1: 20, memTier2: 0, memTier3: 0, memPeak: 4_000_000_000
        )

        let snapshot = ReportSnapshot(
            capturedAt: now,
            meta: ReportMeta(deviceName: "Mac", modelName: "Mac16,1", osVersion: "macOS 27", recordDays: 7, appVersion: "1.6", isDirect: true),
            minutes: [],
            hours: [memRow, recoveredRow],
            days: [],
            process: ReportProcessData(identities: [:], dailyRows: [dummyDaily], batteryHistory: [], alerts: [fridayAppEpisode, mondayAppEpisode, boundaryApp]),
            hardware: nil
        )
        let model = ReportDataAggregator.aggregate(snapshot: snapshot, range: .week, now: now)
        let attribution = model.insights.first(where: { $0.id == "pressure-attribution" })
        #expect(attribution != nil)
        #expect(attribution?.detail.contains("OverlapApp") == true)
        #expect(attribution?.detail.contains("FridayOnly") == false)
        #expect(attribution?.detail.contains("BoundaryOnly") == false)
    }

    @Test @MainActor func staleAggregationDoesNotOverwriteHardwareEnrichedFanlessState() async throws {
        let hardwareGate = DispatchSemaphore(value: 0)
        let airInventory = HardwareInventory(
            categories: [
                HardwareCategory(
                    id: "this-mac",
                    nameKey: "kThisMac",
                    subtitleKey: "kThisMac",
                    groups: [
                        HardwareFactGroup(
                            id: "identity",
                            name: .key("kIdentity"),
                            facts: [HardwareFact(label: .key("hwLabelProductName"), value: "MacBook Air")]
                        )
                    ]
                )
            ],
            rails: [:],
            capturedAt: Date()
        )

        let model = NativeReportViewModel(
            recorder: nil,
            snapshotLoader: { _, _ in
                StatisticsReportSnapshotInput(minutes: [], hours: [], days: [], process: nil, systemSleepIntervals: [])
            },
            hardwareLoader: { _ in
                _ = hardwareGate.wait(timeout: .now() + 2.0)
                return airInventory
            }
        )
        defer { model.teardown() }

        model.load()
        for _ in 0..<200 {
            if !model.isLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        // 在硬件完成前切换范围（生成基于旧快照的在途聚合）并放行硬件补全
        model.selectRange(.week)
        hardwareGate.signal()

        for _ in 0..<400 {
            if !model.isLoading && !model.isHardwareLoading && !model.isAggregating { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(model.rangeModel?.range == .week)
        #expect(model.rangeModel?.thermal.hasFans == false)
    }
}
