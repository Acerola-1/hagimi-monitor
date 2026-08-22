import AppKit
import Darwin
import Foundation
import OSLog

/// 进程/电池维度的报表数据(来自 SwiftData 进程存储)。
struct StatisticsProcessSnapshot {
    /// 行:[日键, 名称下标, cpu%, cpu样本, gpu%, gpu样本, 内存MB, 内存样本, 网络MB, 磁盘MB]
    let appRows: [[Any]]
    let appNames: [String]
    /// 与 appNames 对齐的 base64 PNG(空串 = 无图标)。
    let appIcons: [String]
    /// [日键, 循环次数, 健康度%]
    let batteryDaily: [[Any]]
}

/// 网页报表生成器:从统计库拉取分钟/小时/日三层行,连同元信息与当前语言文案
/// 注入 Bundle 内的 HTML 模板(图表库与图标已内嵌模板),写出单文件报表。
/// 生成在后台线程完成,产物落在应用支持目录,每次打开覆盖同一个文件。
enum StatisticsReportBuilder {
    /// 报表模板与内嵌图表库的资源名。
    private static let templateResource = "ReportTemplate"
    private static let echartsResource = "echarts"

    /// 组装并写出报表文件。可在任意线程调用(内部只做文件与数据库读)。
    static func write(
        snapshot: (minutes: [StatisticsRow], hours: [StatisticsRow], days: [StatisticsRow]),
        meta: [String: Any],
        process: StatisticsProcessSnapshot? = nil
    ) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: templateResource, withExtension: "html"),
              let echartsURL = Bundle.main.url(forResource: echartsResource, withExtension: "min.js") else {
            throw StatisticsReportError.missingResources
        }
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        let echarts = try String(contentsOf: echartsURL, encoding: .utf8)

        // JSON 内联进 <script> 时,"</" 可能提前终结脚本标签,统一转义为合法的 "<\/"。
        // 编码失败(NaN/非 JSON 值混入 payload)抛错走统一的失败上报,不 trap 进程。
        let json: String
        do {
            json = try payloadJSON(snapshot: snapshot, meta: meta, process: process)
        } catch {
            throw StatisticsReportError.encodingFailed(error)
        }
        let escapedJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        let html = template
            .replacingOccurrences(of: "/*__ECHARTS__*/", with: echarts)
            .replacingOccurrences(of: "window.__DATA__ = /*__DATA__*/null;", with: "window.__DATA__ = \(escapedJSON);")
            .replacingOccurrences(of: "__APP_ICON_B64__", with: appIconBase64())
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    /// 应用图标渲染为 128px PNG 的 base64,注入模板品牌位。
    /// 报表是单文件产物,图标需随文件内嵌;128px 覆盖页内最大 58px 展示位的 2x 屏。
    /// 位图绘制为纯数据操作,后台线程安全;失败返回空串,品牌位退化为纯文字。
    private static func appIconBase64() -> String {
        guard let icon = NSImage(named: "AppIcon") else { return "" }
        let size = NSSize(width: 128, height: 128)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return "" }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return png.base64EncodedString()
    }

    /// 报表产物路径:应用支持目录下固定文件名,重复打开即覆盖刷新。
    /// Application Support 目录不可得(沙盒/受管账户极端情形)时退到临时目录,
    /// 与统计库取路径的防御口径一致,不在后台任务里强制解包。
    static var outputURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HagimiMonitor", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("HagimiMonitor-Report.html")
    }

    private static func payloadJSON(
        snapshot: (minutes: [StatisticsRow], hours: [StatisticsRow], days: [StatisticsRow]),
        meta: [String: Any],
        process: StatisticsProcessSnapshot?
    ) throws -> String {
        let columnNames = StatisticsRow.columns.map(\.name)
        var payload: [String: Any] = [
            "generatedAt": Int(Date().timeIntervalSince1970),
            "meta": meta,
            "cols": columnNames,
            "minutes": snapshot.minutes.map { encodeRow($0, columns: columnNames) },
            "hours": snapshot.hours.map { encodeRow($0, columns: columnNames) },
            "days": snapshot.days.map { encodeRow($0, columns: columnNames) },
            "i18n": localizedStrings(),
        ]
        if let process {
            payload["apps"] = ["rows": process.appRows, "names": process.appNames, "icons": process.appIcons]
            payload["batteryDaily"] = process.batteryDaily
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 行编码为 [t, ...列值, n];按列名做精度收敛,控制报表体积。
    private static func encodeRow(_ row: StatisticsRow, columns: [String]) -> [Any] {
        var encoded: [Any] = [row.t]
        for (index, name) in columns.enumerated() {
            if let value = row.values[index] {
                encoded.append(rounded(name, value))
            } else {
                encoded.append(NSNull())
            }
        }
        encoded.append(row.n)
        return encoded
    }

    private static func rounded(_ name: String, _ value: Double) -> Double {
        if name.hasSuffix("_frac") {
            return (value * 10_000).rounded() / 10_000
        }
        if name.hasPrefix("net_") || name.hasPrefix("disk_") || name.hasPrefix("fan_")
            || name.hasPrefix("gpu_mem_") || name.hasPrefix("mem_used_")
            || name.hasPrefix("mem_comp_") || name.hasPrefix("mem_swap_") {
            return value.rounded()
        }
        return (value * 100).rounded() / 100
    }

    // MARK: - 报表文案

    /// 模板 JS 以短键读文案;此处短键 → xcstrings 键(stats.r.*)一一映射,
    /// 三语在 xcstrings 内维护。新增文案两处同步:此列表 + xcstrings。
    private static let stringKeys = [
        "reportTitle", "reportSub", "metaDays", "metaGenerated",
        "rToday", "rWeek", "rMonth", "rYear", "rAll", "applyCustom",
        "kCpu", "kGpu", "kMem", "kMemPressure", "kNetDown", "kNetUp", "kDisk", "kPower",
        "kPeak", "kPeakRate", "kDiskW",
        "secOverview", "secHeatmap", "secCpu", "secCpuPE", "secCpuDist", "secGpu",
        "secGpuDist", "secGpuMem", "secMem", "secNet", "secNetDaily", "secDisk",
        "secDiskDaily", "secPower", "secBatt", "secThermal",
        "secTable", "secInsights",
        "healthTitle", "healthTrend", "healthNoData", "healthCapped",
        "levelExcellent", "levelGood", "levelFair", "levelPoor", "levelCritical",
        "dimCpu", "dimGpu", "dimPressure", "dimThermal",
        "thermalNominal", "thermalFair", "thermalSerious", "thermalCritical",
        "secEvents", "evHint", "evNone", "evMore",
        "evCpuHigh", "evCpuHighDetail", "evPressureHigh", "evPressureDetail",
        "evThermal", "evThermalDetail", "evNetSpike", "evNetDetail",
        "evDiskSpike", "evDiskDetail", "evPowerOnAC", "evPowerOnBattery", "evReboot",
        "secBatteryHealth", "sCycles", "sHealth",
        "secAppsTitle", "appsCpu", "appsMem", "appsGpu", "appsNet", "appsNone",
        "heatLow", "heatHigh", "heatHint", "hourOfDay",
        "granMinute", "granHour", "granDay",
        "sCpu", "sGpu", "sMemPressure", "sMemUsage", "sAvg", "sPeak", "sPerfCore", "sEffCore",
        "sDown", "sUp", "sDiskRead", "sDiskWrite", "sMemUsed", "sMemCompressed",
        "sMemSwap", "sPower", "sBattLevel", "sCpuTemp", "sBattTemp", "sFanRPM",
        "sThermalPressure", "sGpuMem",
        "dist0", "dist1", "dist2", "dist3", "dist4",
        "wd0", "wd1", "wd2", "wd3", "wd4", "wd5", "wd6",
        "colDay", "colCpuAvg", "colCpuPeak", "colMemAvg", "colMemPressure",
        "colNetDown", "colNetUp", "colDiskRead", "colDiskWrite", "colAC",
        "colPowerAvg", "colCoverage",
        "insLoadTitle", "insLoad", "insLoadLow", "insLoadMid", "insLoadHigh",
        "insPeakTitle", "insPeak", "insBusyTitle", "insBusy",
        "insNetTitle", "insNet", "insCoverageTitle", "insCoverage",
        "emptySection", "blankTitle", "blankBody", "footer", "footerLocal",
    ]

    static func localizedStrings() -> [String: String] {
        var strings: [String: String] = [:]
        strings.reserveCapacity(stringKeys.count)
        // 文案键在运行期拼接,必须走 Bundle.localizedString 显式查表:
        // String(localized:) 的动态 LocalizationValue 在源语言进程里不查表、
        // 直接回键本身(实测 zh-Hans 系统上报表满是键名)。
        for key in stringKeys {
            strings[key] = Bundle.main.localizedString(forKey: "stats.r.\(key)", value: nil, table: nil)
        }
        return strings
    }

    /// 从进程存储拉取报表所需的进程/电池数据。
    /// 应用行取近 60 天(与报表小时层窗口一致),日级粒度供网页端按范围聚合。
    static func processSnapshot(from store: StatisticsProcessStore, calendar: Calendar = .current) -> StatisticsProcessSnapshot? {
        let now = Date()
        let fromDay = StatisticsProcessStore.dayKey(now.addingTimeInterval(-59 * 86400), calendar: calendar)
        let toDay = StatisticsProcessStore.dayKey(now, calendar: calendar)

        let identities = store.identities()
        var nameIndex: [String: Int] = [:]
        var names: [String] = []
        var icons: [String] = []
        for identity in identities {
            nameIndex[identity.appKey] = names.count
            names.append(identity.name)
            icons.append(identity.iconPNG?.base64EncodedString() ?? "")
        }

        // 行:[日键, 名称下标, cpu%, cpuN, gpu%, gpuN, 内存MB, 内存N, 下行MB, 上行MB]
        let rows: [[Any]] = store.dailyRows(fromDay: fromDay, toDay: toDay).map { row in
            let index = nameIndex[row.appKey] ?? {
                nameIndex[row.appKey] = names.count
                names.append(row.name)
                icons.append("")
                return names.count - 1
            }()
            return [row.day, index,
                    row.cpuAvg, row.cpuSamples,
                    row.gpuAvg, row.gpuSamples,
                    row.memAvgBytes / 1_048_576, row.memSamples,
                    row.netDownBytes / 1_048_576, row.netUpBytes / 1_048_576] as [Any]
        }

        let battery = store.batteryHistory().map { [$0.day, $0.cycleCount, $0.healthPercent] as [Any] }
        guard !names.isEmpty || !battery.isEmpty else { return nil }
        return StatisticsProcessSnapshot(appRows: rows, appNames: names, appIcons: icons, batteryDaily: battery)
    }

    // MARK: - 元信息

    /// 报告头元信息(设备/机型/系统/覆盖天数)。
    static func meta(days: Int) -> [String: Any] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "device": deviceName(),
            "model": modelName(),
            "os": "macOS \(version.majorVersion).\(version.minorVersion)",
            "days": days,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "direct": isDirect,
        ]
    }

    /// 是否为直连版(Direct):沙盒版拿不到的数据源在此门控。
    private static var isDirect: Bool {
        #if DIRECT_DISTRIBUTION
        return true
        #else
        return false
        #endif
    }

    private static func deviceName() -> String {
        if let name = Host.current().localizedName, !name.isEmpty {
            return name
        }
        let hostName = ProcessInfo.processInfo.hostName
        return hostName.split(separator: ".").first.map(String.init) ?? "Mac"
    }

    private static func modelName() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "Mac"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "Mac"
        }
        return String(cString: buffer)
    }
}

