import Foundation
import SwiftData

struct StatisticsReportPayload: Codable {
    let generatedAt: Date
    let appName: String
    let locale: String
    let strings: StatisticsReportStrings
    let ranges: [StatisticsReportRangePayload]
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
        StatisticsReportPayload(
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
                empty: String(localized: "stats.no-data")
            ),
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
            <section class="grid" id="cards"></section>
            <footer id="footer"></footer>
          </div>
          <script id="payload" type="application/json">\(payloadJSON)</script>
          <script>
            "use strict";
            const payload = JSON.parse(document.getElementById('payload').textContent);
            const L = payload.strings;
            const locale = payload.locale || undefined;
            let active = payload.ranges[0] && payload.ranges[0].id;

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

            // ===== Render =====
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
                return '<article class="card" style="--accent-c:' + color + '">' +
                  '<div class="card-head">' +
                    '<div class="card-icon">' +
                      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">' +
                        iconOf(m.kind) + '</svg>' +
                    '</div>' +
                    '<h2>' + m.title + '</h2>' +
                  '</div>' +
                  '<div class="metrics' + (mets.dual ? ' dual' : '') + '">' + metsHTML + '</div>' +
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

    private func htmlLang(from locale: String) -> String {
        let normalized = locale.lowercased()
        if normalized.hasPrefix("zh") { return "zh-Hans" }
        if normalized.hasPrefix("ja") { return "ja" }
        return "en"
    }
}
