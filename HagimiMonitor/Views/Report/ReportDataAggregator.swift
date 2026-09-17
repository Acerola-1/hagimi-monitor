import Foundation

/// 纯 Swift 统计报表数据聚合器。
/// 严格遵循既有统计口径，执行范围筛选、粒度决策、加权平均、分布桶、事件流与洞察计算。
nonisolated enum ReportDataAggregator: Sendable {

    // MARK: - 粒度决策与行过滤

    /// 根据选定时间跨度决定采用的数据粒度（分钟、小时、日）。
    static func pickSource(
        from: Date,
        to: Date,
        minutes: [StatisticsRow],
        hours: [StatisticsRow],
        days: [StatisticsRow]
    ) -> ReportSourceGranularity {
        let span = to.timeIntervalSince(from)
        let daySeconds: TimeInterval = 86400
        if span <= 2 * daySeconds, !minutes.isEmpty, let firstMinute = minutes.first {
            let firstMinuteDate = Date(timeIntervalSince1970: TimeInterval(firstMinute.t))
            if from >= firstMinuteDate.addingTimeInterval(-daySeconds) {
                return .minutes
            }
        }
        if span <= 60 * daySeconds, !hours.isEmpty, let firstHour = hours.first {
            let firstHourDate = Date(timeIntervalSince1970: TimeInterval(firstHour.t))
            if from >= firstHourDate.addingTimeInterval(-daySeconds) {
                return .hours
            }
        }
        if span <= 60 * daySeconds {
            return hours.isEmpty ? .days : .hours
        }
        return .days
    }

    /// 判定指定起止时间跨度是否属于单日（例如今天、昨天或自定义的单个自然日）。
    /// 用于驱动吞吐图表自适应按小时分桶，以及文案自适应。
    static func isSingleDay(from: Date, to: Date, calendar: Calendar = .current) -> Bool {
        let span = to.timeIntervalSince(from)
        guard span > 0 && span <= 86400 + 3600 else { return false }
        let lastMoment = to.addingTimeInterval(-1)
        return calendar.isDate(from, inSameDayAs: lastMoment)
    }

    /// 过滤指定时间范围内的统计行（左闭右开 [from, to)）。
    static func filterRows(_ rows: [StatisticsRow], from: Date, to: Date) -> [StatisticsRow] {
        let fromTs = Int64(from.timeIntervalSince1970)
        let toTs = Int64(to.timeIntervalSince1970)
        return rows.filter { $0.t >= fromTs && $0.t < toTs }
    }

    /// 行的覆盖秒数：优先使用墙钟 coverS，缺失时回退为帧数 n。
    static func coverSeconds(for row: StatisticsRow) -> Double {
        row.coverS ?? Double(row.n)
    }

    /// 选定范围内的有效采样覆盖比例。无行、无效范围或没有有效覆盖时返回 nil，
    /// 避免把“没有采样”误报成 0%。覆盖量允许跨桶累计，但最终封顶到 100%。
    static func coverageRatio(
        rows: [StatisticsRow],
        from: Date,
        to: Date
    ) -> Double? {
        guard !rows.isEmpty else { return nil }
        let span = to.timeIntervalSince(from)
        guard span.isFinite, span > 0 else { return nil }

        let covered = rows.reduce(0.0) { partial, row in
            partial + max(0, coverSeconds(for: row))
        }
        guard covered > 0 else { return nil }
        return min(1, max(0, covered / span))
    }

    // MARK: - 基础统计计算

    /// 帧数加权平均
    static func weightedAverage(of rows: [StatisticsRow], keyPath: KeyPath<StatisticsRow, Double?>) -> Double? {
        var sum = 0.0
        var totalFrames = 0
        for row in rows {
            if let value = row[keyPath: keyPath], row.n > 0 {
                sum += value * Double(row.n)
                totalFrames += row.n
            }
        }
        return totalFrames > 0 ? sum / Double(totalFrames) : nil
    }

    /// 序列最大值
    static func maximum(of rows: [StatisticsRow], keyPath: KeyPath<StatisticsRow, Double?>) -> Double? {
        var maxVal: Double?
        for row in rows {
            if let value = row[keyPath: keyPath] {
                if let current = maxVal {
                    if value > current { maxVal = value }
                } else {
                    maxVal = value
                }
            }
        }
        return maxVal
    }

    /// 序列最大值与其发生时间
    static func maximumWithTime(of rows: [StatisticsRow], keyPath: KeyPath<StatisticsRow, Double?>) -> (value: Double, time: Date)? {
        var maxPair: (value: Double, time: Date)?
        for row in rows {
            if let value = row[keyPath: keyPath] {
                if let current = maxPair {
                    if value > current.value {
                        maxPair = (value, Date(timeIntervalSince1970: TimeInterval(row.t)))
                    }
                } else {
                    maxPair = (value, Date(timeIntervalSince1970: TimeInterval(row.t)))
                }
            }
        }
        return maxPair
    }

    /// 序列求和（累积量）
    static func total(of rows: [StatisticsRow], keyPath: KeyPath<StatisticsRow, Double?>) -> Double? {
        var sum = 0.0
        var hasAny = false
        for row in rows {
            if let value = row[keyPath: keyPath] {
                sum += value
                hasAny = true
            }
        }
        return hasAny ? sum : nil
    }

    /// 从累积字节量和桶时间跨度计算平均速率 (Bytes/sec)
    /// 严格遵循 `ReportTemplate.html:2278` 的 `rateFromTotal` 口径。
    static func rateFromTotal(totalBytes: Double, bucketSeconds: TimeInterval) -> Double {
        guard bucketSeconds > 0 else { return 0 }
        return totalBytes / bucketSeconds
    }

    // MARK: - 曲线断点与时间序列构建 (R07)

    /// 将行序列转换为支持缺口断开的图表时间序列点。
    /// 当相邻两点间隔超过 `granularitySeconds * 1.5` 时分配新 segmentID，避免跨睡眠/关机拉出连线。
    static func buildTimeSeries(
        rows: [StatisticsRow],
        keyPath: KeyPath<StatisticsRow, Double?>,
        seriesID: String,
        granularitySeconds: TimeInterval,
        transform: ((Double) -> Double)? = nil
    ) -> [ReportTimeSeriesPoint] {
        guard !rows.isEmpty else { return [] }
        var points: [ReportTimeSeriesPoint] = []
        var currentSegment = 0
        var lastTime: Int64?

        let maxGap = Int64(granularitySeconds * 1.5)

        for row in rows {
            guard let rawVal = row[keyPath: keyPath] else {
                continue
            }
            if let prev = lastTime, (row.t - prev) > maxGap {
                currentSegment += 1
            }
            lastTime = row.t
            let date = Date(timeIntervalSince1970: TimeInterval(row.t))
            let finalVal = transform?(rawVal) ?? rawVal
            points.append(ReportTimeSeriesPoint(
                id: "\(seriesID)-\(row.t)",
                date: date,
                seriesID: seriesID,
                segmentID: currentSegment,
                value: finalVal
            ))
        }

        return points
    }

    // MARK: - 5 档负载分布计算

    /// 计算指定维度的 5 级时间分布（0~10%, 10~30%, 30~60%, 60~90%, 90%+）
    static func computeDistribution(of rows: [StatisticsRow], keyPath: KeyPath<StatisticsRow, Double?>) -> ReportDistribution? {
        var bucketsSeconds = [0.0, 0.0, 0.0, 0.0, 0.0]
        var totalSeconds = 0.0

        for row in rows {
            guard let val = row[keyPath: keyPath] else { continue }
            let sec = coverSeconds(for: row)
            totalSeconds += sec

            if val < 10.0 {
                bucketsSeconds[0] += sec
            } else if val < 30.0 {
                bucketsSeconds[1] += sec
            } else if val < 60.0 {
                bucketsSeconds[2] += sec
            } else if val < 90.0 {
                bucketsSeconds[3] += sec
            } else {
                bucketsSeconds[4] += sec
            }
        }

        guard totalSeconds > 0 else { return nil }

        let labels = [
            String(localized: "stats.r.dist0", defaultValue: "< 10%"),
            String(localized: "stats.r.dist1", defaultValue: "10-30%"),
            String(localized: "stats.r.dist2", defaultValue: "30-60%"),
            String(localized: "stats.r.dist3", defaultValue: "60-90%"),
            String(localized: "stats.r.dist4", defaultValue: "> 90%")
        ]

        var bucketItems: [ReportDistribution.Bucket] = []
        for i in 0..<5 {
            let sec = bucketsSeconds[i]
            let pct = (sec / totalSeconds) * 100.0
            bucketItems.append(ReportDistribution.Bucket(
                index: i,
                label: labels[i],
                seconds: sec,
                percent: pct,
                hoursText: ReportUIHelper.formatHours(sec)
            ))
        }

        return ReportDistribution(buckets: bucketItems, totalCoverSeconds: totalSeconds)
    }

    // MARK: - 各模块指标计算

    static func computeCpuMetrics(rows: [StatisticsRow]) -> ReportCpuMetrics {
        let avg = weightedAverage(of: rows, keyPath: \.cpuAvg)
        let peakPair = maximumWithTime(of: rows, keyPath: \.cpuMax)
        let sys = weightedAverage(of: rows, keyPath: \.cpuSysAvg)
        let user = weightedAverage(of: rows, keyPath: \.cpuUserAvg)
        let pCore = weightedAverage(of: rows, keyPath: \.cpuPAvg)
        let eCore = weightedAverage(of: rows, keyPath: \.cpuEAvg)
        let dist = computeDistribution(of: rows, keyPath: \.cpuAvg)
        let highS = total(of: rows, keyPath: \.cpuHighS)

        return ReportCpuMetrics(
            avgUsage: avg,
            peakUsage: peakPair?.value,
            peakTime: peakPair?.time,
            sysAvg: sys,
            userAvg: user,
            pCoreAvg: pCore,
            eCoreAvg: eCore,
            distribution: dist,
            highSeconds: highS
        )
    }

    static func computeGpuMetrics(rows: [StatisticsRow]) -> ReportGpuMetrics {
        let avg = weightedAverage(of: rows, keyPath: \.gpuAvg)
        let peak = maximum(of: rows, keyPath: \.gpuMax)
        let mem = weightedAverage(of: rows, keyPath: \.gpuMemAvg)
        let tiler = weightedAverage(of: rows, keyPath: \.gpuTilerAvg)
        let dist = computeDistribution(of: rows, keyPath: \.gpuAvg)
        let highS = total(of: rows, keyPath: \.gpuHighS)

        return ReportGpuMetrics(
            avgUsage: avg,
            peakUsage: peak,
            memUsedAvg: mem,
            tilerAvg: tiler,
            distribution: dist,
            highSeconds: highS
        )
    }

    static func computeMemoryMetrics(rows: [StatisticsRow]) -> ReportMemoryMetrics {
        let used = weightedAverage(of: rows, keyPath: \.memUsedAvg)
        let compressed = weightedAverage(of: rows, keyPath: \.memCompAvg)
        let swap = weightedAverage(of: rows, keyPath: \.memSwapAvg)
        let pressure = weightedAverage(of: rows, keyPath: \.memPressureAvg)
        let usedPeak = maximum(of: rows, keyPath: \.memPctMax)
        let memPct = weightedAverage(of: rows, keyPath: \.memPctAvg)
        let hasSwap = rows.contains { $0.memSwapAvg != nil }

        return ReportMemoryMetrics(
            usedAvgBytes: used,
            compressedAvgBytes: compressed,
            swapAvgBytes: swap,
            pressureAvgPercent: pressure,
            usedPeakPercent: usedPeak,
            memPctAvg: memPct,
            hasSwapData: hasSwap
        )
    }

    static func computeNetworkMetrics(rows: [StatisticsRow], isHourly: Bool, calendar: Calendar = .current) -> ReportNetworkMetrics {
        let totalDown = total(of: rows, keyPath: \.netDown)
        let totalUp = total(of: rows, keyPath: \.netUp)
        let peakDown = maximum(of: rows, keyPath: \.netDownPeak)
        let peakUp = maximum(of: rows, keyPath: \.netUpPeak)

        var dailyBars: [ReportNetworkMetrics.DailyBar] = []
        if isHourly {
            // 当日或单日自适应：按每小时 (Hour) 分组聚合流量吞吐 (R17)
            let grouped = Dictionary(grouping: rows) { row -> Date in
                let date = Date(timeIntervalSince1970: TimeInterval(row.t))
                return calendar.dateInterval(of: .hour, for: date)?.start ?? date
            }
            let sortedHours = grouped.keys.sorted()
            dailyBars = sortedHours.map { hourStart in
                let hourRows = grouped[hourStart] ?? []
                let down = hourRows.compactMap(\.netDown).reduce(0, +)
                let up = hourRows.compactMap(\.netUp).reduce(0, +)
                let hour = calendar.component(.hour, from: hourStart)
                let key = String(format: "%02d:00", hour)
                return ReportNetworkMetrics.DailyBar(
                    id: "\(Int64(hourStart.timeIntervalSince1970))",
                    date: hourStart,
                    dateText: key,
                    downBytes: down,
                    upBytes: up
                )
            }
        } else {
            // 按完整自然日 startOfDay 分组，避免跨年字符倒序与重复合并 (R17)
            let grouped = Dictionary(grouping: rows) { row -> Date in
                let date = Date(timeIntervalSince1970: TimeInterval(row.t))
                return calendar.startOfDay(for: date)
            }
            let sortedDates = grouped.keys.sorted()
            dailyBars = sortedDates.map { dayStart in
                let dayRows = grouped[dayStart] ?? []
                let down = dayRows.compactMap(\.netDown).reduce(0, +)
                let up = dayRows.compactMap(\.netUp).reduce(0, +)
                let key = ReportUIHelper.formatDateShort(dayStart)
                return ReportNetworkMetrics.DailyBar(
                    id: "\(Int64(dayStart.timeIntervalSince1970))",
                    date: dayStart,
                    dateText: key,
                    downBytes: down,
                    upBytes: up
                )
            }
        }

        return ReportNetworkMetrics(
            totalDownBytes: totalDown,
            totalUpBytes: totalUp,
            peakDownRate: peakDown,
            peakUpRate: peakUp,
            dailyBars: dailyBars,
            isHourly: isHourly
        )
    }

    static func computeDiskMetrics(rows: [StatisticsRow], isHourly: Bool, calendar: Calendar = .current) -> ReportDiskMetrics {
        let totalRead = total(of: rows, keyPath: \.diskRead)
        let totalWrite = total(of: rows, keyPath: \.diskWrite)
        let peakRead = maximum(of: rows, keyPath: \.diskReadPeak)
        let peakWrite = maximum(of: rows, keyPath: \.diskWritePeak)

        var dailyBars: [ReportDiskMetrics.DailyBar] = []
        if isHourly {
            // 当日或单日自适应：按每小时 (Hour) 分组聚合磁盘 I/O 吞吐
            let grouped = Dictionary(grouping: rows) { row -> Date in
                let date = Date(timeIntervalSince1970: TimeInterval(row.t))
                return calendar.dateInterval(of: .hour, for: date)?.start ?? date
            }
            let sortedHours = grouped.keys.sorted()
            dailyBars = sortedHours.map { hourStart in
                let hourRows = grouped[hourStart] ?? []
                let r = hourRows.compactMap(\.diskRead).reduce(0, +)
                let w = hourRows.compactMap(\.diskWrite).reduce(0, +)
                let hour = calendar.component(.hour, from: hourStart)
                let key = String(format: "%02d:00", hour)
                return ReportDiskMetrics.DailyBar(
                    id: "\(Int64(hourStart.timeIntervalSince1970))",
                    date: hourStart,
                    dateText: key,
                    readBytes: r,
                    writeBytes: w
                )
            }
        } else {
            let grouped = Dictionary(grouping: rows) { row -> Date in
                let date = Date(timeIntervalSince1970: TimeInterval(row.t))
                return calendar.startOfDay(for: date)
            }
            let sortedDates = grouped.keys.sorted()
            dailyBars = sortedDates.map { dayStart in
                let dayRows = grouped[dayStart] ?? []
                let r = dayRows.compactMap(\.diskRead).reduce(0, +)
                let w = dayRows.compactMap(\.diskWrite).reduce(0, +)
                let key = ReportUIHelper.formatDateShort(dayStart)
                return ReportDiskMetrics.DailyBar(
                    id: "\(Int64(dayStart.timeIntervalSince1970))",
                    date: dayStart,
                    dateText: key,
                    readBytes: r,
                    writeBytes: w
                )
            }
        }

        return ReportDiskMetrics(
            totalReadBytes: totalRead,
            totalWriteBytes: totalWrite,
            peakReadRate: peakRead,
            peakWriteRate: peakWrite,
            dailyBars: dailyBars,
            isHourly: isHourly
        )
    }

    static func computePowerMetrics(rows: [StatisticsRow]) -> ReportPowerMetrics {
        let avg = weightedAverage(of: rows, keyPath: \.powerAvg)
        let peak = maximum(of: rows, keyPath: \.powerMax)
        return ReportPowerMetrics(avgPowerWatts: avg, peakPowerWatts: peak)
    }

    static func computeBatteryMetrics(
        rows: [StatisticsRow],
        batteryHistory: [StatisticsProcessStore.BatteryPoint],
        from: Date,
        to: Date,
        hardwareHasBattery: Bool
    ) -> ReportBatteryMetrics {
        let avgLevel = weightedAverage(of: rows, keyPath: \.battLevelAvg)
        let avgTemp = weightedAverage(of: rows, keyPath: \.battTempAvg)
        let acFrac = weightedAverage(of: rows, keyPath: \.acFrac)
        let chgFrac = weightedAverage(of: rows, keyPath: \.chargingFrac)

        let fromDay = StatisticsProcessStore.dayKey(from, calendar: .current)
        let toDay = StatisticsProcessStore.dayKey(to, calendar: .current)

        let filteredHistory = batteryHistory.filter { $0.day >= fromDay && $0.day <= toDay }
        let dailyHealth = filteredHistory.map { item -> ReportBatteryMetrics.DailyHealth in
            let date = parseDayKey(item.day)
            return ReportBatteryMetrics.DailyHealth(
                id: item.day,
                day: item.day,
                date: date,
                cycleCount: item.cycleCount,
                healthPercent: item.healthPercent
            )
        }

        let hasHistory = avgLevel != nil || !dailyHealth.isEmpty

        return ReportBatteryMetrics(
            avgLevel: avgLevel,
            avgTemp: avgTemp,
            acFraction: acFrac,
            chargingFraction: chgFrac,
            dailyHistory: dailyHealth,
            isSupported: hardwareHasBattery,
            hasHistoryInRange: hasHistory
        )
    }

    static func computeThermalMetrics(rows: [StatisticsRow], hardwareHasFans: Bool = true, fanSensorAvailable: Bool = true) -> ReportThermalMetrics {
        let cpuThermal = weightedAverage(of: rows, keyPath: \.cpuThermalAvg)
        let cpuTemp = weightedAverage(of: rows, keyPath: \.cpuTempAvg)
        let fanAvg = weightedAverage(of: rows, keyPath: \.fanAvg)
        let fanMax = maximum(of: rows, keyPath: \.fanMax)

        return ReportThermalMetrics(
            cpuThermalAvg: cpuThermal,
            cpuTempAvg: cpuTemp,
            fanAvgRPM: fanAvg,
            fanMaxRPM: fanMax,
            hasFans: hardwareHasFans,
            fanSensorAvailable: fanSensorAvailable
        )
    }

    // MARK: - 应用排行聚合

    static func aggregateApps(
        processData: ReportProcessData?,
        from: Date,
        to: Date,
        isDirect: Bool
    ) -> ReportAppRankings {
        guard let processData, !processData.dailyRows.isEmpty else {
            return ReportAppRankings(cpuList: [], memList: [], gpuList: [], diskList: [], netList: [], highLoadAlerts: [])
        }

        let fromDay = StatisticsProcessStore.dayKey(from, calendar: .current)
        let toDay = StatisticsProcessStore.dayKey(to, calendar: .current)

        typealias AppAggEntry = (
            name: String,
            cpuSum: Double, cpuN: Int,
            gpuSum: Double, gpuN: Int,
            memSum: Double, memN: Int,
            netDownBytes: Double, netUpBytes: Double,
            diskReadBytes: Double, diskWriteBytes: Double,
            cpuT1: Int, cpuT2: Int, cpuT3: Int, cpuPeak: Double,
            gpuT1: Int, gpuT2: Int, gpuT3: Int, gpuPeak: Double,
            memT1: Int, memT2: Int, memT3: Int, memPeak: Double
        )

        var agg: [String: AppAggEntry] = [:]

        for row in processData.dailyRows {
            if row.day < fromDay || row.day > toDay { continue }

            var entry = agg[row.appKey] ?? (
                name: row.name,
                cpuSum: 0, cpuN: 0,
                gpuSum: 0, gpuN: 0,
                memSum: 0, memN: 0,
                netDownBytes: 0, netUpBytes: 0,
                diskReadBytes: 0, diskWriteBytes: 0,
                cpuT1: 0, cpuT2: 0, cpuT3: 0, cpuPeak: 0,
                gpuT1: 0, gpuT2: 0, gpuT3: 0, gpuPeak: 0,
                memT1: 0, memT2: 0, memT3: 0, memPeak: 0
            )

            entry.cpuSum += row.cpuAvg * Double(row.cpuSamples)
            entry.cpuN += row.cpuSamples
            entry.gpuSum += row.gpuAvg * Double(row.gpuSamples)
            entry.gpuN += row.gpuSamples
            entry.memSum += row.memAvgBytes * Double(row.memSamples)
            entry.memN += row.memSamples
            entry.netDownBytes += row.netDownBytes
            entry.netUpBytes += row.netUpBytes
            entry.diskReadBytes += row.diskReadBytes
            entry.diskWriteBytes += row.diskWriteBytes

            entry.cpuT1 += row.cpuTier1
            entry.cpuT2 += row.cpuTier2
            entry.cpuT3 += row.cpuTier3
            if row.cpuPeak > entry.cpuPeak { entry.cpuPeak = row.cpuPeak }

            entry.gpuT1 += row.gpuTier1
            entry.gpuT2 += row.gpuTier2
            entry.gpuT3 += row.gpuTier3
            if row.gpuPeak > entry.gpuPeak { entry.gpuPeak = row.gpuPeak }

            entry.memT1 += row.memTier1
            entry.memT2 += row.memTier2
            entry.memT3 += row.memTier3
            if row.memPeak > entry.memPeak { entry.memPeak = row.memPeak }

            agg[row.appKey] = entry
        }

        // 约定：stats.r.prefix* 与 stats.r.unit* 为原子级词缀/单位键，xcstrings 中其值必须是无格式占位符（不得含 %@ / %d 等）的纯文本，由 Swift 插值拼接避免格式化参数不匹配风险。
        func formatCoreMinutes(_ mins: Double, isGpu: Bool = false) -> String {
            let unitMin = isGpu
                ? String(localized: "stats.r.unitGpuMin", defaultValue: "GPU·分")
                : String(localized: "stats.r.unitCoreMin", defaultValue: "核·分")
            let unitHours = isGpu
                ? String(localized: "stats.r.unitGpuHours", defaultValue: "GPU·时")
                : String(localized: "stats.r.unitCoreHours", defaultValue: "核·时")

            if mins < 1.0 {
                return "< 1 \(unitMin)"
            } else if mins < 60.0 {
                return "\(Int(mins.rounded())) \(unitMin)"
            } else {
                return "\(String(format: "%.1f", mins / 60.0)) \(unitHours)"
            }
        }

        func makeList(
            getValue: ((appKey: String, val: AppAggEntry)) -> Double,
            format: (Double) -> String,
            getTierHint: (((appKey: String, val: AppAggEntry, value: Double)) -> String?)? = nil,
            minThreshold: Double = 0.05,
            tag: String = "item"
        ) -> [ReportAppRankingItem] {
            agg.compactMap { (appKey, val) -> ReportAppRankingItem? in
                let v = getValue((appKey, val))
                guard v >= minThreshold else { return nil }
                let tierHint = getTierHint?((appKey, val, v))
                let iconData = processData.identities[appKey]?.iconPNG
                return ReportAppRankingItem(
                    id: "\(tag)-\(appKey)",
                    appKey: appKey,
                    name: val.name,
                    value: v,
                    valueText: format(v),
                    tierHint: tierHint,
                    iconData: iconData
                )
            }
            .sorted { $0.value > $1.value }
            .prefix(25)
            .map { $0 }
        }

        let cpuList = makeList(
            getValue: { $0.val.cpuSum / 100.0 },
            format: { formatCoreMinutes($0, isGpu: false) },
            getTierHint: { item in
                let val = item.val
                var parts: [String] = []
                if val.cpuN > 0 {
                    let avg = val.cpuSum / Double(val.cpuN)
                    let avgPrefix = String(localized: "stats.r.prefixAvg", defaultValue: "均值")
                    parts.append("\(avgPrefix) \(String(format: "%.1f%%", avg))")
                }
                if val.cpuPeak > 0 {
                    let peakPrefix = String(localized: "stats.r.prefixPeak", defaultValue: "峰值")
                    parts.append("\(peakPrefix) \(String(format: "%.0f%%", val.cpuPeak))")
                }
                if val.cpuT3 > 0 {
                    let fullLoadPrefix = String(localized: "stats.r.prefixFullLoad", defaultValue: "满载:")
                    parts.append("\(fullLoadPrefix) \(val.cpuT3)m")
                } else if val.cpuT2 > 0 {
                    let highLoadPrefix = String(localized: "stats.r.prefixHighLoad", defaultValue: "高载:")
                    parts.append("\(highLoadPrefix) \(val.cpuT2)m")
                }
                return parts.joined(separator: " · ")
            },
            minThreshold: 0.05,
            tag: "cpu"
        )

        let memList = makeList(
            getValue: { $0.val.memN > 0 ? $0.val.memSum / Double($0.val.memN) : 0 },
            format: { ReportUIHelper.formatBytes($0) },
            getTierHint: { item in
                let val = item.val
                var parts: [String] = []
                if val.memPeak > 0 {
                    let peakPrefix = String(localized: "stats.r.prefixPeak", defaultValue: "峰值")
                    parts.append("\(peakPrefix) \(ReportUIHelper.formatBytes(val.memPeak))")
                }
                let highMem = val.memT2 + val.memT3
                if highMem > 0 {
                    let highMemPrefix = String(localized: "stats.r.prefixHighMem", defaultValue: "高水位:")
                    parts.append("\(highMemPrefix) \(highMem)m")
                }
                return parts.isEmpty ? String(localized: "stats.r.appResidentAvg", defaultValue: "常驻均值") : parts.joined(separator: " · ")
            },
            minThreshold: 1024 * 1024,
            tag: "mem"
        )

        let gpuList = makeList(
            getValue: { $0.val.gpuSum / 100.0 },
            format: { formatCoreMinutes($0, isGpu: true) },
            getTierHint: { item in
                let val = item.val
                var parts: [String] = []
                if val.gpuN > 0 {
                    let avg = val.gpuSum / Double(val.gpuN)
                    let avgPrefix = String(localized: "stats.r.prefixAvg", defaultValue: "均值")
                    parts.append("\(avgPrefix) \(String(format: "%.1f%%", avg))")
                }
                if val.gpuPeak > 0 {
                    let peakPrefix = String(localized: "stats.r.prefixPeak", defaultValue: "峰值")
                    parts.append("\(peakPrefix) \(String(format: "%.0f%%", val.gpuPeak))")
                }
                if val.gpuT3 > 0 {
                    let fullLoadPrefix = String(localized: "stats.r.prefixFullLoad", defaultValue: "满载:")
                    parts.append("\(fullLoadPrefix) \(val.gpuT3)m")
                }
                return parts.joined(separator: " · ")
            },
            minThreshold: 0.05,
            tag: "gpu"
        )

        let diskList = isDirect ? makeList(
            getValue: { $0.val.diskReadBytes + $0.val.diskWriteBytes },
            format: { ReportUIHelper.formatBytes($0) },
            getTierHint: { item in
                let val = item.val
                let readPrefix = String(localized: "stats.r.prefixRead", defaultValue: "读")
                let writePrefix = String(localized: "stats.r.prefixWrite", defaultValue: "写")
                return "\(readPrefix) \(ReportUIHelper.formatBytes(val.diskReadBytes)) · \(writePrefix) \(ReportUIHelper.formatBytes(val.diskWriteBytes))"
            },
            minThreshold: 1024,
            tag: "disk"
        ) : []

        let netList = isDirect ? makeList(
            getValue: { $0.val.netDownBytes + $0.val.netUpBytes },
            format: { ReportUIHelper.formatBytes($0) },
            getTierHint: { item in
                let val = item.val
                return "↓ \(ReportUIHelper.formatBytes(val.netDownBytes)) · ↑ \(ReportUIHelper.formatBytes(val.netUpBytes))"
            },
            minThreshold: 1024,
            tag: "net"
        ) : []

        // 高负载告警分组
        var alertGroups: [String: [ProcessAlertEpisode]] = [:]
        for alert in processData.alerts {
            alertGroups[alert.appKey, default: []].append(alert)
        }

        let highLoadItems = alertGroups.map { (appKey, episodes) -> ReportHighLoadAppGroup in
            let name = episodes.first?.name ?? appKey
            let isOngoing = episodes.contains { $0.state == .ongoing }
            let earliest = episodes.map(\.startedAt).min()
            let maxDur = episodes.map(\.durationMinutes).max() ?? 0
            let iconData = processData.identities[appKey]?.iconPNG
            return ReportHighLoadAppGroup(
                id: appKey,
                appKey: appKey,
                name: name,
                isOngoing: isOngoing,
                earliestStart: earliest,
                maxDurationMinutes: maxDur,
                episodes: episodes,
                iconData: iconData
            )
        }.sorted { a, b in
            if a.isOngoing != b.isOngoing { return a.isOngoing }
            return a.maxDurationMinutes > b.maxDurationMinutes
        }

        return ReportAppRankings(
            cpuList: cpuList,
            memList: memList,
            gpuList: gpuList,
            diskList: diskList,
            netList: netList,
            highLoadAlerts: highLoadItems
        )
    }

    // MARK: - 异常事件流推导 (R08: 仅由对应维度的有效观测宣告恢复)

    static func deriveAlertEvents(
        rows: [StatisticsRow],
        source: ReportSourceGranularity,
        now: Date
    ) -> [ReportEventItem] {
        guard !rows.isEmpty else { return [] }
        let span = source.bucketSeconds
        let freshWindow: TimeInterval = 5 * 60

        // 分别跟踪内存维度与热状态维度的最后有效观测时间点
        let lastMemObsEnd = rows.compactMap { row -> Date? in
            let hasMemObs = (row.validMemS ?? 0) > 0 ||
                (row.memNormalS ?? 0) > 0 || (row.memWarnS ?? 0) > 0 || (row.memCritS ?? 0) > 0
            guard hasMemObs else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(row.t) + span)
        }.max()

        let lastThermalObsEnd = rows.compactMap { row -> Date? in
            let hasThermalObs = (row.validThermalS ?? 0) > 0 ||
                (row.thNominalS ?? 0) > 0 || (row.thFairS ?? 0) > 0 || (row.thSeriousS ?? 0) > 0 || (row.thCritS ?? 0) > 0
            guard hasThermalObs else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(row.t) + span)
        }.max()

        struct Spec {
            let kind: ReportEventItem.Kind
            let threshold: Int
            let lastObservedEnd: Date?
            let getLevels: (StatisticsRow) -> [(level: Int, seconds: Double)]
        }

        let specs: [Spec] = [
            Spec(kind: .memory, threshold: 1, lastObservedEnd: lastMemObsEnd) { r in
                var res: [(Int, Double)] = []
                if let s = r.memCritS, s > 0 { res.append((2, s)) }
                if let s = r.memWarnS, s > 0 { res.append((1, s)) }
                return res
            },
            Spec(kind: .thermal, threshold: 2, lastObservedEnd: lastThermalObsEnd) { r in
                var res: [(Int, Double)] = []
                if let s = r.thCritS, s > 0 { res.append((3, s)) }
                if let s = r.thSeriousS, s > 0 { res.append((2, s)) }
                if let s = r.thFairS, s > 0 { res.append((1, s)) }
                return res
            }
        ]

        var events: [ReportEventItem] = []

        for spec in specs {
            var currentStart: Date?
            var currentEnd: Date?
            var pressureSeconds = 0.0
            var worstLevel = 0

            func flush() {
                guard let start = currentStart, let end = currentEnd, pressureSeconds > 0 else { return }
                let state: ReportEventItem.State
                if let lastObs = spec.lastObservedEnd {
                    if end < lastObs {
                        state = .recovered
                    } else {
                        let isFresh = now.timeIntervalSince(lastObs) <= freshWindow
                        state = isFresh ? .ongoing : .interrupted
                    }
                } else {
                    state = .interrupted
                }
                let spanSec = end.timeIntervalSince(start)
                let detail = String(format: "%.0fm (%.0f%%)", pressureSeconds / 60.0, min(100, pressureSeconds / max(spanSec, 1) * 100))
                events.append(ReportEventItem(
                    id: "\(spec.kind)-\(start.timeIntervalSince1970)",
                    kind: spec.kind,
                    state: state,
                    start: start,
                    end: end,
                    pressureSeconds: pressureSeconds,
                    worstLevel: worstLevel,
                    detailText: detail
                ))
                currentStart = nil
                currentEnd = nil
                pressureSeconds = 0.0
                worstLevel = 0
            }

            for row in rows {
                let levels = spec.getLevels(row)
                let pressure = levels.filter { $0.level >= spec.threshold }.map(\.seconds).reduce(0, +)
                let rowDate = Date(timeIntervalSince1970: TimeInterval(row.t))
                let rowEnd = rowDate.addingTimeInterval(span)

                if pressure <= 0 {
                    flush()
                    continue
                }

                if let end = currentEnd, rowDate.timeIntervalSince(end) > span * 1.5 {
                    flush()
                }

                if currentStart == nil {
                    currentStart = rowDate
                }
                currentEnd = rowEnd
                pressureSeconds += pressure
                for item in levels {
                    if item.level > worstLevel { worstLevel = item.level }
                }
            }
            flush()
        }

        let stateRank: [ReportEventItem.State: Int] = [.ongoing: 0, .interrupted: 1, .recovered: 2]
        return events.sorted { a, b in
            let rankA = stateRank[a.state] ?? 3
            let rankB = stateRank[b.state] ?? 3
            if rankA != rankB { return rankA < rankB }
            return a.pressureSeconds > b.pressureSeconds
        }
    }

    // MARK: - 活动热力图构建 (R06: 始终消费小时数据，复合忙碌度)

    static func buildHeatmap(hourlyRows: [StatisticsRow], calendar: Calendar = .current) -> ReportHeatmapData {
        var grid: [String: (sum: Double, frames: Int)] = [:]

        for row in hourlyRows {
            guard row.n > 0 else { continue }
            let cpu = row.cpuAvg ?? 0
            let gpu = row.gpuAvg ?? 0
            let mem = row.memPressureAvg ?? 0
            guard row.cpuAvg != nil || row.gpuAvg != nil || row.memPressureAvg != nil else { continue }

            let busy = max(cpu, gpu, mem)
            let date = Date(timeIntervalSince1970: TimeInterval(row.t))
            let weekday = calendar.component(.weekday, from: date) - 1 // 0=Sun..6=Sat
            let hour = calendar.component(.hour, from: date)
            let key = "\(weekday)-\(hour)"
            var entry = grid[key] ?? (0.0, 0)
            entry.sum += busy * Double(row.n)
            entry.frames += row.n
            grid[key] = entry
        }

        var maxAvg = 0.0
        for (_, entry) in grid {
            let avg = entry.frames > 0 ? entry.sum / Double(entry.frames) : 0
            if avg > maxAvg { maxAvg = avg }
        }

        var cells: [ReportHeatmapCell] = []
        for wd in 0..<7 {
            for hr in 0..<24 {
                let key = "\(wd)-\(hr)"
                let entry = grid[key]
                let avg = (entry != nil && entry!.frames > 0) ? entry!.sum / Double(entry!.frames) : nil
                let intensity = (avg != nil && maxAvg > 0) ? min(1.0, avg! / max(maxAvg, 20.0)) : 0.0
                cells.append(ReportHeatmapCell(
                    id: key,
                    weekday: wd,
                    hour: hr,
                    intensity: intensity,
                    avgBusy: avg
                ))
            }
        }

        return ReportHeatmapData(cells: cells)
    }

    // MARK: - 智能洞察生成 (R14: 修复模板变量替换，R16: 恢复最忙时段)

    static func generateInsights(
        rows: [StatisticsRow],
        hourlyRows: [StatisticsRow],
        source: ReportSourceGranularity,
        from: Date,
        to: Date
    ) -> [ReportInsightItem] {
        var insights: [ReportInsightItem] = []

        // 1. CPU 负载与高负载压力
        if let cpuAvg = weightedAverage(of: rows, keyPath: \.cpuAvg) {
            let (levelText, icon, color): (String, String, String) = {
                if cpuAvg < 20 {
                    return ("负载较轻，算力充足", "gauge.with.dots.needle.33percent", "green")
                } else if cpuAvg < 50 {
                    return ("负载适中，平稳运转", "gauge.with.dots.needle.67percent", "orange")
                } else {
                    return ("负载偏高，计算密集", "gauge.with.dots.needle.100percent", "red")
                }
            }()
            let highS = total(of: rows, keyPath: \.cpuHighS) ?? 0
            var detail = "所选范围平均 CPU 占用 \(String(format: "%.1f%%", cpuAvg)) — \(levelText)"
            if highS > 0 {
                detail += "，高负载持续累计 \(StatisticsDisplayFormat.duration(highS))"
            }
            insights.append(ReportInsightItem(id: "cpu-load", systemIcon: icon, colorName: color, title: "CPU 负载与压力", detail: detail))
        }

        // 2. CPU 瞬时峰值
        if let peakPair = maximumWithTime(of: rows, keyPath: \.cpuMax) {
            let timeStr = ReportUIHelper.formatDateTime(peakPair.time)
            let detail = "瞬时峰值达到 \(String(format: "%.1f%%", peakPair.value))（记录于 \(timeStr)）"
            insights.append(ReportInsightItem(id: "cpu-peak", systemIcon: "bolt.fill", colorName: "yellow", title: "CPU 峰值记录", detail: detail))
        }

        // 3. GPU 图形处理器负荷
        if let gpuAvg = weightedAverage(of: rows, keyPath: \.gpuAvg) {
            let gpuPeak = maximum(of: rows, keyPath: \.gpuMax)
            let gpuHighS = total(of: rows, keyPath: \.gpuHighS) ?? 0
            var detail = "平均图形占用 \(String(format: "%.1f%%", gpuAvg))"
            if let gpuPeak {
                detail += "，瞬时峰值 \(String(format: "%.0f%%", gpuPeak))"
            }
            if gpuHighS > 0 {
                detail += "，高负荷运行达 \(StatisticsDisplayFormat.duration(gpuHighS))"
            } else {
                detail += "，图形算力消耗平稳"
            }
            let color = gpuAvg > 50 ? "red" : (gpuAvg > 20 ? "orange" : "blue")
            insights.append(ReportInsightItem(id: "gpu-load", systemIcon: "display", colorName: color, title: "GPU 渲染与算力", detail: detail))
        }

        // 4. 系统内存与交换空间压力
        if let memPressure = weightedAverage(of: rows, keyPath: \.memPressureAvg) {
            let memPct = weightedAverage(of: rows, keyPath: \.memPctAvg)
            let swapBytes = maximum(of: rows, keyPath: \.memSwapAvg)
            var detail = ""
            if let memPct {
                detail += "物理内存平均占用 \(String(format: "%.1f%%", memPct))，"
            }
            detail += "系统内存压力均值 \(String(format: "%.0f%%", memPressure))"
            if let swapBytes, swapBytes > 10 * 1024 * 1024 {
                detail += "，磁盘交换空间 (Swap) 活跃 \(ReportUIHelper.formatBytes(swapBytes))，提示内存偏紧"
            } else {
                detail += "，无显著 Swap 磁盘交换"
            }
            let color = memPressure >= 50 ? "red" : (memPressure >= 20 ? "orange" : "green")
            insights.append(ReportInsightItem(id: "mem-pressure", systemIcon: "memorychip", colorName: color, title: "系统内存与压力", detail: detail))
        }

        // 5. 热状态与散热温控
        let cpuTemp = weightedAverage(of: rows, keyPath: \.cpuTempAvg)
        let cpuThermal = weightedAverage(of: rows, keyPath: \.cpuThermalAvg)
        let fanRPM = maximum(of: rows, keyPath: \.fanMax) ?? weightedAverage(of: rows, keyPath: \.fanAvg)
        if cpuTemp != nil || cpuThermal != nil {
            var detail = ""
            if let cpuTemp {
                detail += "处理器平均温度 \(String(format: "%.1f°C", cpuTemp))"
            }
            if let fanRPM, fanRPM > 0 {
                detail += "，风扇主动散热最高达 \(String(format: "%.0f RPM", fanRPM))"
            } else {
                detail += "，被动散热/静音运转"
            }
            if let cpuThermal, cpuThermal > 0.05 {
                detail += "，曾出现温控降频或系统级轻微控温"
            }
            let color = (cpuThermal ?? 0) > 0.1 ? "red" : ((cpuTemp ?? 0) > 75 ? "orange" : "green")
            insights.append(ReportInsightItem(id: "thermal-state", systemIcon: "flame.fill", colorName: color, title: "热压力与散热表现", detail: detail))
        }

        // 6. 整机功耗与供电
        if let pAvg = weightedAverage(of: rows, keyPath: \.powerAvg) {
            let pPeak = maximum(of: rows, keyPath: \.powerMax)
            let acFrac = weightedAverage(of: rows, keyPath: \.acFrac)
            var detail = "平均整机功耗 \(String(format: "%.1f W", pAvg))"
            if let pPeak {
                detail += "，最高瞬时功耗 \(String(format: "%.1f W", pPeak))"
            }
            if let acFrac {
                detail += "，接电运行占比 \(String(format: "%.0f%%", acFrac * 100))"
            }
            insights.append(ReportInsightItem(id: "power-stats", systemIcon: "powerplug", colorName: "yellow", title: "功耗与供电特征", detail: detail))
        }

        // 7. 大额磁盘读写活动
        let diskR = total(of: rows, keyPath: \.diskRead) ?? 0
        let diskW = total(of: rows, keyPath: \.diskWrite) ?? 0
        if diskR > 0 || diskW > 0 {
            let totalDisk = diskR + diskW
            let peakR = maximum(of: rows, keyPath: \.diskReadPeak)
            var detail = "累计完成读写 \(ReportUIHelper.formatBytes(totalDisk))（读 \(ReportUIHelper.formatBytes(diskR))，写 \(ReportUIHelper.formatBytes(diskW))）"
            if let peakR, peakR > 10 * 1024 * 1024 {
                detail += "，突发读峰值达到 \(ReportUIHelper.formatBytesRate(peakR))"
            }
            insights.append(ReportInsightItem(id: "disk-io", systemIcon: "internaldrive", colorName: "blue", title: "磁盘读写吞吐", detail: detail))
        }

        // 8. 大额网络流量传输
        let netDown = total(of: rows, keyPath: \.netDown) ?? 0
        let netUp = total(of: rows, keyPath: \.netUp) ?? 0
        if netDown > 0 || netUp > 0 {
            let totalNet = netDown + netUp
            let peakDown = maximum(of: rows, keyPath: \.netDownPeak)
            var detail = "双向网络流量合计 \(ReportUIHelper.formatBytes(totalNet))（下行 \(ReportUIHelper.formatBytes(netDown))，上行 \(ReportUIHelper.formatBytes(netUp))）"
            if let peakDown, peakDown > 1 * 1024 * 1024 {
                detail += "，下行突发峰值 \(ReportUIHelper.formatBytesRate(peakDown))"
            }
            insights.append(ReportInsightItem(id: "net-down", systemIcon: "network", colorName: "blue", title: "网络传输吞吐", detail: detail))
        }

        // 9. 最忙时段 (R16: 从小时层数据推导)
        if !hourlyRows.isEmpty {
            var hourSlots: [Int: (sum: Double, frames: Int)] = [:]
            for r in hourlyRows {
                guard let cpu = r.cpuAvg, r.n > 0 else { continue }
                let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(r.t)))
                var entry = hourSlots[hour] ?? (0.0, 0)
                entry.sum += cpu * Double(r.n)
                entry.frames += r.n
                hourSlots[hour] = entry
            }
            var busiestHour: Int?
            var busiestAvg = 0.0
            for (h, entry) in hourSlots {
                let avg = entry.frames > 0 ? entry.sum / Double(entry.frames) : 0
                if avg > busiestAvg {
                    busiestAvg = avg
                    busiestHour = h
                }
            }
            if let bh = busiestHour, busiestAvg > 5.0 {
                let slotStr = String(format: "%02d:00–%02d:00", bh, (bh + 1) % 24)
                let detail = "\(slotStr) 整体负荷最高，时段 CPU 均值达到 \(String(format: "%.1f%%", busiestAvg))"
                insights.append(ReportInsightItem(id: "busiest-hour", systemIcon: "clock.badge.exclamationmark", colorName: "red", title: "全天活跃节律", detail: detail))
            }
        }

        // 10. 监测覆盖率
        if let coverageRatio = coverageRatio(rows: rows, from: from, to: to) {
            let totalCover = rows.reduce(0.0) { $0 + max(0, coverSeconds(for: $1)) }
            let percentage = coverageRatio * 100
            let detail = "所选时段累计有效采样 \(ReportUIHelper.formatHours(totalCover))，数据覆盖率达 \(String(format: "%.1f%%", percentage))"
            insights.append(ReportInsightItem(id: "coverage", systemIcon: "checkmark.seal.fill", colorName: "gray", title: "数据覆盖度", detail: detail))
        }

        return insights
    }

    // MARK: - 每日汇总表聚合 (R15)

    static func aggregateDailySummary(
        minutes: [StatisticsRow],
        hours: [StatisticsRow],
        days: [StatisticsRow],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [ReportDailySummaryRow] {
        var dayMap: [Date: StatisticsRow] = [:]
        for r in days {
            let d = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(r.t)))
            dayMap[d] = r
        }

        var results: [ReportDailySummaryRow] = []
        var currentDay = calendar.startOfDay(for: from)
        let endDay = calendar.startOfDay(for: to)
        let today = calendar.startOfDay(for: Date())

        while currentDay <= endDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay.addingTimeInterval(86400)
            var targetRow = dayMap[currentDay]

            if targetRow == nil && currentDay == today {
                // 今日用分钟数据实时聚合
                let dayMinutes = filterRows(minutes, from: currentDay, to: min(nextDay, Date()))
                if !dayMinutes.isEmpty {
                    targetRow = aggregateRows(dayMinutes, timestamp: Int64(currentDay.timeIntervalSince1970))
                }
            }

            if targetRow == nil {
                // 近期小时数据兜底
                let dayHours = filterRows(hours, from: currentDay, to: nextDay)
                if !dayHours.isEmpty {
                    targetRow = aggregateRows(dayHours, timestamp: Int64(currentDay.timeIntervalSince1970))
                }
            }

            if let r = targetRow {
                let dayKey = ReportUIHelper.formatDateShort(currentDay)
                results.append(ReportDailySummaryRow(
                    id: r.t,
                    date: currentDay,
                    dayKey: dayKey,
                    cpuAvg: r.cpuAvg,
                    cpuPeak: r.cpuMax,
                    memAvgPct: r.memPctAvg,
                    memPressureAvg: r.memPressureAvg,
                    netDownTotal: r.netDown,
                    netUpTotal: r.netUp,
                    diskReadTotal: r.diskRead,
                    diskWriteTotal: r.diskWrite,
                    acFrac: r.acFrac,
                    powerAvg: r.powerAvg,
                    coverageHours: coverSeconds(for: r) / 3600.0
                ))
            }

            currentDay = nextDay
        }

        return results.reversed()
    }

    private static func aggregateRows(_ rows: [StatisticsRow], timestamp: Int64) -> StatisticsRow {
        var merged = StatisticsRow(t: timestamp, n: rows.reduce(0) { $0 + $1.n })
        merged.cpuAvg = weightedAverage(of: rows, keyPath: \.cpuAvg)
        merged.cpuMax = maximum(of: rows, keyPath: \.cpuMax)
        merged.memPctAvg = weightedAverage(of: rows, keyPath: \.memPctAvg)
        merged.memPressureAvg = weightedAverage(of: rows, keyPath: \.memPressureAvg)
        merged.netDown = total(of: rows, keyPath: \.netDown)
        merged.netUp = total(of: rows, keyPath: \.netUp)
        merged.diskRead = total(of: rows, keyPath: \.diskRead)
        merged.diskWrite = total(of: rows, keyPath: \.diskWrite)
        merged.acFrac = weightedAverage(of: rows, keyPath: \.acFrac)
        merged.powerAvg = weightedAverage(of: rows, keyPath: \.powerAvg)
        merged.coverS = rows.reduce(0.0) { $0 + coverSeconds(for: $1) }
        return merged
    }

    // MARK: - 主聚合入口

    static func aggregate(
        snapshot: ReportSnapshot,
        range: ReportTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current,
        hardwareHasBattery: Bool = true,
        hardwareHasFans: Bool = true,
        fanSensorAvailable: Bool = true
    ) -> ReportActiveRangeModel {
        let (from, to) = range.bounds(now: snapshot.capturedAt, calendar: calendar)
        let granularity = pickSource(
            from: from,
            to: to,
            minutes: snapshot.minutes,
            hours: snapshot.hours,
            days: snapshot.days
        )

        let sourceRows: [StatisticsRow] = {
            switch granularity {
            case .minutes: return snapshot.minutes
            case .hours: return snapshot.hours
            case .days: return snapshot.days
            }
        }()

        let filtered = filterRows(sourceRows, from: from, to: to)
        let hourlyFiltered = filterRows(snapshot.hours, from: from, to: to)
        let coverageRatioValue = coverageRatio(rows: filtered, from: from, to: to)

        // 健康评分计算
        let healthScore = StatisticsHealthScore.evaluate(rows: filtered)
        let healthScoreNilReason: String? = {
            if healthScore != nil { return nil }
            if filtered.isEmpty {
                return String(localized: "stats.r.healthScoreNoData", defaultValue: "所选范围内无有效监测记录")
            } else {
                return String(localized: "stats.r.healthScoreInsufficient", defaultValue: "有效监测数据不足（需至少 30 分钟且指标覆盖率达标）")
            }
        }()

        let isSingleDay = Self.isSingleDay(from: from, to: to, calendar: calendar)

        let cpu = computeCpuMetrics(rows: filtered)
        let gpu = computeGpuMetrics(rows: filtered)
        let memory = computeMemoryMetrics(rows: filtered)
        let network = computeNetworkMetrics(rows: filtered, isHourly: isSingleDay, calendar: calendar)
        let disk = computeDiskMetrics(rows: filtered, isHourly: isSingleDay, calendar: calendar)
        let power = computePowerMetrics(rows: filtered)
        let battery = computeBatteryMetrics(
            rows: filtered,
            batteryHistory: snapshot.process?.batteryHistory ?? [],
            from: from,
            to: to,
            hardwareHasBattery: hardwareHasBattery
        )
        let thermal = computeThermalMetrics(
            rows: filtered,
            hardwareHasFans: hardwareHasFans,
            fanSensorAvailable: fanSensorAvailable
        )
        let apps = aggregateApps(
            processData: snapshot.process,
            from: from,
            to: to,
            isDirect: snapshot.meta.isDirect
        )
        let events = deriveAlertEvents(rows: filtered, source: granularity, now: snapshot.capturedAt)
        let insights = generateInsights(
            rows: filtered,
            hourlyRows: hourlyFiltered,
            source: granularity,
            from: from,
            to: to
        )

        // R06: 7x24 热力图始终使用小时数据输入
        let heatmap = range == .today ? nil : buildHeatmap(hourlyRows: hourlyFiltered, calendar: calendar)

        // R15: 每日汇总聚合表
        let dailySummary = aggregateDailySummary(
            minutes: snapshot.minutes,
            hours: snapshot.hours,
            days: snapshot.days,
            from: from,
            to: to,
            calendar: calendar
        )

        return ReportActiveRangeModel(
            range: range,
            granularity: granularity,
            from: from,
            to: to,
            isSingleDay: isSingleDay,
            rows: filtered,
            coverageRatio: coverageRatioValue,
            healthScore: healthScore,
            healthScoreNilReason: healthScoreNilReason,
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            network: network,
            disk: disk,
            power: power,
            battery: battery,
            thermal: thermal,
            apps: apps,
            events: events,
            insights: insights,
            heatmap: heatmap,
            dailySummaryRows: dailySummary
        )
    }

    private static func parseDayKey(_ day: Int64) -> Date {
        let y = Int(day / 10000)
        let m = Int((day % 10000) / 100)
        let d = Int(day % 100)
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return Calendar.current.date(from: components) ?? Date()
    }
}