enum StatisticsReportError: LocalizedError {
    case missingResources
    case encodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingResources:
            return "Report template resources are missing from the app bundle"
        case .encodingFailed(let error):
            return "Failed to encode report payload: \(error.localizedDescription)"
        }
    }
}

/// 报表打开流程:设置页按钮与 App 菜单共用。生成在后台执行,
/// 完成后唤起默认浏览器打开本地文件。
@MainActor
enum StatisticsReportFlow {
    private static var isGenerating = false

    static func open(recorder: StatisticsRecorder) {
        guard !isGenerating else { return }
        isGenerating = true
        let snapshotProvider: () -> (minutes: [StatisticsRow], hours: [StatisticsRow], days: [StatisticsRow])? = {
            recorder.reportSnapshot(now: Date())
        }
        let processStore = recorder.processStore
        let meta = StatisticsReportBuilder.meta(days: recorder.recordDays)
        Task.detached(priority: .userInitiated) {
            defer {
                Task { @MainActor in
                    isGenerating = false
                }
            }
            guard let snapshot = snapshotProvider() else { return }
            // 先 flush 进程累加器再取快照,保证报表含当日最新应用数据
            processStore?.flush()
            let process = processStore.map { StatisticsReportBuilder.processSnapshot(from: $0) } ?? nil
            do {
                let url = try StatisticsReportBuilder.write(snapshot: snapshot, meta: meta, process: process)
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            } catch {
                AppLogger.settings.error("Statistics report generation failed: \(String(describing: error), privacy: .public)")
                AppLogStore.shared.error("Statistics report generation failed: \(error.localizedDescription)", category: "settings")
            }
        }
    }
}
