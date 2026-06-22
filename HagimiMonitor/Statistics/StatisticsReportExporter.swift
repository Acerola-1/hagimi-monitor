import Foundation
import SwiftData

struct StatisticsReportPayload: Codable {
    let generatedAt: Date
    let appName: String
    let locale: String
    let strings: StatisticsReportStrings
    let ranges: [StatisticsReportRangePayload]
    let events: [StatisticsReportEventPayload]
}

struct StatisticsReportEventPayload: Codable {
    let timestamp: TimeInterval
    let eventType: String
    let severity: Int16
    let title: String
    let detail: String
    let topProcesses: [String]?
    let value: Double?
    let duration: Double?
}

struct HealthScoreReportPayload: Codable {
    let score: Double
    let level: String
    let thermalCapped: Bool
    let isDataAvailable: Bool
    let dimensions: [DimensionScoreReportPayload]
    let trend: [HealthTrendPointPayload]
}

struct HealthTrendPointPayload: Codable {
    let timestamp: TimeInterval
    let score: Double
}

struct DimensionScoreReportPayload: Codable {
    let name: String
    let rawText: String
    let rawValue: Double
    let healthValue: Double
    let weight: Double
    let level: String
    let isAvailable: Bool
}

struct StatisticsReportStrings: Codable {
    let title: String
    let subtitle: String
    let footer: String
    let avg: String
    let peak: String
    let low: String
    let median: String
    let download: String
    let upload: String
    let read: String
    let write: String
    let empty: String
    // Health score
    let healthTitle: String
    let healthExcellent: String
    let healthGood: String
    let healthFair: String
    let healthPoor: String
    let healthCritical: String
    let healthThermalCapped: String
    let healthNoData: String
    let healthNoDataHint: String
    // Event timeline
    let eventTitle: String
    let eventTopProcesses: String
    let eventDuration: String
    let eventShowMore: String
    // Executive Summary
    let summaryTitle: String
    let moduleLoad: String
    let keyInsights: String
    let insightLoadHigh: String
    let insightLoadMedium: String
    let insightLoadLow: String
    let insightPeak: String
    let insightBusiest: String
    let insightHealthScore: String
    let insightThermal: String
    let insightSevereEvents: String
    // Heatmap
    let heatmapTitle: String
    let heatmapDescription: String
    let heatmapAvg: String
    let heatmapLow: String
    let heatmapHigh: String
    // Card tabs
    let tabTrend: String
    let tabDistribution: String
    // Histogram
    let samples: String
    // Time labels
    let today: String
    let yesterday: String
    let daySun: String
    let dayMon: String
    let dayTue: String
    let dayWed: String
    let dayThu: String
    let dayFri: String
    let daySat: String
}

struct StatisticsReportRangePayload: Codable {
    let id: String
    let title: String
    let healthScore: HealthScoreReportPayload?
    let modules: [StatisticsReportModulePayload]
}

struct StatisticsReportModulePayload: Codable {
    let kind: String
    let title: String
    let symbol: String
    let avg: Double
    let peak: Double
    let low: Double
    let median: Double
    let p50: Double
    let p90: Double
    let p95: Double
    let totalBytesIn: Int64?
    let totalBytesOut: Int64?
    let totalBytesRead: Int64?
    let totalBytesWritten: Int64?
    let avgPower: Double?
    let points: [StatisticsReportPointPayload]
}

struct StatisticsReportPointPayload: Codable {
    let timestamp: TimeInterval
    let avg: Double
    let peak: Double
    let low: Double
    let bytesIn: Int64?
    let bytesOut: Int64?
    let bytesRead: Int64?
    let bytesWritten: Int64?
}

@MainActor
struct StatisticsReportExporter {
    private struct RangeSpec {
        let id: String
        let range: StatisticsTimeRange
    }

    private static let rangeSpecs = [
        RangeSpec(id: "last24Hours", range: .last24Hours),
        RangeSpec(id: "lastWeek", range: .lastWeek),
        RangeSpec(id: "lastMonth", range: .lastMonth),
        RangeSpec(id: "lastYear", range: .lastYear)
    ]
    private static let kinds: [MonitorKind] = [.cpu, .gpu, .memory, .network, .storage, .power]

    private let aggregator: StatisticsAggregator
    private let outputDirectory: URL
    private let now: () -> Date

    init(container: ModelContainer = StatisticsStore.container, outputDirectory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.aggregator = StatisticsAggregator(container: container)
        let baseDirectory = outputDirectory ?? FileManager.default.temporaryDirectory
        self.outputDirectory = baseDirectory.appendingPathComponent("HagimiMonitor", isDirectory: true)
        self.now = now
    }

    func makePayload(pending: [String: PendingBucket] = [:]) -> StatisticsReportPayload {
        let events = aggregator.queryEvents(range: .lastYear, limit: 1000)
        return StatisticsReportPayload(
            generatedAt: now(),
            appName: "HagimiMonitor",
            locale: Locale.preferredLanguages.first ?? Locale.current.identifier,
            strings: StatisticsReportStrings(
                title: String(localized: "stats.report.title"),
                subtitle: String(localized: "stats.report.subtitle"),
                footer: String(localized: "stats.report.footer"),
                avg: String(localized: "stats.avg"),
                peak: String(localized: "stats.peak"),
                low: String(localized: "stats.low"),
                median: String(localized: "stats.median"),
                download: String(localized: "stats.net.down"),
                upload: String(localized: "stats.net.up"),
                read: String(localized: "stats.disk.read"),
                write: String(localized: "stats.disk.write"),
                empty: String(localized: "stats.no-data"),
                healthTitle: String(localized: "health.title"),
                healthExcellent: String(localized: "health.level.excellent"),
                healthGood: String(localized: "health.level.good"),
                healthFair: String(localized: "health.level.fair"),
                healthPoor: String(localized: "health.level.poor"),
                healthCritical: String(localized: "health.level.critical"),
                healthThermalCapped: String(localized: "health.thermal-capped"),
                healthNoData: String(localized: "health.no-data"),
                healthNoDataHint: String(localized: "health.no-data.hint"),
                eventTitle: String(localized: "event.title"),
                eventTopProcesses: String(localized: "event.top-processes"),
                eventDuration: String(localized: "event.duration"),
                eventShowMore: String(localized: "event.show-more"),
                // Executive Summary
                summaryTitle: String(localized: "report.summary.title"),
                moduleLoad: String(localized: "report.module-load"),
                keyInsights: String(localized: "report.key-insights"),
                insightLoadHigh: String(localized: "report.insight.load-high"),
                insightLoadMedium: String(localized: "report.insight.load-medium"),
                insightLoadLow: String(localized: "report.insight.load-low"),
                insightPeak: String(localized: "report.insight.peak"),
                insightBusiest: String(localized: "report.insight.busiest"),
                insightHealthScore: String(localized: "report.insight.health-score"),
                insightThermal: String(localized: "report.insight.thermal"),
                insightSevereEvents: String(localized: "report.insight.severe-events"),
                // Heatmap
                heatmapTitle: String(localized: "report.heatmap.title"),
                heatmapDescription: String(localized: "report.heatmap.description"),
                heatmapAvg: String(localized: "report.heatmap.avg"),
                heatmapLow: String(localized: "report.heatmap.low"),
                heatmapHigh: String(localized: "report.heatmap.high"),
                // Card tabs
                tabTrend: String(localized: "report.tab.trend"),
                tabDistribution: String(localized: "report.tab.distribution"),
                // Histogram
                samples: String(localized: "report.samples"),
                // Time labels
                today: String(localized: "report.today"),
                yesterday: String(localized: "report.yesterday"),
                daySun: String(localized: "report.day.sun"),
                dayMon: String(localized: "report.day.mon"),
                dayTue: String(localized: "report.day.tue"),
                dayWed: String(localized: "report.day.wed"),
                dayThu: String(localized: "report.day.thu"),
                dayFri: String(localized: "report.day.fri"),
                daySat: String(localized: "report.day.sat")
            ),
            ranges: Self.rangeSpecs.map { spec in
                let pendingBuckets = spec.range == .last24Hours ? pending : nil
                let health = aggregator.queryHealthScore(range: spec.range, pending: pendingBuckets)
                return StatisticsReportRangePayload(
                    id: spec.id,
                    title: spec.range.title,
                    healthScore: healthScorePayload(from: health),
                    modules: Self.kinds.map { kind in
                        let modulePending = spec.range == .last24Hours ? pending[kind.rawValue] : nil
                        return modulePayload(from: aggregator.query(kind: kind, range: spec.range, pending: modulePending))
                    }
                )
            },
            events: events.map { event in
                let processes: [String]? = event.topProcesses.flatMap { json in
                    guard let data = json.data(using: .utf8),
                          let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
                    return arr.isEmpty ? nil : arr
                }
                return StatisticsReportEventPayload(
                    timestamp: event.timestamp.timeIntervalSince1970,
                    eventType: event.eventType,
                    severity: event.severity,
                    title: event.title,
                    detail: event.detail,
                    topProcesses: processes,
                    value: event.value,
                    duration: event.duration
                )
            }
        )
    }

