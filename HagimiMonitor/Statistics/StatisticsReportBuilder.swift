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
    /// 日期范围选择用的日期选择库(Flatpickr)及其基础样式,单文件产物需一并内联。
    private static let hardwareSectionResource = "HardwareSection"
    private static let flatpickrResource = "flatpickr"

    /// 报表用到的符号图标:与面板同一批 SF Symbols(面板用 `MonitorKind.symbol`),
    /// 生成时渲染成位图随载荷内联,模板用 mask + currentColor 着色——
    /// 不用手绘 SVG,也不受网页环境拿不到 SF Symbols 字体所限。
    /// (符号名, 模板 CSS 变量后缀)
    private static let reportSymbols: [(name: String, key: String)] = [
        // 模块图标与面板同源(MonitorKind.symbol)
        ("cpu", "cpu"),
        ("display", "gpu"),
        ("memorychip", "mem"),
        ("network", "net"),
        ("internaldrive", "disk"),
        ("powerplug", "power"),
        ("fan.fill", "fan"),
        ("thermometer.medium", "thermal"),
        ("battery.100", "batt"),
        // 报表板块图标
        ("gauge.medium", "health"),
        ("chart.line.uptrend.xyaxis", "trend"),
        ("chart.xyaxis.line", "overview"),
        ("chart.bar.fill", "dist"),
        ("square.grid.3x3", "heatmap"),
        ("heart.text.square", "battHealth"),
        ("exclamationmark.triangle", "alert"),
        ("tablecells", "table"),
        ("sparkles", "insights"),
        ("app.dashed", "apps"),
        ("clock.arrow.circlepath", "legacy"),
        ("arrow.up", "top"),
        // 顶部信息条
        ("laptopcomputer", "device"),
        ("apple.logo", "os"),
        ("display", "display"),
        ("clock", "clock"),
        ("calendar", "calendar"),
    ]

    /// 组装并写出报表文件。可在任意线程调用(内部只做文件与数据库读)。
    static func write(
        snapshot: (minutes: [StatisticsRow], hours: [StatisticsRow], days: [StatisticsRow]),
        meta: [String: Any],
        process: StatisticsProcessSnapshot? = nil,
        hardware: HardwareInventory? = nil
    ) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: templateResource, withExtension: "html"),
              let hardwareCSSURL = Bundle.main.url(forResource: hardwareSectionResource, withExtension: "css"),
              let hardwareJSURL = Bundle.main.url(forResource: hardwareSectionResource, withExtension: "js"),
              let echartsURL = Bundle.main.url(forResource: echartsResource, withExtension: "min.js"),
              let flatpickrJSURL = Bundle.main.url(forResource: flatpickrResource, withExtension: "min.js"),
              let flatpickrCSSURL = Bundle.main.url(forResource: flatpickrResource, withExtension: "min.css") else {
            throw StatisticsReportError.missingResources
        }
        // 硬件模块块的样式与脚本独立成资源,与 ECharts/Flatpickr 同一种内联方式:
        // 模板本体保持干净,改硬件版面不必动那 2600 行。
        let hardwareCSS = try String(contentsOf: hardwareCSSURL, encoding: .utf8)
        let hardwareJS = try String(contentsOf: hardwareJSURL, encoding: .utf8)
        let template = try String(contentsOf: templateURL, encoding: .utf8)
            .replacingOccurrences(of: "/*__HARDWARE_CSS__*/", with: hardwareCSS)
            .replacingOccurrences(of: "/*__HARDWARE_JS__*/", with: hardwareJS)
        let echarts = try String(contentsOf: echartsURL, encoding: .utf8)
        let flatpickrJS = try String(contentsOf: flatpickrJSURL, encoding: .utf8)
        let flatpickrCSS = try String(contentsOf: flatpickrCSSURL, encoding: .utf8)

        // JSON 内联进 <script> 时,"</" 可能提前终结脚本标签,统一转义为合法的 "<\/"。
        // 编码失败(NaN/非 JSON 值混入 payload)抛错走统一的失败上报,不 trap 进程。
        let json: String
        do {
            json = try payloadJSON(snapshot: snapshot, meta: meta, process: process, hardware: hardware)
        } catch {
            throw StatisticsReportError.encodingFailed(error)
        }
        let escapedJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        let html = template
            .replacingOccurrences(of: "/*__SYMBOL_CSS__*/", with: symbolCSSVariables())
            .replacingOccurrences(of: "/*__ECHARTS__*/", with: echarts)
            .replacingOccurrences(of: "/*__FLATPICKR__*/", with: flatpickrJS)
            .replacingOccurrences(of: "/*__FLATPICKR_CSS__*/", with: flatpickrCSS)
            .replacingOccurrences(of: "window.__DATA__ = /*__DATA__*/null;", with: "window.__DATA__ = \(escapedJSON);")
            .replacingOccurrences(of: "__APP_ICON_B64__", with: appIconBase64())
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    /// 应用图标渲染为 256px PNG 的 base64,注入模板品牌位。
    /// 报表是单文件产物,图标需随文件内嵌;256px 覆盖页内最大 58px 展示位的 4x 屏,
    /// 避免 2x 以下在 Retina 放大时发糊。位图绘制为纯数据操作,后台线程安全;
    /// 失败返回空串,品牌位退化为纯文字。
    private static func appIconBase64() -> String {
        guard let icon = NSImage(named: "AppIcon") else { return "" }
        let size = NSSize(width: 256, height: 256)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 256, pixelsHigh: 256,
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

    /// 把用到的 SF Symbols 渲染成 3x 位图,拼成模板的 CSS 变量块(`--i-*`)。
    /// 位图只贡献 alpha(作 mask),颜色交给模板的 currentColor——因此天然跟随
    /// 明暗主题与选中态,不必为两种外观各存一份。渲染失败(符号不存在)跳过,
    /// 模板端该处图标留空,不影响报表其余部分。
    private static func symbolCSSVariables() -> String {
        var lines: [String] = []
        for symbol in reportSymbols {
            guard let png = symbolImageData(symbol.name) else { continue }
            lines.append("--i-\(symbol.key): url(\"data:image/png;base64,\(png.base64EncodedString())\");")
        }
        return ":root {\n    " + lines.joined(separator: "\n    ") + "\n  }"
    }

    /// 单个符号 → 16pt@3x 的 PNG(透明底,字形占 alpha 通道)。
    private static func symbolImageData(_ name: String) -> Data? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let side = 48
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // 按本征比例居中放入方形画布:符号宽度不一,前端 mask 用 contain 呈现
        let natural = symbol.size
        let scale = min(16 / max(natural.width, 1), 16 / max(natural.height, 1))
        let drawSize = NSSize(width: natural.width * scale, height: natural.height * scale)
        symbol.draw(in: NSRect(
            x: (16 - drawSize.width) / 2,
            y: (16 - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        ))
        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
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
        process: StatisticsProcessSnapshot?,
        hardware: HardwareInventory?
    ) throws -> String {
        let columnNames = StatisticsRow.columns.map(\.name)
        var payload: [String: Any] = [
            "generatedAt": Int(Date().timeIntervalSince1970),
            "meta": meta,
            // 评分常量随载荷下发:报表 JS 与 App 端 StatisticsHealthScore 共用同一组
            // 权重、门槛与等级区间,改口径只需改一处,不会两边各写一套数字。
            "scoreModel": [
                "memWeight": StatisticsHealthScore.memWeight,
                "thermalWeight": StatisticsHealthScore.thermalWeight,
                "memoryLevelWeights": StatisticsHealthScore.memoryLevelWeights,
                "thermalLevelWeights": StatisticsHealthScore.thermalLevelWeights,
                "minIntersectionSeconds": StatisticsHealthScore.minIntersectionSeconds,
                "minCoverageRatio": StatisticsHealthScore.minCoverageRatio,
                "lowThreshold": StatisticsHealthScore.lowThreshold,
                "mildThreshold": StatisticsHealthScore.mildThreshold,
                "elevatedThreshold": StatisticsHealthScore.elevatedThreshold,
            ],
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
        // 硬件清单:一次性采集(见 HardwareInventoryReader),随载荷内联。
        // 采集层只带文案 key,这里统一解析成显示文本再下发——前端拿到什么显示什么,
        // 报表语言 = 生成时刻的系统语言(与框架文案的 t() 同一语义)。
        // 缺失值保留成 null 由前端显示 —。
        if let hardware {
            payload["hardware"] = [
                "capturedAt": Int(hardware.capturedAt.timeIntervalSince1970),
                "categories": hardware.categories.map(encodeCategory),
                // 各模块右栏要展示的分组由 App 侧选好,报表只渲染——分组名与其
                // 消费者不再分处两种语言两套文件。
                "rails": hardware.rails.mapValues { $0.map(encodeGroup) },
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 硬件分类编码成前端要的最小结构。缺失值编成 NSNull,前端按「—」渲染——
    /// 不能省略这一行,省略会让「读不到」和「这一项不存在」混为一谈。
    private static func encodeCategory(_ category: HardwareCategory) -> [String: Any] {
        [
            "id": category.id,
            "name": hwText(category.nameKey),
            "subtitle": hwText(category.subtitleKey),
            "groups": category.groups.map(encodeGroup),
        ]
    }

    private static func encodeGroup(_ group: HardwareFactGroup) -> [String: Any] {
        [
            "name": group.name.resolve(hwText),
            "facts": group.facts.map { fact -> [String: Any] in
                ["label": fact.label.resolve(hwText), "value": fact.value ?? NSNull()]
            },
        ] as [String: Any]
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
    /// 两语在 xcstrings 内维护。新增文案两处同步:此列表 + xcstrings。
    private static let stringKeys = [
        "reportTitle", "metaDays", "metaGenerated",
        "kThisMac", "hwCardTitle", "hwNoData", "hwItemCount", "hwMachineSub", "hwCategoryCount",
        "hwLiveGroup", "hwLiveTag",
        "hwLiveCpuUsage", "hwLiveThermal", "hwLiveProcessCount", "hwLiveIdle",
        "hwLiveGpuUsage", "hwLiveGpuMemory", "hwLiveRenderer", "hwLiveTiler",
        "hwLiveMemUsed", "hwLiveCompressed", "hwLiveSwap", "hwLivePressure",
        "hwLiveDiskUsed", "hwLiveDiskFree", "hwLiveDiskRead", "hwLiveDiskWrite",
        "hwLiveDownload", "hwLiveUpload", "hwLiveSignal",
        "hwLiveBatteryLevel", "hwLiveBatteryState", "hwLiveBatteryTemp",
        "rToday", "rWeek", "rMonth", "rYear", "selectRange",
        "rangeLabel", "railEyebrow", "railLocal", "railNet", "railDisk", "railPower",
        "kCpu", "kGpu", "kMem", "kMemPressure", "kNetDown", "kNetUp", "kDisk", "kPower",
        "kPeak", "kPeakRate", "kDiskW",
        "secOverview", "secHeatmap", "secCpu", "secCpuPE", "secCpuDist", "secGpu",
        "secGpuDist", "secGpuMem", "secMem", "secNet", "secNetDaily", "secDisk",
        "secDiskDaily", "secPower", "secBatt", "secThermal",
        "secTable", "secInsights",
        "healthTitle", "healthTrend", "healthNoData",
        "healthInsufficient", "healthLegacy", "healthLegacyRows", "healthWorkload",
        "levelLow", "levelMild", "levelElevated", "levelHigh",
        "dimCpu", "dimGpu", "dimPressure", "dimThermal",
        "thermalNominal", "thermalFair", "thermalSerious", "thermalCritical",
        "memWarning", "memCritical",
        "secEvents", "evHint",
        "alertMem", "alertThermal", "alertOngoing", "alertRecovered", "alertInterrupted",
        "alertNone", "alertIncludes", "alertDetail", "alertDetailPlain",
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

/// 报表内要定位的板块。板块标题与报表模板同源(模板的粘性导航也按标题组织),
/// 报表改版只要标题还在,跳转就继续有效。
enum StatisticsReportAnchor: Sendable {
    case memory
    case thermal

    var sectionTitle: String {
        switch self {
        case .memory: String(localized: "stats.r.secMem")
        case .thermal: String(localized: "stats.r.secThermal")
        }
    }
}

/// 报表打开流程:设置页按钮与 App 菜单共用。生成在后台执行,
/// 完成后唤起默认浏览器打开本地文件。
@MainActor
enum StatisticsReportFlow {
    private static var isGenerating = false

    static func open(recorder: StatisticsRecorder, anchor: StatisticsReportAnchor? = nil) {
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
            // 硬件清单也在这里采集:16 个 system_profiler DataType 本机实测约 2.1 秒,
            // 必须留在后台任务里,绝不上主线程。采集为空(例如极端受限环境)不影响报表,
            // 「本机」模块会在前端按空清单自行隐藏。
            let hardware = HardwareInventoryReader().capture()
            do {
                let url = try StatisticsReportBuilder.write(
                    snapshot: snapshot, meta: meta, process: process, hardware: hardware)
                await MainActor.run {
                    ReportWindowPresenter.open(url: url, anchor: anchor)
                }
            } catch {
                AppLogger.settings.error("Statistics report generation failed: \(String(describing: error), privacy: .public)")
                AppLogStore.shared.error("Statistics report generation failed: \(error.localizedDescription)", category: "settings")
            }
        }
    }
}
