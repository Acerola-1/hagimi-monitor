import Foundation
import Testing
@testable import HagimiMonitorDirect

/// R05 / R06：事件按查询区间裁剪；范围外事件不进列表与计数；跨午夜只算本期部分。
struct EpisodeClippingTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func episode(start: Date, end: Date, metric: ProcessAlertEpisode.Metric = .cpu) -> ProcessAlertEpisode {
        ProcessAlertEpisode(
            appKey: "bundle:com.example.App", name: "App", metric: metric,
            startedAt: start, lastSeenAt: end, endedAt: end,
            peakUsage: 90, averageUsage: 70,
            continuousHighSeconds: end.timeIntervalSince(start),
            eventSpanSeconds: end.timeIntervalSince(start),
            observationCount: 10,
            endReason: .observationGap,
            state: .interrupted
        )
    }

    @Test func eventEntirelyBeforeRangeIsDropped() {
        let event = episode(start: t0, end: t0.addingTimeInterval(120))
        let result = ReportDataAggregator.clipEpisode(
            event,
            from: t0.addingTimeInterval(3600),
            to: t0.addingTimeInterval(7200)
        )
        // 完全在范围外：不进列表、不进计数。
        #expect(result == nil)
    }

    @Test func eventStraddlingStartIsClippedToRange() {
        // 事件 23:00–01:00（120 分钟），查询从 00:00 开始：本期只应计 60 分钟。
        let event = episode(start: t0, end: t0.addingTimeInterval(120 * 60))
        let clipped = ReportDataAggregator.clipEpisode(
            event,
            from: t0.addingTimeInterval(60 * 60),
            to: t0.addingTimeInterval(240 * 60)
        )
        let value = try? #require(clipped)
        #expect(value?.coveredSeconds == TimeInterval(60 * 60))
        #expect(value?.episode.continuousHighSeconds == TimeInterval(60 * 60))
        // 事件 ID 保持不变，用户仍能追踪到同一条事件。
        #expect(value?.episode.id == event.id)
    }

    @Test func eventInsideRangeIsUnchanged() {
        let event = episode(start: t0, end: t0.addingTimeInterval(120))
        let clipped = ReportDataAggregator.clipEpisode(
            event,
            from: t0.addingTimeInterval(-3600),
            to: t0.addingTimeInterval(3600)
        )
        let value = try? #require(clipped)
        #expect(value?.coveredSeconds == TimeInterval(120))
        #expect(value?.episode.continuousHighSeconds == TimeInterval(120))
        #expect(value?.episode.observationCount == 10)
    }

    @Test func eventStraddlingEndIsClippedToRange() {
        let event = episode(start: t0, end: t0.addingTimeInterval(240 * 60))
        let clipped = ReportDataAggregator.clipEpisode(
            event,
            from: t0.addingTimeInterval(-60),
            to: t0.addingTimeInterval(120 * 60)
        )
        let value = try? #require(clipped)
        #expect(value?.coveredSeconds == TimeInterval(120 * 60))
    }

    @Test func clippedObservationCountStaysAtLeastOne() {
        // 只有很小一部分落在范围内：次数按比例折算但不能变成 0，
        // 否则会显示「有 0 次观测」的矛盾表述。
        let event = episode(start: t0, end: t0.addingTimeInterval(600 * 60))
        let clipped = ReportDataAggregator.clipEpisode(
            event,
            from: t0,
            to: t0.addingTimeInterval(60)
        )
        let value = try? #require(clipped)
        #expect((value?.episode.observationCount ?? 0) >= 1)
    }

    @Test func zeroLengthOverlapIsRejected() {
        let event = episode(start: t0, end: t0.addingTimeInterval(120))
        // 边界恰好相接：没有交集，不返回。
        let result = ReportDataAggregator.clipEpisode(event, from: t0.addingTimeInterval(120), to: t0.addingTimeInterval(300))
        #expect(result == nil)
    }
}