    func export(pending: [String: PendingBucket] = [:]) throws -> URL {
        let payload = makePayload(pending: pending)
        let html = try StatisticsReportHTMLBuilder().build(payload: payload)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fileURL = outputDirectory.appendingPathComponent("hagimi-statistics-\(Int(payload.generatedAt.timeIntervalSince1970 * 1000)).html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func healthScorePayload(from health: HealthScore) -> HealthScoreReportPayload {
        HealthScoreReportPayload(
            score: health.score,
            level: health.level.rawValue,
            thermalCapped: health.thermalCapped,
            isDataAvailable: health.isDataAvailable,
            dimensions: health.dimensions.map { dim in
                DimensionScoreReportPayload(
                    name: dim.name,
                    rawText: dim.rawText,
                    rawValue: dim.rawValue,
                    healthValue: dim.healthValue,
                    weight: dim.weight,
                    level: dim.level.rawValue,
                    isAvailable: dim.isAvailable
                )
            },
            trend: health.trend.map { HealthTrendPointPayload(timestamp: $0.date.timeIntervalSince1970, score: $0.score) }
        )
    }

    private static func percentile(sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = p * Double(sorted.count - 1)
        let lo = Int(idx)
        let hi = min(lo + 1, sorted.count - 1)
        let frac = idx - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    private func modulePayload(from summary: StatisticsSummary) -> StatisticsReportModulePayload {
        let avgs = summary.points.map(\.avg).sorted()
        return StatisticsReportModulePayload(
            kind: summary.kind.rawValue,
            title: summary.kind.title,
            symbol: summary.kind.symbol,
            avg: summary.avg,
            peak: summary.peak,
            low: summary.low,
            median: summary.median,
            p50: Self.percentile(sorted: avgs, p: 0.50),
            p90: Self.percentile(sorted: avgs, p: 0.90),
            p95: Self.percentile(sorted: avgs, p: 0.95),
            totalBytesIn: summary.totalBytesIn,
            totalBytesOut: summary.totalBytesOut,
            totalBytesRead: summary.totalBytesRead,
            totalBytesWritten: summary.totalBytesWritten,
            avgPower: summary.avgPower,
            points: summary.points.map { point in
                StatisticsReportPointPayload(timestamp: point.date.timeIntervalSince1970, avg: point.avg, peak: point.peak, low: point.low, bytesIn: point.bytesIn, bytesOut: point.bytesOut, bytesRead: point.bytesRead, bytesWritten: point.bytesWritten)
            }
        )
    }
}

struct StatisticsReportHTMLBuilder {
    func build(payload: StatisticsReportPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadJSON = String(decoding: try encoder.encode(payload), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        let lang = htmlLang(from: payload.locale)
        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(payload.strings.title) · HagimiMonitor</title>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #fafafc;
              --bg-elev: #ffffff;
              --bg-inset: #f1f1f4;
              --bg-soft: #f6f6f9;
              --text: #1d1d1f;
              --text-dim: #86868b;
              --text-faint: #b0b0b5;
              --border: rgba(0,0,0,.06);
              --hairline: rgba(0,0,0,.05);
              --shadow-sm: 0 1px 2px rgba(0,0,0,.04);
              --shadow-md: 0 1px 3px rgba(0,0,0,.04), 0 8px 24px rgba(0,0,0,.05);
              --c-cpu: #ff453a; --c-gpu: #30d158; --c-memory: #ff9f0a;
              --c-storage: #007aff; --c-network: #5ac8fa; --c-power: #af52de;
              --c-default: #5856d6;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #000000; --bg-elev: #1c1c1e; --bg-inset: #2c2c2e; --bg-soft: #161618;
                --text: #f5f5f7; --text-dim: #98989d; --text-faint: #636366;
                --border: rgba(255,255,255,.08); --hairline: rgba(255,255,255,.06);
                --shadow-sm: 0 1px 2px rgba(0,0,0,.4);
                --shadow-md: 0 1px 3px rgba(0,0,0,.4), 0 8px 24px rgba(0,0,0,.4);
                --c-cpu: #ff6961; --c-gpu: #5be17b; --c-memory: #ffb340;
                --c-storage: #0a84ff; --c-network: #64d2ff; --c-power: #bf5af2;
              }
            }
            * { box-sizing: border-box; }
            html { -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }
            body {
              margin: 0; background: var(--bg); color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text",
                "PingFang SC", "Hiragino Sans", "Helvetica Neue", system-ui, sans-serif;
              font-size: 14px; line-height: 1.5;
              font-feature-settings: "ss01", "cv01";
            }
            .wrap { max-width: 1280px; margin: 0 auto; padding: 56px 32px 80px; }

            /* ===== Header ===== */
            .hero { display: flex; flex-wrap: wrap; align-items: flex-start;
              gap: 20px 32px; margin-bottom: 36px; }
            .hero-text { flex: 1; min-width: 240px; }
            .eyebrow { display: inline-flex; align-items: center; gap: 6px; font-size: 12px;
              color: var(--text-dim); font-weight: 600; letter-spacing: .04em;
              text-transform: uppercase; margin-bottom: 10px; }
            .eyebrow::before { content: ""; width: 6px; height: 6px; border-radius: 50%;
              background: var(--c-network); box-shadow: 0 0 0 3px rgba(90,200,250,.18); }
            h1 { margin: 0; font-size: 34px; font-weight: 700; letter-spacing: -.026em;
              line-height: 1.15; }
            .sub { margin: 8px 0 0; color: var(--text-dim); font-size: 15px; max-width: 540px; }
            .meta { color: var(--text-faint); font-size: 12px; margin-top: 14px;
              font-variant-numeric: tabular-nums; }

            /* ===== Tabs ===== */
            .segmented { display: inline-flex; padding: 3px; gap: 2px; border-radius: 12px;
              background: var(--bg-inset); border: 1px solid var(--hairline);
              align-self: flex-start; }
            .segmented button { appearance: none; border: 0; background: transparent; cursor: pointer;
              padding: 8px 16px; border-radius: 9px; font-size: 13px; font-weight: 590;
              color: var(--text-dim); font-family: inherit; letter-spacing: -.005em;
              transition: color .15s, background .15s; white-space: nowrap; }
            .segmented button:hover { color: var(--text); }
            .segmented button.active { background: var(--bg-elev); color: var(--text);
              box-shadow: var(--shadow-sm); }
            @media (prefers-color-scheme: dark) {
              .segmented button.active { background: #48484a; }
            }

            /* ===== Cards ===== */
            .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(380px, 1fr)); gap: 18px; }
            .card { position: relative; background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 22px 22px 16px; box-shadow: var(--shadow-md);
              overflow: hidden; }
            .card::before { content: ""; position: absolute; inset: 0 0 auto 0; height: 2px;
              background: var(--accent-c); opacity: .9; }
            .card-head { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
            .card-icon { position: relative; width: 32px; height: 32px; border-radius: 9px; flex: none;
              background: var(--accent-c);
              display: grid; place-items: center; color: #fff;
              box-shadow: 0 2px 6px rgba(0,0,0,.12); }
            .card-icon::after { content: ""; position: absolute; inset: 0; border-radius: inherit;
              background: linear-gradient(135deg, rgba(255,255,255,.18), rgba(0,0,0,.05));
              pointer-events: none; }
            .card-icon svg { width: 16px; height: 16px; stroke-width: 2.4; position: relative; z-index: 1; }
            .card-head h2 { margin: 0; font-size: 16px; font-weight: 640;
              letter-spacing: -.01em; flex: 1; }

            /* ===== Metrics ===== */
            .metrics { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0;
              margin: 0 -4px 16px; padding: 4px; }
            .metric { padding: 6px 12px; position: relative; }
            .metric + .metric::before { content: ""; position: absolute; left: 0; top: 12%;
              bottom: 12%; width: 1px; background: var(--hairline); }
            .metric label { display: block; color: var(--text-dim); font-size: 11px;
              font-weight: 500; margin-bottom: 4px; letter-spacing: .01em; }
            .metric strong { display: block; font-size: 22px; font-weight: 600;
              letter-spacing: -.022em; font-variant-numeric: tabular-nums;
              line-height: 1.1; }
            .metric.lead strong { color: var(--accent-c); font-weight: 680; }
            .metric .unit { font-size: 13px; font-weight: 500; color: var(--text-dim);
              margin-left: 2px; letter-spacing: 0; }

            /* Dual layout for net / storage */
            .metrics.dual { grid-template-columns: 1fr 1fr; }
            .metrics.dual .metric strong { font-size: 24px; }

            /* ===== Chart ===== */
            .chart { position: relative; height: 156px; margin: 6px -6px 0;
              border-radius: 10px; padding: 6px 6px 4px; }
            .chart svg { width: 100%; height: 100%; display: block; overflow: visible; }
            .gridline { stroke: var(--hairline); stroke-width: 1; }
            .axis-label { fill: var(--text-faint); font-size: 9.5px;
              font-variant-numeric: tabular-nums; font-weight: 500; }
            .cursor-line { stroke: var(--text-faint); stroke-width: 1;
              stroke-dasharray: 2 3; opacity: 0; }
            .cursor-dot { opacity: 0; }
            .tooltip { position: absolute; pointer-events: none; opacity: 0;
              transform: translate(-50%, calc(-100% - 10px));
              background: var(--text); color: var(--bg-elev);
              padding: 8px 11px; border-radius: 9px;
              font-size: 11.5px; line-height: 1.5; white-space: nowrap;
              box-shadow: 0 8px 24px rgba(0,0,0,.25);
              transition: opacity .12s; z-index: 5;
              font-variant-numeric: tabular-nums; }
            .tooltip b { font-weight: 700; }
            .tooltip .t-date { opacity: .55; font-size: 10.5px;
              margin-bottom: 2px; }

            .empty { height: 156px; display: grid; place-items: center;
              color: var(--text-faint); background: var(--bg-soft);
              border-radius: 12px; font-size: 13px; font-weight: 500; }

            .legend { display: flex; gap: 16px; margin-top: 12px; padding-top: 12px;
              border-top: 1px solid var(--hairline); }
            .legend span { display: inline-flex; align-items: center; gap: 6px;
              font-size: 11.5px; color: var(--text-dim); font-weight: 500; }
            .legend i { width: 16px; height: 2px; border-radius: 2px;
              display: inline-block; }
            .legend i.dashed { background: none !important;
              border-top: 2px dashed; }

            /* ===== Health Score ===== */
            .health-card { background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 28px; box-shadow: var(--shadow-md);
              margin-bottom: 24px; display: flex; align-items: center; gap: 32px;
              flex-wrap: wrap; }
            .health-ring-wrap { position: relative; width: 140px; height: 140px; flex: none; }
            .health-ring-wrap svg { width: 100%; height: 100%; transform: rotate(-90deg); }
            .health-ring-bg { fill: none; stroke: var(--bg-inset); stroke-width: 10; }
            .health-ring-fg { fill: none; stroke-width: 10; stroke-linecap: round;
              transition: stroke-dashoffset .6s ease; }
            .health-ring-text { position: absolute; inset: 0; display: flex; flex-direction: column;
              align-items: center; justify-content: center; }
            .health-ring-text .score { font-size: 32px; font-weight: 700; letter-spacing: -.02em;
              font-variant-numeric: tabular-nums; line-height: 1; }
            .health-ring-text .level { font-size: 12px; font-weight: 600; margin-top: 4px;
              letter-spacing: .02em; }
            .health-ring-text .capped { font-size: 10px; color: #d94848; margin-top: 2px; font-weight: 500; }
            .health-dims { flex: 1; min-width: 240px; }
            .health-dim-row { display: flex; align-items: center; gap: 10px; padding: 5px 0; }
            .health-dim-row .dim-name { width: 90px; font-size: 12.5px; color: var(--text-dim);
              font-weight: 500; flex: none; }
            .health-dim-row .dim-bar { flex: 1; height: 8px; background: var(--bg-inset);
              border-radius: 4px; overflow: hidden; }
            .health-dim-row .dim-bar-fill { height: 100%; border-radius: 4px; transition: width .4s ease; }
            .health-dim-row .dim-val { width: 36px; text-align: right; font-size: 12px;
              font-weight: 600; font-variant-numeric: tabular-nums; flex: none; }
            .health-dim-row .dim-raw { width: 64px; text-align: right; font-size: 11.5px;
              color: var(--text-dim); font-variant-numeric: tabular-nums; flex: none; }
            .health-empty { padding: 20px 4px; color: var(--text-dim); font-size: 13px; }
            .health-empty .hint { font-size: 11.5px; color: var(--text-faint); margin-top: 4px; }
            .health-trend { margin-top: 14px; width: 100%; height: 48px; }
            .health-trend path.line { fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }

            /* ===== Event Timeline ===== */
            .timeline-section { background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 24px; box-shadow: var(--shadow-md); margin-bottom: 24px; }
            .timeline-section h2 { margin: 0 0 4px; font-size: 16px; font-weight: 640;
              letter-spacing: -.01em; }
            .timeline-section .event-count { color: var(--text-dim); font-size: 12px;
              font-weight: 500; margin-bottom: 18px; }
            .timeline-day { margin-bottom: 16px; }
            .timeline-day-label { font-size: 12px; font-weight: 600; color: var(--text-dim);
              margin-bottom: 8px; letter-spacing: .01em; }
            .timeline-events { position: relative; padding-left: 28px; }
            .timeline-events::before { content: ""; position: absolute; left: 8px; top: 4px;
              bottom: 4px; width: 2px; background: var(--hairline); border-radius: 1px; }
            .timeline-row { position: relative; padding: 6px 0; }
            .timeline-row::before { content: ""; position: absolute; left: -24px; top: 12px;
              width: 10px; height: 10px; border-radius: 50%; border: 2px solid var(--bg-elev); z-index: 1; }
            .timeline-row.severity-2::before { background: #ff453a; box-shadow: 0 0 0 2px rgba(255,69,58,.25); }
            .timeline-row.severity-1::before { background: #ff9f0a; box-shadow: 0 0 0 2px rgba(255,159,10,.25); }
            .timeline-row.severity-0::before { background: var(--text-faint); }
            .timeline-row .event-time { font-size: 11px; color: var(--text-faint); font-variant-numeric: tabular-nums; }
            .timeline-row .event-title { font-size: 13px; font-weight: 600; margin: 2px 0; }
            .timeline-row .event-detail { font-size: 12px; color: var(--text-dim); }
            .timeline-row .event-processes { font-size: 11px; color: var(--text-faint); margin-top: 2px; }
            .timeline-more { display: flex; justify-content: center; margin-top: 14px; }
            .timeline-more button { border: 0; border-radius: 999px; padding: 7px 14px;
              background: var(--bg-inset); color: var(--accent); font: inherit; font-size: 12px;
              font-weight: 600; cursor: pointer; }
            .timeline-more button:hover { filter: brightness(0.96); }
            @media (prefers-color-scheme: dark) {
              .timeline-row.severity-2::before { background: #ff6961; }
              .timeline-row.severity-1::before { background: #ffb340; }
            }

            /* ===== Footer ===== */
            footer { margin-top: 56px; padding-top: 20px;
              border-top: 1px solid var(--hairline);
              text-align: center; color: var(--text-faint); font-size: 12px; }

            @media (max-width: 600px) {
              .wrap { padding: 32px 16px 56px; }
              h1 { font-size: 26px; }
              .grid { grid-template-columns: 1fr; gap: 14px; }
              .segmented { overflow-x: auto; max-width: 100%; }
              .metrics { grid-template-columns: 1fr 1fr; }
              .metric:nth-child(3) { grid-column: span 2; padding-top: 10px; }
              .metric:nth-child(3)::before { display: none; }
            }

            /* ===== Executive Summary ===== */
            .insights { margin-bottom: 28px; }
            .insights h2 { margin: 0 0 18px; font-size: 20px; font-weight: 700;
              letter-spacing: -.02em; }
            .insight-grid { display: grid;
              grid-template-columns: minmax(200px, 200px) 1fr 1fr;
              gap: 16px; align-items: stretch; }
            .insight-score { background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 20px 24px; box-shadow: var(--shadow-md);
              display: flex; flex-direction: column; align-items: center; justify-content: center;
              gap: 6px; }
            .score-ring-wrap { position: relative; width: 80px; height: 80px; }
            .score-ring-wrap svg { width: 100%; height: 100%; }
            .score-ring-text { position: absolute; inset: 0; display: flex;
              align-items: center; justify-content: center; }
            .insight-score .big-score { font-size: 28px; font-weight: 700;
              font-variant-numeric: tabular-nums; letter-spacing: -.02em; line-height: 1; }
            .insight-score .score-label { font-size: 12px; color: var(--text-dim);
              font-weight: 600; letter-spacing: .02em; }
            .score-capped { font-size: 10px; color: #d94848; font-weight: 600; }
            .score-dots { display: flex; gap: 5px; margin-top: 4px; flex-wrap: wrap;
              justify-content: center; }
            .score-badge { display: inline-flex; align-items: center; gap: 4px;
              font-size: 10px; font-weight: 600; padding: 2px 7px; border-radius: 6px;
              border: 1px solid; background: var(--bg-soft); }
            .score-badge-dot { width: 6px; height: 6px; border-radius: 50%; flex: none; }
            .insight-load { background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 22px; box-shadow: var(--shadow-md); }
            .insight-load h3 { margin: 0 0 14px; font-size: 13px; color: var(--text-dim);
              font-weight: 600; letter-spacing: .02em; text-transform: uppercase; }
            .insight-load-item { display: flex; align-items: center; gap: 10px; padding: 5px 0; }
            .insight-load-item .il-name { width: 80px; font-size: 12.5px; color: var(--text-dim);
              font-weight: 500; flex: none; }
            .insight-load-item .il-bar { flex: 1; min-width: 0; height: 8px; background: var(--bg-inset);
              border-radius: 4px; overflow: hidden; }
            .insight-load-item .il-bar-fill { display: block; height: 100%; border-radius: 4px;
              transition: width .4s ease; }
            .insight-load-item .il-val { width: 40px; text-align: right; font-size: 12px;
              font-weight: 600; font-variant-numeric: tabular-nums; flex: none; }
            .insight-list { background: var(--bg-elev); border: 1px solid var(--border);
              border-radius: 18px; padding: 22px; box-shadow: var(--shadow-md); }
            .insight-list h3 { margin: 0 0 14px; font-size: 13px; color: var(--text-dim);
              font-weight: 600; letter-spacing: .02em; text-transform: uppercase; }
            .insight-list ul { margin: 0; padding: 0; list-style: none; }
            .insight-list li { padding: 5px 0; font-size: 13px; color: var(--text);
              line-height: 1.5; }
            .insight-list li::before { content: ""; display: inline-block; width: 6px;
              height: 6px; border-radius: 50%; margin-right: 8px; vertical-align: middle;
              background: var(--c-network); }

            /* ===== Heatmap ===== */
            .heatmap-wrap { margin-top: 20px; background: var(--bg-elev);
              border: 1px solid var(--border); border-radius: 18px; padding: 22px;
              box-shadow: var(--shadow-md); position: relative; }
            .heatmap-wrap h3 { margin: 0 0 8px; font-size: 13px; color: var(--text-dim);
              font-weight: 600; letter-spacing: .02em; text-transform: uppercase; }
            .heatmap-desc { margin: 0 0 14px; font-size: 11px; line-height: 1.45;
              color: var(--text-faint); }
            .heatmap-tabs { margin-bottom: 14px; }
            .heatmap-section { margin-bottom: 18px; }
            .heatmap-section:last-child { margin-bottom: 0; }
            .heatmap-section-title { font-size: 12px; font-weight: 600; color: var(--text);
              margin-bottom: 8px; }
            .heatmap-grid-wrap { min-width: 0; }
            .heatmap-hour-row { display: grid; grid-template-columns: 18px repeat(24, 1fr);
              gap: 2px; margin-bottom: 2px; }
            .heatmap-hour-row span { text-align: center; font-size: 10px;
              color: var(--text-faint); }
            .heatmap-rows { display: flex; flex-direction: column; gap: 2px; }
            .heatmap-row { display: grid; grid-template-columns: 18px repeat(24, 1fr); gap: 2px; }
            .heatmap-day-label { display: flex; align-items: center; justify-content: center;
              aspect-ratio: 1; font-size: 10px; color: var(--text-faint); font-weight: 500;
              font-variant-numeric: tabular-nums; }
            .heatmap-cell { aspect-ratio: 1; border-radius: 3px;
              background: var(--bg-inset); transition: background .15s; min-width: 0; }
            .heatmap-cell:hover { outline: 2px solid var(--text-faint); outline-offset: 1px; }
            .heatmap-legend { display: flex; align-items: center; gap: 4px;
              margin-top: 10px; justify-content: flex-end; }
            .heatmap-legend span { font-size: 10px; color: var(--text-faint); }
            .heatmap-legend .heatmap-cell { cursor: default; width: 14px; height: 14px;
              flex: none; aspect-ratio: auto; }
            .heatmap-legend .heatmap-cell:hover { outline: none; }
            .heatmap-tip { position: fixed; pointer-events: none; opacity: 0;
              transform: translate(-50%, calc(-100% - 8px));
              background: var(--text); color: var(--bg-elev);
              padding: 6px 10px; border-radius: 8px; font-size: 11.5px;
              white-space: nowrap; box-shadow: 0 6px 16px rgba(0,0,0,.2);
              transition: opacity .12s; z-index: 10;
              font-variant-numeric: tabular-nums; }
            .heatmap-tip b { font-weight: 700; }

            /* ===== Percentile badges ===== */
            .percentiles { display: flex; gap: 10px; margin-top: 12px;
              padding-top: 12px; border-top: 1px solid var(--hairline); }
            .pct-badge { background: var(--bg-soft); border-radius: 8px;
              padding: 6px 10px; text-align: center; flex: 1; }
            .pct-badge .pct-label { font-size: 10px; color: var(--text-faint);
              font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
            .pct-badge .pct-val { font-size: 14px; font-weight: 660;
              font-variant-numeric: tabular-nums; margin-top: 2px; }

            /* ===== Histogram ===== */
            .hist-wrap { position: relative; height: 130px; margin: 6px -6px 0;
              border-radius: 10px; padding: 10px 8px 4px; }
            .hist-wrap svg { width: 100%; height: 100%; display: block; overflow: visible; }
            .hist-bar { rx: 2; }
            .hist-bar:hover { opacity: .85; }
            .hist-label { fill: var(--text-faint); font-size: 9px;
              font-variant-numeric: tabular-nums; font-weight: 500; }
            .hist-tooltip { position: absolute; pointer-events: none; opacity: 0;
              transform: translate(-50%, calc(-100% - 6px));
              background: var(--text); color: var(--bg-elev);
              padding: 6px 10px; border-radius: 8px; font-size: 11px;
              white-space: nowrap; box-shadow: 0 6px 16px rgba(0,0,0,.2);
              transition: opacity .12s; z-index: 5;
              font-variant-numeric: tabular-nums; }

            /* ===== Chart peak marker ===== */
            .peak-label { font-size: 9px; font-weight: 600;
              font-variant-numeric: tabular-nums; }

            /* ===== Chart/Tab toggle ===== */
            .card-tabs { display: flex; gap: 2px; margin-bottom: 12px;
              background: var(--bg-inset); border-radius: 8px; padding: 2px; }
            .card-tabs button { appearance: none; border: 0; background: transparent;
              cursor: pointer; padding: 5px 12px; border-radius: 6px;
              font-size: 11.5px; font-weight: 580; color: var(--text-dim);
              font-family: inherit; transition: color .15s, background .15s;
              white-space: nowrap; }
            .card-tabs button:hover { color: var(--text); }
            .card-tabs button.active { background: var(--bg-elev); color: var(--text);
              box-shadow: var(--shadow-sm); }
          </style>
        </head>
        <body>
          <div class="wrap">
            <header class="hero">
              <div class="hero-text">
                <div class="eyebrow">HagimiMonitor</div>
                <h1 id="title"></h1>
                <p class="sub" id="subtitle"></p>
                <div class="meta" id="generated"></div>
              </div>
              <nav class="segmented" id="tabs" role="tablist"></nav>
            </header>
            <section class="insights" id="insights"></section>
            <section class="grid" id="cards"></section>
            <section id="timeline"></section>
            <footer id="footer"></footer>
          </div>
          <script id="payload" type="application/json">\(payloadJSON)</script>
          <script>
            "use strict";
            const payload = JSON.parse(document.getElementById('payload').textContent);
            const L = payload.strings;
            const locale = payload.locale || undefined;
            let active = payload.ranges[0] && payload.ranges[0].id;
            let timelineLimit = 50;

            const RANGE_WINDOW_MS = {
              last24Hours: 24 * 60 * 60 * 1000,
              lastWeek: 7 * 24 * 60 * 60 * 1000,
              lastMonth: 30 * 24 * 60 * 60 * 1000,
              lastYear: 365 * 24 * 60 * 60 * 1000
            };

            const ACCENT_LIGHT = {
              cpu: '#ff453a', gpu: '#30d158', memory: '#ff9f0a',
              storage: '#007aff', network: '#5ac8fa', power: '#af52de'
            };
            const ACCENT_DARK = {
              cpu: '#ff6961', gpu: '#5be17b', memory: '#ffb340',
              storage: '#0a84ff', network: '#64d2ff', power: '#bf5af2'
            };
            const isDark = matchMedia && matchMedia('(prefers-color-scheme: dark)').matches;
            const ACCENTS = isDark ? ACCENT_DARK : ACCENT_LIGHT;
            const accentOf = k => ACCENTS[k] || (isDark ? '#5856d6' : '#5e5ce6');

            const ICON = {
              cpu: '<rect x="4" y="4" width="16" height="16" rx="2.5"/><rect x="9" y="9" width="6" height="6"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3"/>',
              gpu: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="8" cy="12" r="2.4"/><circle cx="16" cy="12" r="2.4"/>',
              memory: '<path d="M3 7h18M3 12h18M3 17h18"/><circle cx="6" cy="7" r="1" fill="currentColor"/><circle cx="6" cy="12" r="1" fill="currentColor"/><circle cx="6" cy="17" r="1" fill="currentColor"/>',
              storage: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="0.8" fill="currentColor"/>',
              network: '<path d="M2 12c5-5 15-5 20 0M5 15c4-3 10-3 14 0M9 18c1.5-1 4.5-1 6 0"/><circle cx="12" cy="20" r="1" fill="currentColor"/>',
              power: '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>'
            };
            const iconOf = k => ICON[k] || '<circle cx="12" cy="12" r="8"/>';

            // ===== Header text =====
            const genDate = new Date(payload.generatedAt);
            const fmtFull = genDate.toLocaleString(locale, {
              year: 'numeric', month: 'short', day: 'numeric',
              hour: '2-digit', minute: '2-digit'
            });
            document.title = L.title + ' · HagimiMonitor';
            document.getElementById('title').textContent = L.title;
            document.getElementById('subtitle').textContent = L.subtitle;
            document.getElementById('generated').textContent = fmtFull;
            document.getElementById('footer').textContent = L.footer;

            // ===== Formatters =====
            function bytes(v) {
              if (!v) return { num: '0', unit: 'B' };
              const u = ['B','KB','MB','GB','TB']; let n = v, i = 0;
              while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
              return { num: n.toFixed(i >= 3 ? 2 : (i === 0 ? 0 : 1)), unit: u[i] };
            }
            function pct(v, kind) {
              if (!Number.isFinite(v)) return { num: '--', unit: '' };
              return { num: v.toFixed(1), unit: kind === 'power' ? 'W' : '%' };
            }
            function withUnit(o) {
              if (!o.unit) return o.num;
              return o.num + '<span class="unit"> ' + o.unit + '</span>';
            }
            function fmtPointDate(ts, rangeId) {
              const d = new Date(ts * 1000);
              if (rangeId === 'last24Hours') return d.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' });
              return d.toLocaleDateString(locale, { month: 'short', day: 'numeric' });
            }
            function eventsForRange(rangeId) {
              const end = new Date(payload.generatedAt).getTime();
              const windowMs = RANGE_WINDOW_MS[rangeId] || RANGE_WINDOW_MS.lastMonth;
              const start = end - windowMs;
              return (payload.events || []).filter(ev => {
                const ts = ev.timestamp * 1000;
                return ts >= start && ts <= end;
              });
            }

            // ===== Per-card metrics =====
            function metricsOf(m) {
              if (m.kind === 'network') return { dual: true, items: [
                { label: L.download, val: bytes(m.totalBytesIn), lead: true },
                { label: L.upload, val: bytes(m.totalBytesOut), lead: false }
              ]};
              if (m.kind === 'storage') return { dual: true, items: [
                { label: L.read, val: bytes(m.totalBytesRead), lead: true },
                { label: L.write, val: bytes(m.totalBytesWritten), lead: false }
              ]};
              if (m.kind === 'power') return { dual: false, items: [
                { label: L.avg, val: pct(m.avgPower != null ? m.avgPower : m.avg, m.kind), lead: true },
                { label: L.peak, val: pct(m.peak, m.kind), lead: false },
                { label: L.median, val: pct(m.median, m.kind), lead: false }
              ]};
              return { dual: false, items: [
                { label: L.avg, val: pct(m.avg, m.kind), lead: true },
                { label: L.peak, val: pct(m.peak, m.kind), lead: false },
                { label: L.median, val: pct(m.median, m.kind), lead: false }
              ]};
            }

            // ===== Percentiles =====
            function percentiles(values) {
              if (!values.length) return { p50: 0, p90: 0, p95: 0 };
              const s = values.slice().sort((a, b) => a - b);
              function q(p) { const i = p * (s.length - 1); const lo = Math.floor(i);
                return s[lo] * (1 - (i - lo)) + (s[Math.min(lo + 1, s.length - 1)] || s[lo]) * (i - lo); }
              return { p50: q(0.5), p90: q(0.9), p95: q(0.95) };
            }

            // ===== Executive Summary =====
            function renderInsights(range) {
              const el = document.getElementById('insights');
              const mods = range.modules || [];
              const hs = range.healthScore;

              // Check if any module has actual data
              const hasData = mods.some(m => m.points.length > 0);

              // Overall load (weighted + softmax, same as main panel)
              const loadMods = mods.filter(m => ['cpu','gpu','memory'].includes(m.kind));
              const cpuAvg = (mods.find(m => m.kind === 'cpu') || {avg: 0}).avg;
              const gpuAvg = (mods.find(m => m.kind === 'gpu') || {avg: 0}).avg;
              const memAvg = (mods.find(m => m.kind === 'memory') || {avg: 0}).avg;
              const rawScore = Math.min(Math.max(cpuAvg * 0.5 + gpuAvg * 0.3 + memAvg * 0.2, 0), 99.9) / 100;
              const boosted = Math.pow(rawScore, 1.3);
              const overallLoad = rawScore > 0 ? (boosted / (boosted + Math.pow(1 - rawScore, 1.3))) * 100 : 0;

              // Key metrics panel (only when data exists)
              let metricsHTML = '';
              if (hasData) {
                const loadColor = overallLoad > 70 ? (isDark ? '#ff6961' : '#d94848') : overallLoad > 40 ? (isDark ? '#ffb340' : '#d4a843') : (isDark ? '#5be17b' : '#2f9e64');
                metricsHTML += '<div style="margin-bottom:12px"><div style="font-size:36px;font-weight:700;font-variant-numeric:tabular-nums;color:' + loadColor + '">' + overallLoad.toFixed(1) + '%</div></div>';
                loadMods.forEach(m => {
                  const c = accentOf(m.kind);
                  metricsHTML += '<div class="insight-load-item"><span class="il-name">' + m.title + '</span>' +
                    '<span class="il-bar"><span class="il-bar-fill" style="width:' + Math.min(m.avg, 100) + '%;background:' + c + '"></span></span>' +
                    '<span class="il-val" style="color:' + c + '">' + m.avg.toFixed(1) + '%</span></div>';
                });
              } else {
                metricsHTML = '<div style="color:var(--text-faint);font-size:13px;padding:20px 0">' + L.empty + '</div>';
              }

              // Insights (only when data exists)
              const insights = [];
              if (hasData) {
                if (overallLoad > 70) insights.push(L.insightLoadHigh.replace('{value}', overallLoad.toFixed(0)));
                else if (overallLoad > 40) insights.push(L.insightLoadMedium.replace('{value}', overallLoad.toFixed(0)));
                else insights.push(L.insightLoadLow.replace('{value}', overallLoad.toFixed(0)));

                let peakMod = null, peakVal = 0;
                mods.forEach(m => { if (m.peak > peakVal && m.kind !== 'network' && m.kind !== 'storage') { peakVal = m.peak; peakMod = m; } });
                if (peakMod) {
                  const peakPt = peakMod.points.reduce((best, p) => p.peak > best.peak ? p : best, peakMod.points[0]);
                  const peakTime = new Date(peakPt.timestamp * 1000).toLocaleString(locale, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
                  insights.push(L.insightPeak.replace('{module}', peakMod.title).replace('{value}', peakVal.toFixed(1) + '%').replace('{time}', peakTime));
                }

                let busiest = null, busiestAvg = 0;
                mods.forEach(m => { if (m.avg > busiestAvg && m.kind !== 'network' && m.kind !== 'storage') { busiestAvg = m.avg; busiest = m; } });
                if (busiest && busiestAvg > 30) insights.push(L.insightBusiest.replace('{module}', busiest.title).replace('{value}', busiestAvg.toFixed(1)));

                if (hs && hs.isDataAvailable) {
                  const lvl = hs.level || levelOf(hs.score);
                  insights.push(L.insightHealthScore.replace('{score}', Math.round(hs.score)).replace('{level}', LEVEL_LABELS[lvl] || lvl));
                  if (hs.thermalCapped) insights.push(L.insightThermal);
                }

                const severeEvents = eventsForRange(range.id).filter(e => e.severity >= 2);
                if (severeEvents.length > 0) insights.push(L.insightSevereEvents.replace('{count}', severeEvents.length));
              }

              const insightsHTML = '<ul>' + insights.map(i => '<li>' + i + '</li>').join('') + '</ul>';

              // Score panel with ring + sub-dimensions
              let scoreHTML = '';
              if (hs && hs.isDataAvailable) {
                const lvl = hs.level || levelOf(hs.score);
                const lColor = LEVEL_COLORS[lvl] || '#5856d6';
                const circ = 2 * Math.PI * 36;
                const off = circ * (1 - Math.min(hs.score, 100) / 100);
                // Sub-dimension badges
                let dimDots = '';
                (hs.dimensions || []).forEach(d => {
                  if (d.isAvailable === false) return;
                  const dc = LEVEL_COLORS[d.level] || LEVEL_COLORS.good;
                  dimDots += '<span class="score-badge" style="color:' + dc + ';border-color:' + dc + '">' +
                    '<span class="score-badge-dot" style="background:' + dc + '"></span>' + d.name + '</span>';
                });
                const cappedBadge = hs.thermalCapped ? '<div class="score-capped">⚠ ' + L.healthThermalCapped + '</div>' : '';
                scoreHTML =
                  '<div class="score-ring-wrap">' +
                    '<svg viewBox="0 0 80 80">' +
                      '<circle cx="40" cy="40" r="36" fill="none" stroke="var(--bg-inset)" stroke-width="6"/>' +
                      '<circle cx="40" cy="40" r="36" fill="none" stroke="' + lColor + '" stroke-width="6" stroke-linecap="round" ' +
                        'stroke-dasharray="' + circ.toFixed(1) + '" stroke-dashoffset="' + off.toFixed(1) + '" ' +
                        'style="transform:rotate(-90deg);transform-origin:center"/>' +
                    '</svg>' +
                    '<div class="score-ring-text">' +
                      '<span class="big-score" style="color:' + lColor + '">' + Math.round(hs.score) + '</span>' +
                    '</div>' +
                  '</div>' +
                  '<div class="score-label" style="color:' + lColor + '">' + (LEVEL_LABELS[lvl] || lvl) + '</div>' +
                  cappedBadge +
                  '<div class="score-dots">' + dimDots + '</div>';
              } else {
                scoreHTML = '<div class="big-score" style="color:var(--text-faint)">--</div>' +
                  '<div class="score-label">' + L.healthNoData + '</div>';
              }

              // Heatmap
              const heatmapHTML = buildHeatmap(mods);

              // Hide entire section when no data at all
              if (!hasData && !(hs && hs.isDataAvailable)) {
                el.innerHTML = '';
                return;
              }

              const insightsListHTML = insights.length ? '<div class="insight-list"><h3>' + L.keyInsights + '</h3>' + insightsHTML + '</div>' : '';
              el.innerHTML = '<h2>' + L.summaryTitle + '</h2>' +
                '<div class="insight-grid">' +
                  '<div class="insight-score">' + scoreHTML + '</div>' +
                  '<div class="insight-load"><h3>' + L.moduleLoad + '</h3>' + metricsHTML + '</div>' +
                  insightsListHTML +
                '</div>' +
                heatmapHTML;
            }

            // ===== Heatmap (7×24 grid, per module, tabbed) =====
            function buildHeatmap(mods) {
              const heatMods = mods.filter(m => m.points.length > 0 && m.kind !== 'network' && m.kind !== 'storage');
              if (!heatMods.length) return '';

              const dayLabels = [L.daySun, L.dayMon, L.dayTue, L.dayWed, L.dayThu, L.dayFri, L.daySat];
              const hourRow = '<div class="heatmap-hour-row"><span></span>' +
                Array.from({length:24}, (_, i) =>
                  '<span style="' + ([0,6,12,18].includes(i) ? '' : 'visibility:hidden') + '">' + i + '</span>'
                ).join('') + '</div>';

              // Tab buttons
              let tabs = '<div class="segmented heatmap-tabs">';
              heatMods.forEach((m, i) => {
                tabs += '<button data-kind="' + m.kind + '" class="' + (i === 0 ? 'active' : '') + '" style="font-size:12px">' + m.title + '</button>';
              });
              tabs += '</div>';

              // Sections (hidden except first)
              let sections = '';
              heatMods.forEach((m, i) => {
                const heat = Array.from({length: 7}, () => Array(24).fill(0));
                const counts = Array.from({length: 7}, () => Array(24).fill(0));
                m.points.forEach(p => {
                  const d = new Date(p.timestamp * 1000);
                  const day = d.getDay(), hour = d.getHours();
                  heat[day][hour] += p.avg;
                  counts[day][hour]++;
                });
                let maxVal = 1;
                for (let d = 0; d < 7; d++) for (let h = 0; h < 24; h++) {
                  if (counts[d][h] > 0) { heat[d][h] /= counts[d][h]; }
                  if (heat[d][h] > maxVal) maxVal = heat[d][h];
                }
                const hue = m.kind === 'cpu' ? 210 : m.kind === 'gpu' ? 140 : m.kind === 'memory' ? 35 : 270;
                let rows = '';
                for (let d = 0; d < 7; d++) {
                  rows += '<div class="heatmap-row"><span class="heatmap-day-label">' + dayLabels[d] + '</span>';
                  for (let h = 0; h < 24; h++) {
                    const intensity = counts[d][h] > 0 ? heat[d][h] / maxVal : 0;
                    const bg = intensity === 0 ? '' :
                      'background:hsla(' + hue + ',80%,' + (isDark ? (35 + 30 * intensity) : (65 - 35 * intensity)) + '%,' + (0.25 + 0.7 * intensity) + ')';
                    const valText = counts[d][h] > 0 ? heat[d][h].toFixed(1) + (m.kind === 'power' ? 'W' : '%') : '--';
                    rows += '<div class="heatmap-cell" style="' + bg + '" data-day="' + d + '" data-hour="' + h + '" data-val="' + valText + '" data-count="' + counts[d][h] + '" data-kind="' + m.kind + '"></div>';
                  }
                  rows += '</div>';
                }
                const vis = i === 0 ? '' : 'display:none';
                sections += '<div class="heatmap-section" data-kind="' + m.kind + '" style="' + vis + '">' +
                  '<div class="heatmap-grid-wrap">' + hourRow +
                    '<div class="heatmap-rows">' + rows + '</div>' +
                  '</div>' +
                '</div>';
              });

              return '<div class="heatmap-wrap"><h3>' + L.heatmapTitle + '</h3>' +
                '<p class="heatmap-desc">' + L.heatmapDescription + '</p>' +
                tabs + sections +
                '<div class="heatmap-legend"><span>' + L.heatmapLow + '</span>' +
                  [0, 0.25, 0.5, 0.75, 1].map(v => {
                    const bg = v === 0 ? 'background:var(--bg-inset)' :
                      'background:hsla(210,80%,' + (isDark ? (35 + 30 * v) : (65 - 35 * v)) + '%,' + (0.25 + 0.7 * v) + ')';
                    return '<div class="heatmap-cell" style="' + bg + '"></div>';
                  }).join('') +
                  '<span>' + L.heatmapHigh + '</span></div>' +
                '<div class="heatmap-tip"></div>' +
              '</div>';
            }

            function initHeatmapTooltip() {
              const wrap = document.querySelector('.heatmap-wrap');
              if (!wrap) return;
              const tip = wrap.querySelector('.heatmap-tip');
              const dayLabels = [L.daySun, L.dayMon, L.dayTue, L.dayWed, L.dayThu, L.dayFri, L.daySat];

              // Tab switching
              wrap.querySelectorAll('.heatmap-tabs button').forEach(btn => {
                btn.onclick = () => {
                  wrap.querySelectorAll('.heatmap-tabs button').forEach(b => b.classList.remove('active'));
                  btn.classList.add('active');
                  const kind = btn.dataset.kind;
                  wrap.querySelectorAll('.heatmap-section[data-kind]').forEach(s => {
                    s.style.display = s.dataset.kind === kind ? '' : 'none';
                  });
                };
              });

              // Tooltip
              wrap.addEventListener('mousemove', function(ev) {
                const cell = ev.target.closest('.heatmap-cell[data-day]');
                if (!cell || !tip) { if (tip) tip.style.opacity = 0; return; }
                const d = +cell.dataset.day, h = +cell.dataset.hour;
                const val = cell.dataset.val;
                const count = cell.dataset.count || '0';
                const range = String(h).padStart(2, '0') + ':00-' + String(h).padStart(2, '0') + ':59';
                tip.innerHTML = '<b>' + dayLabels[d] + ' ' + range + '</b><br>' + L.heatmapAvg + ' ' + val + '<br>' + L.samples + ' ' + count;
                const rect = cell.getBoundingClientRect();
                tip.style.left = (rect.left + rect.width / 2) + 'px';
                tip.style.top = (rect.top - 8) + 'px';
                tip.style.opacity = 1;
              });
              wrap.addEventListener('mouseleave', function() { tip.style.opacity = 0; });
            }

            // ===== Histogram =====
            function buildHistogram(container, m) {
              if (!m.points.length) return;
              const vals = m.points.map(p => p.avg);
              const lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals);
              const bucketCount = 12;
              const range = hi - lo || 1;
              const bucketW = range / bucketCount;
              const buckets = new Array(bucketCount).fill(0);
              vals.forEach(v => { const b = Math.min(Math.floor((v - lo) / bucketW), bucketCount - 1); buckets[b]++; });
              const maxB = Math.max.apply(null, buckets);
              const color = container.style.getPropertyValue('--accent-c').trim() || accentOf(m.kind);

              const W = 600, H = 130, PAD_L = 8, PAD_R = 8, PAD_T = 10, PAD_B = 22;
              const innerW = W - PAD_L - PAD_R, innerH = H - PAD_T - PAD_B;
              const barW = (innerW / bucketCount) - 2;

              let bars = '';
              buckets.forEach((count, i) => {
                const barH = maxB > 0 ? (count / maxB) * innerH : 0;
                const x = PAD_L + i * (innerW / bucketCount) + 1;
                const y = PAD_T + innerH - barH;
                const pctLabel = (count / vals.length * 100).toFixed(0) + '%';
                bars += '<rect class="hist-bar" x="' + x.toFixed(1) + '" y="' + y.toFixed(1) + '" ' +
                  'width="' + barW.toFixed(1) + '" height="' + barH.toFixed(1) + '" ' +
                  'fill="' + color + '" opacity="0.7" data-pct="' + pctLabel + '" ' +
                  'data-range="' + (lo + i * bucketW).toFixed(1) + '-' + (lo + (i+1) * bucketW).toFixed(1) + '"/>';
              });

              // X-axis labels (every 3rd bucket)
              let labels = '';
              for (let i = 0; i <= bucketCount; i += 3) {
                const x = PAD_L + i * (innerW / bucketCount);
                const val = lo + i * bucketW;
                labels += '<text class="hist-label" x="' + x.toFixed(1) + '" y="' + (H - 4) + '" text-anchor="middle">' +
                  (m.kind === 'power' ? val.toFixed(0) + 'W' : val.toFixed(0) + '%') + '</text>';
              }

              const svgEl = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
              svgEl.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
              svgEl.setAttribute('preserveAspectRatio', 'none');
              svgEl.innerHTML = bars + labels;

              const wrap = document.createElement('div');
              wrap.className = 'hist-wrap';
              wrap.style.cssText = 'position:relative;height:130px;margin:6px -6px 0;border-radius:10px;padding:10px 8px 4px';
              wrap.appendChild(svgEl);

              const tip = document.createElement('div');
              tip.className = 'hist-tooltip';
              wrap.appendChild(tip);

              wrap.addEventListener('mousemove', function(ev) {
                const rect = svgEl.getBoundingClientRect();
                const relX = (ev.clientX - rect.left) / rect.width;
                const bucketIdx = Math.floor((relX * W - PAD_L) / (innerW / bucketCount));
                if (bucketIdx >= 0 && bucketIdx < bucketCount && buckets[bucketIdx] > 0) {
                  const barEl = svgEl.querySelectorAll('.hist-bar')[bucketIdx];
                  const rangeText = barEl.getAttribute('data-range');
                  const pctText = barEl.getAttribute('data-pct');
                  tip.innerHTML = rangeText + '<br><b>' + buckets[bucketIdx] + '</b> ' + L.samples + ' (' + pctText + ')';
                  tip.style.left = ((PAD_L + bucketIdx * (innerW / bucketCount) + innerW / bucketCount / 2) / W * 100) + '%';
                  tip.style.top = ((PAD_T + innerH - (buckets[bucketIdx] / maxB * innerH)) / H * 100) + '%';
                  tip.style.opacity = 1;
                } else {
                  tip.style.opacity = 0;
                }
              });
              wrap.addEventListener('mouseleave', function() { tip.style.opacity = 0; });

              container.appendChild(wrap);
            }

            // ===== Chart =====
            const W = 600, H = 156, PAD_L = 8, PAD_R = 8, PAD_T = 14, PAD_B = 18;

            function buildChart(card, m, rangeId) {
              const host = card.querySelector('.chart');
              if (!m.points.length) {
                host.outerHTML = '<div class="empty">' + L.empty + '</div>';
                return;
              }
              const color = card.style.getPropertyValue('--accent-c').trim() || accentOf(m.kind);
              const pts = m.points;
              const isDual = m.kind === 'network' || m.kind === 'storage';

              if (isDual) {
                // 双线图：网络(下载/上传) 或 存储(读取/写入) — 累计流量趋势
                const key1 = m.kind === 'network' ? 'bytesIn' : 'bytesRead';
                const key2 = m.kind === 'network' ? 'bytesOut' : 'bytesWritten';
                const label1 = m.kind === 'network' ? L.download : L.read;
                const label2 = m.kind === 'network' ? L.upload : L.write;
                // 累加成累计值
                const cum1 = [], cum2 = [];
                let s1 = 0, s2 = 0;
                for (let i = 0; i < pts.length; i++) {
                  s1 += (pts[i][key1] || 0);
                  s2 += (pts[i][key2] || 0);
                  cum1.push(s1);
                  cum2.push(s2);
                }
                let lo = 0, hi = Math.max(Math.max.apply(null, cum1), Math.max.apply(null, cum2));
                if (hi < 1) hi = 1;
                const pad = hi * 0.12; hi += pad;

                const innerW = W - PAD_L - PAD_R, innerH = H - PAD_T - PAD_B;
                const X = i => PAD_L + (pts.length === 1 ? innerW / 2 : innerW * i / (pts.length - 1));
                const Y = v => PAD_T + innerH * (1 - (v - lo) / (hi - lo));

                const lineFromArr = arr => arr.map((v, i) => (i ? 'L' : 'M') + X(i).toFixed(1) + ' ' + Y(v).toFixed(1)).join(' ');
                const area1 = lineFromArr(cum1) + ' L' + X(pts.length - 1).toFixed(1) + ' ' + (PAD_T + innerH) + ' L' + X(0).toFixed(1) + ' ' + (PAD_T + innerH) + ' Z';

                let grid = '';
                for (let t = 0; t <= 2; t++) {
                  const val = lo + (hi - lo) * t / 2;
                  const y = Y(val).toFixed(1);
                  const b = bytes(val);
                  grid += '<line class="gridline" x1="' + PAD_L + '" y1="' + y + '" x2="' + (W - PAD_R) + '" y2="' + y + '"/>';
                  grid += '<text class="axis-label" x="' + (W - PAD_R) + '" y="' + (y - 4) + '" text-anchor="end">' + b.num + ' ' + b.unit + '</text>';
                }

                const gid = 'g_' + m.kind + '_' + rangeId;
                const strokeColor1 = m.kind === 'network' ? '#0a84ff' : '#0a84ff';
                const strokeColor2 = m.kind === 'network' ? '#30d158' : '#ff9500';
                host.innerHTML =
                  '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
                    '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
                      '<stop offset="0" stop-color="' + strokeColor1 + '" stop-opacity="0.18"/>' +
                      '<stop offset="1" stop-color="' + strokeColor1 + '" stop-opacity="0"/>' +
                    '</linearGradient></defs>' +
                    grid +
                    '<path d="' + area1 + '" fill="url(#' + gid + ')"/>' +
                    '<path d="' + lineFromArr(cum2) + '" fill="none" stroke="' + strokeColor2 + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
                    '<path d="' + lineFromArr(cum1) + '" fill="none" stroke="' + strokeColor1 + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
                    '<line class="cursor-line" y1="' + PAD_T + '" y2="' + (PAD_T + innerH) + '"/>' +
                    '<circle class="cursor-dot" r="4" fill="' + strokeColor1 + '" stroke="var(--bg-elev)" stroke-width="2.2"/>' +
                  '</svg>' +
                  '<div class="tooltip"></div>';

                const svg = host.querySelector('svg');
                const cursor = host.querySelector('.cursor-line');
                const cdot = host.querySelector('.cursor-dot');
                const tip = host.querySelector('.tooltip');

                function move(ev) {
                  const r = svg.getBoundingClientRect();
                  const rel = (ev.clientX - r.left) / r.width;
                  let idx = pts.length === 1 ? 0 : Math.round(rel * (pts.length - 1));
                  idx = Math.max(0, Math.min(pts.length - 1, idx));
                  const xUser = X(idx), yUser = Y(cum1[idx]);
                  cursor.setAttribute('x1', xUser); cursor.setAttribute('x2', xUser); cursor.style.opacity = 1;
                  cdot.setAttribute('cx', xUser); cdot.setAttribute('cy', yUser); cdot.style.opacity = 1;
                  tip.style.left = (xUser / W * 100) + '%';
                  tip.style.top = (yUser / H * 100) + '%';
                  tip.innerHTML =
                    '<div class="t-date">' + fmtPointDate(pts[idx].timestamp, rangeId) + '</div>' +
                    label1 + ' <b>' + withUnit(bytes(cum1[idx])) + '</b> · ' +
                    label2 + ' <b>' + withUnit(bytes(cum2[idx])) + '</b>';
                  tip.style.opacity = 1;
                }
                function leave() { cursor.style.opacity = 0; cdot.style.opacity = 0; tip.style.opacity = 0; }
                host.addEventListener('mousemove', move);
                host.addEventListener('mouseleave', leave);
              } else {
                // 单线图：avg/peak（CPU/GPU/内存/功耗）
                const lows = pts.map(p => p.low), peaks = pts.map(p => p.peak);
                let lo = Math.min.apply(null, lows), hi = Math.max.apply(null, peaks);
                if (m.kind !== 'power') { lo = Math.min(lo, 0); hi = Math.max(hi, 1); }
                if (hi - lo < 1e-6) { hi = lo + 1; }
                const pad = (hi - lo) * 0.12; lo -= pad * 0.3; hi += pad;

                const innerW = W - PAD_L - PAD_R, innerH = H - PAD_T - PAD_B;
                const X = i => PAD_L + (pts.length === 1 ? innerW / 2 : innerW * i / (pts.length - 1));
                const Y = v => PAD_T + innerH * (1 - (v - lo) / (hi - lo));

                const line = key => pts.map((p, i) => (i ? 'L' : 'M') + X(i).toFixed(1) + ' ' + Y(p[key]).toFixed(1)).join(' ');
                const area = line('avg') + ' L' + X(pts.length - 1).toFixed(1) + ' ' + (PAD_T + innerH) + ' L' + X(0).toFixed(1) + ' ' + (PAD_T + innerH) + ' Z';

                let grid = '';
                for (let t = 0; t <= 2; t++) {
                  const val = lo + (hi - lo) * t / 2;
                  const y = Y(val).toFixed(1);
                  grid += '<line class="gridline" x1="' + PAD_L + '" y1="' + y + '" x2="' + (W - PAD_R) + '" y2="' + y + '"/>';
                  grid += '<text class="axis-label" x="' + (W - PAD_R) + '" y="' + (y - 4) + '" text-anchor="end">' +
                    (m.kind === 'power' ? val.toFixed(0) + 'W' : val.toFixed(0) + '%') + '</text>';
                }

                const gid = 'g_' + m.kind + '_' + rangeId;
                // Peak annotation
                let peakAnno = '';
                if (pts.length > 1) {
                  let peakIdx = 0;
                  for (let i = 1; i < pts.length; i++) { if (pts[i].peak > pts[peakIdx].peak) peakIdx = i; }
                  const pk = pts[peakIdx];
                  const px = X(peakIdx), py = Y(pk.peak);
                  const peakLabel = pk.peak.toFixed(1) + (m.kind === 'power' ? 'W' : '%');
                  peakAnno = '<line x1="' + px.toFixed(1) + '" y1="' + py.toFixed(1) + '" x2="' + px.toFixed(1) + '" y2="' + (PAD_T + innerH) + '" stroke="' + color + '" stroke-width="1" stroke-dasharray="2 2" opacity="0.5"/>' +
                    '<circle cx="' + px.toFixed(1) + '" cy="' + py.toFixed(1) + '" r="3.5" fill="' + color + '" stroke="var(--bg-elev)" stroke-width="1.5"/>' +
                    '<text class="peak-label" x="' + px.toFixed(1) + '" y="' + (py - 8).toFixed(1) + '" text-anchor="middle" fill="' + color + '">' + peakLabel + '</text>';
                }
                host.innerHTML =
                  '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
                    '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
                      '<stop offset="0" stop-color="' + color + '" stop-opacity="0.22"/>' +
                      '<stop offset="1" stop-color="' + color + '" stop-opacity="0"/>' +
                    '</linearGradient></defs>' +
                    grid +
                    '<path d="' + area + '" fill="url(#' + gid + ')"/>' +
                    '<path d="' + line('peak') + '" fill="none" stroke="' + color + '" stroke-width="1.2" stroke-opacity="0.4" stroke-dasharray="3 3" stroke-linecap="round"/>' +
                    '<path d="' + line('avg') + '" fill="none" stroke="' + color + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
                    peakAnno +
                    '<line class="cursor-line" y1="' + PAD_T + '" y2="' + (PAD_T + innerH) + '"/>' +
                    '<circle class="cursor-dot" r="4" fill="' + color + '" stroke="var(--bg-elev)" stroke-width="2.2"/>' +
                  '</svg>' +
                  '<div class="tooltip"></div>';

                const svg = host.querySelector('svg');
                const cursor = host.querySelector('.cursor-line');
                const cdot = host.querySelector('.cursor-dot');
                const tip = host.querySelector('.tooltip');

                function move(ev) {
                  const r = svg.getBoundingClientRect();
                  const rel = (ev.clientX - r.left) / r.width;
                  let idx = pts.length === 1 ? 0 : Math.round(rel * (pts.length - 1));
                  idx = Math.max(0, Math.min(pts.length - 1, idx));
                  const p = pts[idx];
                  const xUser = X(idx), yUser = Y(p.avg);
                  cursor.setAttribute('x1', xUser); cursor.setAttribute('x2', xUser); cursor.style.opacity = 1;
                  cdot.setAttribute('cx', xUser); cdot.setAttribute('cy', yUser); cdot.style.opacity = 1;
                  const suffix = m.kind === 'power' ? ' W' : '%';
                  tip.style.left = (xUser / W * 100) + '%';
                  tip.style.top = (yUser / H * 100) + '%';
                  tip.innerHTML =
                    '<div class="t-date">' + fmtPointDate(p.timestamp, rangeId) + '</div>' +
                    L.avg + ' <b>' + p.avg.toFixed(1) + suffix + '</b> · ' +
                    L.peak + ' <b>' + p.peak.toFixed(1) + suffix + '</b>';
                  tip.style.opacity = 1;
                }
                function leave() { cursor.style.opacity = 0; cdot.style.opacity = 0; tip.style.opacity = 0; }
                host.addEventListener('mousemove', move);
                host.addEventListener('mouseleave', leave);
              }
            }

            // ===== Health Score =====
            const LEVEL_COLORS = {
              excellent: isDark ? '#34c759' : '#2f9e64',
              good: isDark ? '#64d2ff' : '#3bafda',
              fair: isDark ? '#ffd60a' : '#d4a843',
              poor: isDark ? '#ff9f0a' : '#e08e45',
              critical: isDark ? '#ff6961' : '#d94848'
            };
            const LEVEL_LABELS = {
              excellent: L.healthExcellent, good: L.healthGood,
              fair: L.healthFair, poor: L.healthPoor, critical: L.healthCritical
            };
            function levelOf(score) {
              if (score >= 85) return 'excellent';
              if (score >= 70) return 'good';
              if (score >= 50) return 'fair';
              if (score >= 30) return 'poor';
              return 'critical';
            }
            function renderHealth(range) {
              const el = document.getElementById('health');
              const hs = range.healthScore;
              if (!hs) { el.innerHTML = ''; return; }
              if (hs.isDataAvailable === false) {
                el.innerHTML = '<div class="health-card"><div class="health-empty">' +
                  L.healthNoData + '<div class="hint">' + L.healthNoDataHint + '</div></div></div>';
                return;
              }
              const level = hs.level || levelOf(hs.score);
              const color = LEVEL_COLORS[level] || LEVEL_COLORS.good;
              const circumference = 2 * Math.PI * 54;
              const offset = circumference * (1 - Math.min(hs.score, 100) / 100);
              let dimsHTML = '';
              (hs.dimensions || []).forEach(d => {
                if (d.isAvailable === false) return;
                const dc = LEVEL_COLORS[d.level] || LEVEL_COLORS.good;
                const pct = Math.round(d.healthValue * 100);
                dimsHTML += '<div class="health-dim-row">' +
                  '<span class="dim-name">' + d.name + '</span>' +
                  '<span class="dim-bar"><span class="dim-bar-fill" style="width:' + pct + '%;background:' + dc + '"></span></span>' +
                  '<span class="dim-raw">' + (d.rawText || '') + '</span>' +
                  '<span class="dim-val" style="color:' + dc + '">' + pct + '</span>' +
                '</div>';
              });
              const cappedText = hs.thermalCapped ? '<div class="capped">' + L.healthThermalCapped + '</div>' : '';
              // 趋势线
              let trendHTML = '';
              const trend = hs.trend || [];
              if (trend.length >= 2) {
                const w = 600, h = 48, pad = 2;
                const xs = trend.map((_, i) => pad + (w - 2*pad) * i / (trend.length - 1));
                const ys = trend.map(p => pad + (h - 2*pad) * (1 - Math.min(Math.max(p.score,0),100)/100));
                let d = 'M ' + xs[0].toFixed(1) + ' ' + ys[0].toFixed(1);
                for (let i = 1; i < trend.length; i++) { d += ' L ' + xs[i].toFixed(1) + ' ' + ys[i].toFixed(1); }
                trendHTML = '<svg class="health-trend" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">' +
                  '<path class="line" d="' + d + '" stroke="url(#trendGrad)"/>' +
                  '<defs><linearGradient id="trendGrad" x1="0" x2="1"><stop offset="0" stop-color="#2f9e64"/>' +
                  '<stop offset="0.5" stop-color="#d4a843"/><stop offset="1" stop-color="#d94848"/></linearGradient></defs></svg>';
              }
              el.innerHTML = '<div class="health-card">' +
                '<div class="health-ring-wrap">' +
                  '<svg viewBox="0 0 120 120">' +
                    '<circle class="health-ring-bg" cx="60" cy="60" r="54"/>' +
                    '<circle class="health-ring-fg" cx="60" cy="60" r="54" stroke="' + color + '" ' +
                      'stroke-dasharray="' + circumference.toFixed(1) + '" stroke-dashoffset="' + offset.toFixed(1) + '"/>' +
                  '</svg>' +
                  '<div class="health-ring-text">' +
                    '<span class="score" style="color:' + color + '">' + Math.round(hs.score) + '</span>' +
                    '<span class="level" style="color:' + color + '">' + (LEVEL_LABELS[level] || level) + '</span>' +
                    cappedText +
                  '</div>' +
                '</div>' +
                '<div class="health-dims">' + dimsHTML + trendHTML + '</div>' +
              '</div>';
            }

            // ===== Render =====
            function render() {
              const tabs = document.getElementById('tabs');
              tabs.innerHTML = payload.ranges.map(r =>
                '<button role="tab" class="' + (r.id === active ? 'active' : '') + '" data-id="' + r.id + '">' + r.title + '</button>'
              ).join('');
              tabs.querySelectorAll('button').forEach(b => b.onclick = () => { active = b.dataset.id; timelineLimit = 50; render(); });

              const range = payload.ranges.find(r => r.id === active) || payload.ranges[0];
              renderInsights(range);
              initHeatmapTooltip();
              const cards = document.getElementById('cards');
              cards.innerHTML = range.modules.map((m, idx) => {
                const color = accentOf(m.kind);
                const mets = metricsOf(m);
                const metsHTML = mets.items.map(it =>
                  '<div class="metric' + (it.lead ? ' lead' : '') + '">' +
                    '<label>' + it.label + '</label><strong>' + withUnit(it.val) + '</strong></div>'
                ).join('');
                const isDual = m.kind === 'network' || m.kind === 'storage';
                const legend = m.points.length ?
                  '<div class="legend">' +
                    (isDual
                      ? '<span><i style="background:#0a84ff"></i>' + (m.kind === 'network' ? L.download : L.read) + '</span>' +
                        '<span><i style="background:' + (m.kind === 'network' ? '#30d158' : '#ff9500') + '"></i>' + (m.kind === 'network' ? L.upload : L.write) + '</span>'
                      : '<span><i style="background:' + color + '"></i>' + L.avg + '</span>' +
                        '<span><i class="dashed" style="border-color:' + color + '"></i>' + L.peak + '</span>'
                    ) +
                  '</div>' : '';
                // Percentiles
                const pvals = m.points.map(p => p.avg);
                const pcts = percentiles(pvals);
                const pUnit = m.kind === 'power' ? 'W' : '%';
                const pctHTML = m.points.length > 1 ?
                  '<div class="percentiles">' +
                    '<div class="pct-badge"><div class="pct-label">P50</div><div class="pct-val">' + pcts.p50.toFixed(1) + pUnit + '</div></div>' +
                    '<div class="pct-badge"><div class="pct-label">P90</div><div class="pct-val">' + pcts.p90.toFixed(1) + pUnit + '</div></div>' +
                    '<div class="pct-badge"><div class="pct-label">P95</div><div class="pct-val">' + pcts.p95.toFixed(1) + pUnit + '</div></div>' +
                  '</div>' : '';
                return '<article class="card" style="--accent-c:' + color + '">' +
                  '<div class="card-head">' +
                    '<div class="card-icon">' +
                      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">' +
                        iconOf(m.kind) + '</svg>' +
                    '</div>' +
                    '<h2>' + m.title + '</h2>' +
                  '</div>' +
                  '<div class="metrics' + (mets.dual ? ' dual' : '') + '">' + metsHTML + '</div>' +
                  '<div class="card-tabs" data-idx="' + idx + '">' +
                    '<button class="active" data-view="chart">' + L.tabTrend + '</button>' +
                    '<button data-view="hist">' + L.tabDistribution + '</button>' +
                  '</div>' +
                  '<div class="chart" data-view="chart"></div>' +
                  '<div class="hist-container" data-view="hist" style="display:none"></div>' +
                  legend + pctHTML +
                '</article>';
              }).join('');

              // Tab switching
              cards.querySelectorAll('.card-tabs').forEach(tabs => {
                const card = tabs.closest('.card');
                tabs.querySelectorAll('button').forEach(btn => {
                  btn.onclick = () => {
                    tabs.querySelectorAll('button').forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    const view = btn.dataset.view;
                    card.querySelectorAll('.chart, .hist-container').forEach(el => {
                      el.style.display = el.dataset.view === view ? '' : 'none';
                    });
                  };
                });
              });

              const cardEls = cards.querySelectorAll('.card');
              range.modules.forEach((m, i) => {
                buildChart(cardEls[i], m, range.id);
                buildHistogram(cardEls[i].querySelector('.hist-container'), m);
              });

              // ===== Event Timeline =====
              renderTimeline();
            }

            // ===== Event Timeline Rendering =====
            function renderTimeline() {
              const el = document.getElementById('timeline');
              const allEvents = eventsForRange(active);
              if (!allEvents.length) { el.innerHTML = ''; return; }
              const events = allEvents.slice(0, timelineLimit);

              const SEVERITY_ICON = {
                2: '&#9888;', // exclamationmark.triangle
                1: '&#9888;', // exclamationmark.circle
                0: '&#8505;'  // info.circle
              };

              const now = new Date(payload.generatedAt);
              const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
              const yesterdayStart = new Date(todayStart); yesterdayStart.setDate(yesterdayStart.getDate() - 1);

              const groups = new Map();
              events.forEach(ev => {
                const d = new Date(ev.timestamp * 1000);
                let dayKey;
                if (d >= todayStart) {
                  dayKey = L.today;
                } else if (d >= yesterdayStart) {
                  dayKey = L.yesterday;
                } else {
                  dayKey = d.toLocaleDateString(locale, { year: 'numeric', month: 'short', day: 'numeric' });
                }
                if (!groups.has(dayKey)) groups.set(dayKey, []);
                groups.get(dayKey).push(ev);
              });

              let html = '<div class="timeline-section">';
              html += '<h2>' + L.eventTitle + '</h2>';
              html += '<div class="event-count">' + events.length + ' / ' + allEvents.length + ' ' + (L.eventTitle || 'events') + '</div>';

              for (const [day, dayEvents] of groups.entries()) {
                html += '<div class="timeline-day">';
                html += '<div class="timeline-day-label">' + day + '</div>';
                html += '<div class="timeline-events">';
                dayEvents.forEach(ev => {
                  const d = new Date(ev.timestamp * 1000);
                  const timeStr = d.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit' });
                  const sev = ev.severity || 0;
                  html += '<div class="timeline-row severity-' + sev + '">';
                  html += '<span class="event-time">' + timeStr + '</span>';
                  html += '<div class="event-title">' + escapeHtml(ev.title) + '</div>';
                  html += '<div class="event-detail">' + escapeHtml(ev.detail) + '</div>';
                  if (ev.topProcesses && ev.topProcesses.length) {
                    html += '<div class="event-processes">' + L.eventTopProcesses + ': ' + ev.topProcesses.map(escapeHtml).join(', ') + '</div>';
                  }
                  if (ev.duration) {
                    const mins = Math.round(ev.duration / 60);
                    html += '<div class="event-processes">' + (L.eventDuration || 'Duration: {value}').replace('{value}', mins + ' min') + '</div>';
                  }
                  html += '</div>';
                });
                html += '</div></div>';
              }

              if (allEvents.length > events.length) {
                html += '<div class="timeline-more"><button id="timelineMore">' + L.eventShowMore + '</button></div>';
              }
              html += '</div>';
              el.innerHTML = html;
              const more = document.getElementById('timelineMore');
              if (more) more.onclick = () => { timelineLimit += 50; renderTimeline(); };
            }

            function escapeHtml(s) {
              if (!s) return '';
              return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
            }

            render();
          </script>
        </body>
        </html>
        """
    }

    private func htmlLang(from locale: String) -> String {
        let normalized = locale.lowercased()
        if normalized.hasPrefix("zh") { return "zh-Hans" }
        if normalized.hasPrefix("ja") { return "ja" }
        return "en"
    }
}
