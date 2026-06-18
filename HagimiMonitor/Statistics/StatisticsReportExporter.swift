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
          <title>HagimiMonitor · Statistics</title>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #f5f5f7;
              --bg-elev: rgba(255,255,255,.72);
              --bg-inset: #ececef;
              --text: #1d1d1f;
              --text-dim: #6e6e73;
              --text-faint: #a1a1a6;
              --border: rgba(0,0,0,.08);
              --hairline: rgba(0,0,0,.06);
              --accent: #0a84ff;
              --shadow: 0 1px 2px rgba(0,0,0,.04), 0 12px 32px rgba(0,0,0,.06);
              --c-cpu: #ff453a; --c-gpu: #30d158; --c-memory: #ff9f0a;
              --c-storage: #0a84ff; --c-network: #64d2ff; --c-power: #bf5af2;
              --c-default: #5e5ce6;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #0b0b0d; --bg-elev: rgba(28,28,30,.72); --bg-inset: #1c1c1e;
                --text: #f5f5f7; --text-dim: #98989d; --text-faint: #6e6e73;
                --border: rgba(255,255,255,.1); --hairline: rgba(255,255,255,.08);
                --shadow: 0 1px 2px rgba(0,0,0,.3), 0 12px 32px rgba(0,0,0,.4);
              }
            }
            * { box-sizing: border-box; }
            html { -webkit-font-smoothing: antialiased; }
            body {
              margin: 0; background: var(--bg); color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: 14px; line-height: 1.5;
            }
            .wrap { max-width: 1240px; margin: 0 auto; padding: 40px 28px 64px; }

            header { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: flex-end; gap: 16px 24px; margin-bottom: 28px; }
            .brand { display: flex; align-items: center; gap: 13px; }
            .glyph { width: 40px; height: 40px; border-radius: 11px; flex: none;
              background: linear-gradient(135deg, var(--accent), #5e5ce6);
              display: grid; place-items: center; color: #fff; box-shadow: 0 4px 12px rgba(10,132,255,.35); }
            .glyph svg { width: 22px; height: 22px; }
            h1 { margin: 0; font-size: 26px; font-weight: 700; letter-spacing: -.022em; }
            .sub { margin: 2px 0 0; color: var(--text-dim); font-size: 13px; }

            .segmented { display: inline-flex; padding: 3px; gap: 2px; border-radius: 11px;
              background: var(--bg-inset); border: 1px solid var(--hairline); }
            .segmented button { appearance: none; border: 0; background: transparent; cursor: pointer;
              padding: 7px 15px; border-radius: 8px; font-size: 13px; font-weight: 590; color: var(--text-dim);
              font-family: inherit; letter-spacing: -.01em; transition: color .15s; white-space: nowrap; }
            .segmented button:hover { color: var(--text); }
            .segmented button.active { background: var(--bg-elev); color: var(--text);
              box-shadow: 0 1px 3px rgba(0,0,0,.12); }
            @media (prefers-color-scheme: dark) { .segmented button.active { background: #48484a; } }

            .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px; }
            .card { background: var(--bg-elev); border: 1px solid var(--border); border-radius: 18px;
              padding: 20px 20px 14px; box-shadow: var(--shadow);
              backdrop-filter: saturate(180%) blur(20px); -webkit-backdrop-filter: saturate(180%) blur(20px); }
            .card-head { display: flex; align-items: center; gap: 9px; margin-bottom: 16px; }
            .dot { width: 9px; height: 9px; border-radius: 999px; flex: none; }
            .card-head h2 { margin: 0; font-size: 15px; font-weight: 640; letter-spacing: -.01em; }
            .card-head .badge { margin-left: auto; font-size: 11px; font-weight: 600; color: var(--text-faint);
              background: var(--bg-inset); padding: 3px 8px; border-radius: 6px; }

            .metrics { display: flex; gap: 22px; margin-bottom: 14px; flex-wrap: wrap; }
            .metric label { display: block; color: var(--text-faint); font-size: 11px; font-weight: 600;
              text-transform: uppercase; letter-spacing: .04em; margin-bottom: 2px; }
            .metric strong { font-size: 21px; font-weight: 600; letter-spacing: -.02em;
              font-variant-numeric: tabular-nums; }
            .metric.lead strong { color: var(--accent-c); }

            .chart { position: relative; height: 150px; margin: 4px -4px 0; }
            .chart svg { width: 100%; height: 100%; display: block; overflow: visible; }
            .chart .gridline { stroke: var(--hairline); stroke-width: 1; }
            .chart .axis-label { fill: var(--text-faint); font-size: 9px; font-variant-numeric: tabular-nums; }
            .cursor-line { stroke: var(--text-faint); stroke-width: 1; stroke-dasharray: 3 3; opacity: 0; }
            .cursor-dot { opacity: 0; }
            .tooltip { position: absolute; pointer-events: none; opacity: 0; transform: translate(-50%, -118%);
              background: var(--text); color: var(--bg); padding: 6px 9px; border-radius: 8px;
              font-size: 11px; line-height: 1.45; white-space: nowrap; box-shadow: 0 6px 18px rgba(0,0,0,.25);
              transition: opacity .1s; z-index: 5; }
            .tooltip b { font-variant-numeric: tabular-nums; font-weight: 700; }
            .tooltip .t-date { color: var(--bg); opacity: .6; font-size: 10px; }

            .legend { display: flex; gap: 14px; margin-top: 10px; padding-top: 10px;
              border-top: 1px solid var(--hairline); }
            .legend span { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; color: var(--text-dim); }
            .legend i { width: 14px; height: 2px; border-radius: 2px; display: inline-block; }
            .legend i.dashed { background: none !important; border-top: 2px dashed; }

            .empty { height: 150px; display: grid; place-items: center; color: var(--text-faint);
              background: var(--bg-inset); border-radius: 12px; font-size: 13px; }

            footer { margin-top: 40px; text-align: center; color: var(--text-faint); font-size: 12px; }

            @media (max-width: 560px) {
              .wrap { padding: 28px 16px 48px; }
              header { align-items: flex-start; }
              .grid { grid-template-columns: 1fr; }
              .segmented { overflow-x: auto; max-width: 100%; }
            }
          </style>
        </head>
        <body>
          <div class="wrap">
            <header>
              <div class="brand">
                <div class="glyph"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 16l5-7 4 5 3-4 6 8"/></svg></div>
                <div>
                  <h1>HagimiMonitor</h1>
                  <p class="sub" id="generated"></p>
                </div>
              </div>
              <nav class="segmented" id="tabs" role="tablist"></nav>
            </header>
            <section class="grid" id="cards"></section>
            <footer id="footer"></footer>
          </div>
          <script id="payload" type="application/json">\(payloadJSON)</script>
          <script>
            "use strict";
            const payload = JSON.parse(document.getElementById('payload').textContent);
            let active = payload.ranges[0] && payload.ranges[0].id;

            const ACCENT = {
              cpu: '#ff453a', gpu: '#30d158', memory: '#ff9f0a',
              storage: '#0a84ff', network: '#64d2ff', power: '#bf5af2'
            };
            const accentOf = k => ACCENT[k] || '#5e5ce6';

            const L = {
              avg: 'Average', peak: 'Peak', low: 'Low', median: 'Median',
              up: 'Upload', down: 'Download', read: 'Read', write: 'Written',
              empty: 'No data recorded for this range', samples: 'pts'
            };

            const genDate = new Date(payload.generatedAt);
            document.getElementById('generated').textContent =
              'Statistics report · generated ' + genDate.toLocaleString();
            document.getElementById('footer').textContent =
              payload.appName + ' · report is read-only and reflects data captured up to ' + genDate.toLocaleString();

            function bytes(v) {
              if (!v) return '0 B';
              const u = ['B','KB','MB','GB','TB']; let n = v, i = 0;
              while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
              return n.toFixed(i >= 3 ? 2 : (i === 0 ? 0 : 1)) + ' ' + u[i];
            }
            function num(v, kind) {
              if (!Number.isFinite(v)) return '--';
              return kind === 'power' ? v.toFixed(1) + ' W' : v.toFixed(1) + '%';
            }
            function fmtPointDate(ts, rangeId) {
              const d = new Date(ts * 1000);
              if (rangeId === 'last24Hours') return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
              return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
            }

            // Lead metric per kind: [label, value, isLead]
            function metricsOf(m) {
              if (m.kind === 'network') return [
                [L.down, bytes(m.totalBytesIn), true], [L.up, bytes(m.totalBytesOut), false], [L.peak, num(m.peak, m.kind), false]];
              if (m.kind === 'storage') return [
                [L.read, bytes(m.totalBytesRead), true], [L.write, bytes(m.totalBytesWritten), false], [L.peak, num(m.peak, m.kind), false]];
              if (m.kind === 'power') return [
                [L.avg, num(m.avgPower != null ? m.avgPower : m.avg, m.kind), true], [L.peak, num(m.peak, m.kind), false], [L.median, num(m.median, m.kind), false]];
              return [
                [L.avg, num(m.avg, m.kind), true], [L.peak, num(m.peak, m.kind), false], [L.median, num(m.median, m.kind), false]];
            }

            const W = 600, H = 150, PAD_L = 6, PAD_R = 6, PAD_T = 12, PAD_B = 18;

            function buildChart(card, m, rangeId) {
              const host = card.querySelector('.chart');
              if (!m.points.length) {
                host.outerHTML = '<div class="empty">' + L.empty + '</div>';
                return;
              }
              const color = accentOf(m.kind);
              const pts = m.points;
              const lows = pts.map(p => p.low), peaks = pts.map(p => p.peak);
              let lo = Math.min.apply(null, lows), hi = Math.max.apply(null, peaks);
              if (m.kind !== 'power') { lo = Math.min(lo, 0); hi = Math.max(hi, 1); }
              if (hi - lo < 1e-6) { hi = lo + 1; }
              const pad = (hi - lo) * 0.08; lo -= pad; hi += pad;

              const innerW = W - PAD_L - PAD_R, innerH = H - PAD_T - PAD_B;
              const X = i => PAD_L + (pts.length === 1 ? innerW / 2 : innerW * i / (pts.length - 1));
              const Y = v => PAD_T + innerH * (1 - (v - lo) / (hi - lo));

              const line = key => pts.map((p, i) => (i ? 'L' : 'M') + X(i).toFixed(1) + ' ' + Y(p[key]).toFixed(1)).join(' ');
              const area = line('avg') + ' L' + X(pts.length - 1).toFixed(1) + ' ' + (PAD_T + innerH) + ' L' + X(0).toFixed(1) + ' ' + (PAD_T + innerH) + ' Z';

              // horizontal gridlines + labels (3 ticks)
              let grid = '';
              for (let t = 0; t <= 2; t++) {
                const val = lo + (hi - lo) * t / 2;
                const y = Y(val).toFixed(1);
                grid += '<line class="gridline" x1="' + PAD_L + '" y1="' + y + '" x2="' + (W - PAD_R) + '" y2="' + y + '"/>';
                grid += '<text class="axis-label" x="' + PAD_L + '" y="' + (y - 3) + '">' +
                  (m.kind === 'power' ? val.toFixed(0) + 'W' : val.toFixed(0) + '%') + '</text>';
              }

              const gid = 'g_' + m.kind + '_' + rangeId;
              host.innerHTML =
                '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
                  '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
                    '<stop offset="0" stop-color="' + color + '" stop-opacity="0.26"/>' +
                    '<stop offset="1" stop-color="' + color + '" stop-opacity="0"/>' +
                  '</linearGradient></defs>' +
                  grid +
                  '<path d="' + area + '" fill="url(#' + gid + ')"/>' +
                  '<path d="' + line('peak') + '" fill="none" stroke="' + color + '" stroke-width="1" stroke-opacity="0.4" stroke-dasharray="3 3"/>' +
                  '<path d="' + line('avg') + '" fill="none" stroke="' + color + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
                  '<line class="cursor-line" y1="' + PAD_T + '" y2="' + (PAD_T + innerH) + '"/>' +
                  '<circle class="cursor-dot" r="3.5" fill="' + color + '" stroke="var(--bg-elev)" stroke-width="2"/>' +
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

            function render() {
              const tabs = document.getElementById('tabs');
              tabs.innerHTML = payload.ranges.map(r =>
                '<button role="tab" class="' + (r.id === active ? 'active' : '') + '" data-id="' + r.id + '">' + r.title + '</button>'
              ).join('');
              tabs.querySelectorAll('button').forEach(b => b.onclick = () => { active = b.dataset.id; render(); });

              const range = payload.ranges.find(r => r.id === active) || payload.ranges[0];
              const cards = document.getElementById('cards');
              cards.innerHTML = range.modules.map(m => {
                const color = accentOf(m.kind);
                const mets = metricsOf(m).map(it =>
                  '<div class="metric' + (it[2] ? ' lead' : '') + '" style="--accent-c:' + color + '">' +
                    '<label>' + it[0] + '</label><strong>' + it[1] + '</strong></div>'
                ).join('');
                const badge = m.points.length ? ('<span class="badge">' + m.points.length + ' ' + L.samples + '</span>') : '';
                const legend = m.points.length ?
                  '<div class="legend">' +
                    '<span><i style="background:' + color + '"></i>' + L.avg + '</span>' +
                    '<span><i class="dashed" style="border-color:' + color + '"></i>' + L.peak + '</span>' +
                  '</div>' : '';
                return '<article class="card">' +
                  '<div class="card-head"><span class="dot" style="background:' + color + '"></span>' +
                    '<h2>' + m.title + '</h2>' + badge + '</div>' +
                  '<div class="metrics">' + mets + '</div>' +
                  '<div class="chart"></div>' + legend +
                '</article>';
              }).join('');

              const cardEls = cards.querySelectorAll('.card');
              range.modules.forEach((m, i) => buildChart(cardEls[i], m, range.id));
            }

            render();
          </script>
        </body>
        </html>
        """
    }
}