/// 5.3：有分段时按区间精确裁剪，不假设负载在整个事件内均匀分布。
@Suite("事件分段裁剪")
struct EpisodeSegmentClippingTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func segment(_ startOffset: TimeInterval, _ endOffset: TimeInterval, _ average: Double)
        -> AppResourceEventStateMachine.CoveredSegment {
        AppResourceEventStateMachine.CoveredSegment(
            start: t0.addingTimeInterval(startOffset),
            end: t0.addingTimeInterval(endOffset),
            averageValue: average
        )
    }

    @Test func clipsSegmentsToRangeAndRecomputesAverage() {
        // 三段：0–60 均值 80、60–120 均值 20、120–180 均值 60。
        let segments = [segment(0, 60, 80), segment(60, 120, 20), segment(120, 180, 60)]
        let result = AppResourceEventStateMachine.clipSegments(
            segments,
            from: t0.addingTimeInterval(30),
            to: t0.addingTimeInterval(150)
        )
        let value = try? #require(result)
        // 范围内秒数：30 + 60 + 30 = 120。
        #expect(value?.seconds == 120)
        // 均值按秒加权：(80×30 + 20×60 + 60×30) / 120 = 45。
        #expect(value?.averageValue == 45)
        // 峰值取范围内出现过的段。
        #expect(value?.peak == 80)
    }

    @Test func rangeWithoutAnySegmentReturnsNil() {
        let segments = [segment(0, 60, 80)]
        let result = AppResourceEventStateMachine.clipSegments(
            segments,
            from: t0.addingTimeInterval(600),
            to: t0.addingTimeInterval(900)
        )
        // 所有分段都在范围外：返回 nil，调用方据此丢弃该事件。
        #expect(result == nil)
    }

    @Test func nonUniformLoadDoesNotGetFlattenedByProportion() {
        // 均匀折算会把 180 秒的事件在查询前 60 秒时算成均值 53.3；
        // 按分段精确裁剪应得到该段真实的 80。
        let segments = [segment(0, 60, 80), segment(60, 120, 20), segment(120, 180, 60)]
        let clipped = AppResourceEventStateMachine.clipSegments(
            segments, from: t0, to: t0.addingTimeInterval(60))
        let value = try? #require(clipped)
        #expect(value?.averageValue == 80)
        #expect(value?.seconds == 60)
    }

    @Test func eventCarriesSegmentsThroughClipping() {
        // 事件对象携带分段时，聚合层应使用分段结果而非比例折算。
        let episode = ProcessAlertEpisode(
            appKey: "bundle:com.example.App", name: "App", metric: .cpu,
            startedAt: t0, lastSeenAt: t0.addingTimeInterval(180), endedAt: t0.addingTimeInterval(180),
            peakUsage: 80, averageUsage: 53,
            continuousHighSeconds: 180, eventSpanSeconds: 180, observationCount: 4,
            segments: [segment(0, 60, 80), segment(60, 120, 20), segment(120, 180, 60)],
            endReason: .observationGap, state: .interrupted
        )
        let clipped = ReportDataAggregator.clipEpisode(
            episode, from: t0, to: t0.addingTimeInterval(60))
        let value = try? #require(clipped)
        #expect(value?.episode.averageUsage == 80)
        #expect(value?.episode.continuousHighSeconds == 60)
        // 峰值不得高于范围内出现过的段。
        #expect((value?.episode.peakUsage ?? 999) <= 80)
    }

    @Test func legacyEventWithoutSegmentsFallsBackToProportion() {
        let episode = ProcessAlertEpisode(
            appKey: "bundle:com.example.App", name: "App", metric: .cpu,
            startedAt: t0, lastSeenAt: t0.addingTimeInterval(120), endedAt: t0.addingTimeInterval(120),
            peakUsage: 90, averageUsage: 70,
            continuousHighSeconds: 120, eventSpanSeconds: 120, observationCount: 4,
            endReason: .observationGap, state: .interrupted
        )
        let clipped = ReportDataAggregator.clipEpisode(
            episode, from: t0, to: t0.addingTimeInterval(60))
        let value = try? #require(clipped)
        // 无分段时按比例折算一半，行为与升级前一致。
        #expect(value?.episode.continuousHighSeconds == 60)
        #expect(value?.episode.averageUsage == 70)
    }
}

/// 档位分布口径：档位秒数表示各量级持续多久，与观测次数分开；
/// 标签来自共享指标定义，模板不再硬编码边界数字。
@Suite("档位分布口径")
struct EpisodeTierDurationTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    /// ProcessAlertCenter.ingest 接受的是采样元组，不是面板用的 TopCPUProcess。
    private func cpu(_ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: "Heavy", pid: 400, usage: usage)]
    }

    @Test func tierSecondsAccumulateByRealCoverageNotObservationCount() {
        let alerts = ProcessAlertCenter()
        // 三拍各 60 秒，前两拍 70%（tier2），第三拍 90%（tier3）。
        alerts.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(0))
        alerts.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(60))
        alerts.ingest(cpu: cpu(90), memory: [], gpu: [], network: [], at: at(120))
        let episode = alerts.activeAlerts.first
        // 首拍没有覆盖秒数，因此 tier2 收到 60 秒、tier3 收到 60 秒。
        #expect(episode?.tier2Seconds == 60)
        #expect(episode?.tier3Seconds == 60)
        #expect(episode?.tier1Seconds == 0)
        // 档位秒数之和不超过有效高占用总秒数。
        let total = (episode?.tier1Seconds ?? 0) + (episode?.tier2Seconds ?? 0) + (episode?.tier3Seconds ?? 0)
        #expect(total <= (episode?.continuousHighSeconds ?? 0) + 0.001)
    }

    @Test func tierSecondsNeverExceedContinuousDuration() {
        let alerts = ProcessAlertCenter()
        for offset in stride(from: 0.0, through: 300.0, by: 60.0) {
            alerts.ingest(cpu: cpu(95), memory: [], gpu: [], network: [], at: at(offset))
        }
        let episode = alerts.activeAlerts.first
        let total = (episode?.tier1Seconds ?? 0) + (episode?.tier2Seconds ?? 0) + (episode?.tier3Seconds ?? 0)
        #expect(total <= (episode?.continuousHighSeconds ?? 0) + 0.001)
    }

    @Test func bandLabelsComeFromSharedDefinition() {
        // 内存档位是真实的 1/2/4 GiB，不是旧模板里的 2–4 / 4–8 / 8+ GB。
        let memory = StandaloneHTMLReportExporter.bandLabels(for: .memory)
        #expect(memory == ["1.0 GiB", "2.0 GiB", "4.0 GiB"])
        #expect(memory.contains { $0.contains("8") } == false)

        // 网络标签是十进制单位（原始边界是 MiB/s）。
        let network = StandaloneHTMLReportExporter.bandLabels(for: .network)
        #expect(network.first == "5.2 MB/s")

        let cpu = StandaloneHTMLReportExporter.bandLabels(for: .cpu)
        #expect(cpu == ["30%", "50%", "80%"])
    }
}
