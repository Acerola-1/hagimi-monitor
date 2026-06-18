import Foundation
import SwiftData

struct StatisticsReportPayload: Codable {
    let generatedAt: Date
    let appName: String
    let ranges: [StatisticsReportRangePayload]
}

struct StatisticsReportRangePayload: Codable {
    let id: String
    let title: String
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
        StatisticsReportPayload(
            generatedAt: now(),
            appName: "HagimiMonitor",
            ranges: Self.rangeSpecs.map { spec in
                StatisticsReportRangePayload(
                    id: spec.id,
                    title: spec.range.title,
                    modules: Self.kinds.map { kind in
                        let pendingBucket = spec.range == .last24Hours ? pending[kind.rawValue] : nil
                        return modulePayload(from: aggregator.query(kind: kind, range: spec.range, pending: pendingBucket))
                    }
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

    private func modulePayload(from summary: StatisticsSummary) -> StatisticsReportModulePayload {
        StatisticsReportModulePayload(
            kind: summary.kind.rawValue,
            title: summary.kind.title,
            symbol: summary.kind.symbol,
            avg: summary.avg,
            peak: summary.peak,
            low: summary.low,
            median: summary.median,
            totalBytesIn: summary.totalBytesIn,
            totalBytesOut: summary.totalBytesOut,
            totalBytesRead: summary.totalBytesRead,
            totalBytesWritten: summary.totalBytesWritten,
            avgPower: summary.avgPower,
            points: summary.points.map { point in
                StatisticsReportPointPayload(timestamp: point.date.timeIntervalSince1970, avg: point.avg, peak: point.peak, low: point.low)
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
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>HagimiMonitor Statistics Report</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { margin: 0; background: #f5f5f7; color: #1d1d1f; }
            main { max-width: 1180px; margin: 0 auto; padding: 32px; }
            header { display: flex; justify-content: space-between; gap: 20px; align-items: end; margin-bottom: 20px; }
            h1 { margin: 0; font-size: 32px; letter-spacing: -0.04em; }
            .tabs { display: flex; gap: 6px; padding: 5px; border-radius: 14px; background: #e8e8ed; }
            button { border: 0; border-radius: 10px; padding: 8px 14px; background: transparent; font-weight: 650; cursor: pointer; }
            button.active { background: #007aff; color: white; }
            .grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
            .card { background: rgba(255,255,255,.8); border: 1px solid rgba(0,0,0,.06); border-radius: 20px; padding: 18px; box-shadow: 0 12px 30px rgba(0,0,0,.06); }
            .card h2 { margin: 0 0 12px; font-size: 18px; }
            .metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 12px; }
            label { display: block; color: #86868b; font-size: 12px; margin-bottom: 3px; }
            strong { font-size: 22px; letter-spacing: -0.03em; }
            .accent { color: #5856d6; }
            svg { width: 100%; height: 110px; display: block; }
            .empty { height: 110px; display: grid; place-items: center; color: #86868b; background: #f2f2f7; border-radius: 14px; }
            @media (max-width: 860px) { header { align-items: start; flex-direction: column; } .grid { grid-template-columns: 1fr; } }
            @media (prefers-color-scheme: dark) { body { background: #111113; color: #f5f5f7; } .card { background: rgba(34,34,38,.82); border-color: rgba(255,255,255,.08); } .tabs { background: #2c2c2e; } .empty { background: #1c1c1e; } }
          </style>
        </head>
        <body>
          <main>
            <header><div><h1>HagimiMonitor Statistics Report</h1><p id="generated"></p></div><nav class="tabs" id="tabs"></nav></header>
            <section class="grid" id="cards"></section>
          </main>
          <script id="payload" type="application/json">\(payloadJSON)</script>
          <script>
            const payload = JSON.parse(document.getElementById('payload').textContent);
            let active = payload.ranges[0]?.id;
            document.getElementById('generated').textContent = new Date(payload.generatedAt).toLocaleString();
            const tabs = document.getElementById('tabs');
            const cards = document.getElementById('cards');
            const labels = { avg: 'Avg', peak: 'Peak', median: 'Median', up: 'Up', down: 'Down', read: 'Read', write: 'Write' };
            function bytes(value) { if (!value) return '--'; const units = ['B','KB','MB','GB','TB']; let n = value, i = 0; while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; } return `${n.toFixed(i >= 3 ? 2 : 1)} ${units[i]}`; }
            function number(value, kind) { if (!Number.isFinite(value)) return '--'; return kind === 'power' ? `${value.toFixed(1)} W` : `${value.toFixed(1)}%`; }
            function path(points) { if (!points.length) return ''; const vals = points.map(p => p.avg); const min = Math.min(...vals, 0); const max = Math.max(...vals, 1); return points.map((p, i) => { const x = points.length === 1 ? 160 : i * (320 / (points.length - 1)); const y = 104 - ((p.avg - min) / Math.max(max - min, 1)) * 98; return `${i ? 'L' : 'M'} ${x.toFixed(1)} ${y.toFixed(1)}`; }).join(' '); }
            function chart(module) { if (!module.points.length) return '<div class="empty">No data</div>'; const d = path(module.points); return `<svg viewBox="0 0 320 110" preserveAspectRatio="none"><path d="${d} L 320 110 L 0 110 Z" fill="rgba(88,86,214,.16)"/><path d="${d}" fill="none" stroke="#5856d6" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>`; }
            function metricHTML(module) { if (module.kind === 'network') return [[labels.up, bytes(module.totalBytesOut)], [labels.down, bytes(module.totalBytesIn)], [labels.peak, number(module.peak, module.kind)]]; if (module.kind === 'storage') return [[labels.read, bytes(module.totalBytesRead)], [labels.write, bytes(module.totalBytesWritten)], [labels.peak, number(module.peak, module.kind)]]; return [[labels.avg, number(module.avgPower || module.avg, module.kind)], [labels.peak, number(module.peak, module.kind)], [labels.median, number(module.median, module.kind)]]; }
            function render() { tabs.innerHTML = payload.ranges.map(r => `<button class="${r.id === active ? 'active' : ''}" data-id="${r.id}">${r.title}</button>`).join(''); const range = payload.ranges.find(r => r.id === active) || payload.ranges[0]; cards.innerHTML = range.modules.map(m => `<article class="card"><h2>${m.title}</h2><div class="metrics">${metricHTML(m).map((item, idx) => `<div><label>${item[0]}</label><strong class="${idx === 0 ? 'accent' : ''}">${item[1]}</strong></div>`).join('')}</div>${chart(m)}</article>`).join(''); tabs.querySelectorAll('button').forEach(b => b.onclick = () => { active = b.dataset.id; render(); }); }
            render();
          </script>
        </body>
        </html>
        """
    }
}
