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

    /// 有效采样量除以整机清醒时长。只扣除系统明确报告的休眠区间；
    /// 应用退出或采样失败形成的空档仍计入分母。
    static func coverageRatio(
        rows: [StatisticsRow],
        from: Date,
        to: Date,
        systemSleepIntervals: [SystemSleepInterval] = []
    ) -> Double? {
        guard !rows.isEmpty else { return nil }
        let span = to.timeIntervalSince(from)
        guard span.isFinite, span > 0 else { return nil }

        let awakeSpan = span - sleepSeconds(in: systemSleepIntervals, from: from, to: to)
        guard awakeSpan > 0 else { return nil }
        let covered = rows.reduce(0.0) { partial, row in
            partial + max(0, coverSeconds(for: row))
        }
        guard covered > 0 else { return nil }
        return min(1, max(0, covered / awakeSpan))
    }

    /// 将事件裁剪至查询区间 [from, to) 内，按有效交集计算区间内时长与加权均值。
    static func clipEpisode(
        _ episode: ProcessAlertEpisode,
        from: Date,
        to: Date
    ) -> (episode: ProcessAlertEpisode, coveredSeconds: Double)? {
        let start = max(episode.startedAt, from)
        let end = min(episode.endedAt ?? episode.lastSeenAt, to)
        guard end > start else { return nil }

        var clipped = episode
        clipped.eventSpanSeconds = end.timeIntervalSince(start)

        // 存在分段记录时按覆盖分段精确裁剪时长、均值与峰值
        if let precise = AppResourceEventStateMachine.clipSegments(episode.segments, from: from, to: to) {
            clipped.continuousHighSeconds = precise.seconds
            clipped.averageUsage = precise.averageValue
            clipped.peakUsage = min(episode.peakUsage, max(precise.peak, precise.averageValue))
            let fraction = precise.seconds / max(episode.continuousHighSeconds, 0.001)
            clipped.observationCount = max(1, Int((Double(episode.observationCount) * fraction).rounded()))
            return (clipped, clipped.continuousHighSeconds)
        }

        // 无分段记录时按跨度比例折算
        let effective = episode.endedAt ?? episode.lastSeenAt
        let fullSpan = max(effective.timeIntervalSince(episode.startedAt), 0.001)
        let inRange = end.timeIntervalSince(start)
        let fraction = min(1, max(0, inRange / fullSpan))
        clipped.continuousHighSeconds = episode.continuousHighSeconds * fraction
        clipped.observationCount = max(1, Int((Double(episode.observationCount) * fraction).rounded()))
        return (clipped, clipped.continuousHighSeconds)
    }

    /// 从持久化记录还原事件展示模型。
    static func persistedEpisodes(_ events: [PersistedAppEvent]) -> [ProcessAlertEpisode] {
        events.compactMap { stored in
            guard let metric = ProcessAlertEpisode.Metric(rawValue: stored.metric),
                  let state = ProcessAlertEpisode.State(rawValue: stored.state),
                  let id = UUID(uuidString: stored.eventID) else {
                return nil
            }
            return ProcessAlertEpisode(
                id: id,
                appKey: stored.appKey,
                name: stored.name,
                metric: metric,
                startedAt: stored.startedAt,
                lastSeenAt: stored.lastEffectiveAt,
                endedAt: stored.endedAt,
                peakUsage: stored.peakUsage,
                averageUsage: stored.averageUsage,
                continuousHighSeconds: stored.continuousHighSeconds,
                eventSpanSeconds: stored.eventSpanSeconds,
                observationCount: stored.observationCount,
                endReason: stored.endReason.flatMap(ProcessAlertEpisode.EndReason.init(rawValue:)),
                state: state,
                notified: stored.notified
            )
        }
    }

    /// 趋势图支持的应用指标类别。
    enum AppTrendMetric: String, Sendable, CaseIterable {
        case cpu
        case gpu
        case memory
        case network
        case disk
    }

    /// 单个应用在范围内的逐日趋势点（按时间升序）。
    static func appTrendSeries(
        dailyRows: [StatisticsProcessStore.DailyAppRow],
        appKey: String,
        trendMetric: AppTrendMetric,
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        let range = StatisticsProcessStore.dayRange(from: from, to: to, calendar: calendar)
        let rows = dailyRows
            .filter { $0.appKey == appKey && range.contains(day: $0.day) }
            .sorted { $0.day < $1.day }

        return rows.compactMap { row in
            let value: Double? = switch trendMetric {
            case .cpu: row.cpuSamples > 0 ? row.cpuAvg : nil
            case .gpu: row.gpuSamples > 0 ? row.gpuAvg : nil
            case .memory: row.memSamples > 0 ? row.memAvgBytes : nil
            case .network: (row.netDownBytes + row.netUpBytes) > 0 ? row.netDownBytes + row.netUpBytes : nil
            case .disk: (row.diskReadBytes + row.diskWriteBytes) > 0 ? row.diskReadBytes + row.diskWriteBytes : nil
            }
            guard let value else { return nil }
            return (date: dayKeyToDate(row.day, calendar: calendar), value: value)
        }
    }

    /// 单个应用在范围内的逐日趋势点（告警指标重载，兼容既有调用）。
    static func appTrendSeries(
        dailyRows: [StatisticsProcessStore.DailyAppRow],
        appKey: String,
        metric: ProcessAlertEpisode.Metric,
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        let trendMetric: AppTrendMetric = switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        }
        return appTrendSeries(
            dailyRows: dailyRows,
            appKey: appKey,
            trendMetric: trendMetric,
            from: from,
            to: to,
            calendar: calendar
        )
    }

    /// 日键（yyyyMMdd）还原为当天零点。
    static func dayKeyToDate(_ key: Int64, calendar: Calendar = .current) -> Date {
        Date(timeIntervalSince1970: TimeInterval(StatisticsProcessStore.dateFromDayKey(key, calendar: calendar)))
    }

    /// 历史名称到稳定身份键的可证实映射。
    /// 仅在显示名称唯一对应已知身份时归并，存在同名冲突时保持独立。
    static func identityAliases(processData: ReportProcessData) -> [String: String] {
        var byDisplayName: [String: String] = [:]
        for (key, identity) in processData.identities {
            guard key != identity.name else { continue }
            if let existing = byDisplayName[identity.name], existing != key {
                byDisplayName[identity.name] = ""
                continue
            }
            byDisplayName[identity.name] = key
        }
        return byDisplayName.filter { !$0.value.isEmpty }
    }

    /// 汇总本期结果的数据质量标记（无观测、日汇总估算、样本估算、部分覆盖）。
    static func dataQuality(
        rows: [StatisticsRow],
        coverageRatio: Double?,
        granularity: ReportSourceGranularity,
        appsEstimateLeadingSample: Bool
    ) -> StatisticsDataQuality {
        guard !rows.isEmpty else { return [.noObservation] }
        var quality: StatisticsDataQuality = [.observed]
        if granularity == .days {
            quality = quality.combining(.legacyDailyEstimate)
        }
        if appsEstimateLeadingSample {
            quality = quality.combining(.leadingSampleEstimate)
        }
        // 覆盖率低于 1 时标记为部分覆盖。
        if let coverageRatio, coverageRatio < 0.95 {
            quality = quality.combining(.partialCoverage)
        }
        return quality
    }

    /// 先裁剪再合并区间，避免重复通知或跨范围休眠造成分母重复扣除。
    static func sleepSeconds(in intervals: [SystemSleepInterval], from: Date, to: Date) -> TimeInterval {
        let clipped = intervals.compactMap { interval -> (Date, Date)? in
            let start = max(from, interval.start)
            let end = min(to, interval.end)
            return end > start ? (start, end) : nil
        }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in clipped {
            if let segment = current, interval.0 <= segment.1 {
                current = (segment.0, max(segment.1, interval.1))
            } else {
                if let segment = current { total += segment.1.timeIntervalSince(segment.0) }
                current = interval
            }
        }
        if let segment = current { total += segment.1.timeIntervalSince(segment.0) }
        return total
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
        hardwareHasBattery: Bool,
        calendar: Calendar = .current
    ) -> ReportBatteryMetrics {
        let avgLevel = weightedAverage(of: rows, keyPath: \.battLevelAvg)
        let avgTemp = weightedAverage(of: rows, keyPath: \.battTempAvg)
        let acFrac = weightedAverage(of: rows, keyPath: \.acFrac)
        let chgFrac = weightedAverage(of: rows, keyPath: \.chargingFrac)

        let dayRange = StatisticsProcessStore.dayRange(from: from, to: to, calendar: calendar)

        let filteredHistory = batteryHistory.filter { dayRange.contains(day: $0.day) }
        let dailyHealth = filteredHistory.map { item -> ReportBatteryMetrics.DailyHealth in
            let date = parseDayKey(item.day, calendar: calendar)
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
        isDirect: Bool,
        calendar: Calendar = .current
    ) -> ReportAppRankings {
        guard let processData, !processData.dailyRows.isEmpty else {
            return ReportAppRankings(cpuList: [], memList: [], gpuList: [], diskList: [], netList: [], highLoadAlerts: [])
        }

        // 应用日行按 [from, to) 右开区间过滤
        let dayRange = StatisticsProcessStore.dayRange(from: from, to: to, calendar: calendar)

        // 权威名称表归并旧版记录：仅在旧键唯一对应已知身份显示名时映射，避免同名冲突误合
        let aliasMap = identityAliases(processData: processData)

        typealias AppAggEntry = (
            name: String,
            cpuSum: Double, cpuN: Int,
            gpuSum: Double, gpuN: Int,
            memSum: Double, memN: Int,
            netDownBytes: Double, netUpBytes: Double, netDayPeakBytes: Double,
            diskReadBytes: Double, diskWriteBytes: Double, diskDayPeakBytes: Double,
            cpuT1: Int, cpuT2: Int, cpuT3: Int, cpuPeak: Double,
            gpuT1: Int, gpuT2: Int, gpuT3: Int, gpuPeak: Double,
            memT1: Int, memT2: Int, memT3: Int, memPeak: Double
        )

        var agg: [String: AppAggEntry] = [:]
        var hasLegacyInRange = false

        for row in processData.dailyRows {
            if !dayRange.contains(day: row.day) { continue }
            let canonicalKey = aliasMap[row.appKey] ?? row.appKey
            if processData.identities[canonicalKey]?.isLegacyNameOnly ?? processData.identities[row.appKey]?.isLegacyNameOnly ?? false {
                hasLegacyInRange = true
            }

            var entry = agg[canonicalKey] ?? (
                name: row.name,
                cpuSum: 0, cpuN: 0,
                gpuSum: 0, gpuN: 0,
                memSum: 0, memN: 0,
                netDownBytes: 0, netUpBytes: 0, netDayPeakBytes: 0,
                diskReadBytes: 0, diskWriteBytes: 0, diskDayPeakBytes: 0,
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
            let dayNet = row.netDownBytes + row.netUpBytes
            if dayNet > entry.netDayPeakBytes { entry.netDayPeakBytes = dayNet }
            entry.diskReadBytes += row.diskReadBytes
            entry.diskWriteBytes += row.diskWriteBytes
            let dayDisk = row.diskReadBytes + row.diskWriteBytes
            if dayDisk > entry.diskDayPeakBytes { entry.diskDayPeakBytes = dayDisk }

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

            agg[canonicalKey] = entry
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
            getPeak: ((AppAggEntry) -> Double)? = nil,
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
                    peakValue: getPeak?(val) ?? v,
                    valueText: format(v),
                    tierHint: tierHint,
                    iconData: iconData
                )
            }
            // 保留全部聚合记录，条目截断由展示层控制
            .sorted { $0.value > $1.value }
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
            getPeak: { $0.cpuPeak },
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
            getPeak: { $0.memPeak },
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
            getPeak: { $0.gpuPeak },
            minThreshold: 0.05,
            tag: "gpu"
        )

        let diskList = isDirect ? makeList(
            getValue: { $0.val.diskReadBytes + $0.val.diskWriteBytes },
            format: { ReportUIHelper.formatVolume($0) },
            getTierHint: { item in
                let val = item.val
                let readPrefix = String(localized: "stats.r.prefixRead", defaultValue: "读")
                let writePrefix = String(localized: "stats.r.prefixWrite", defaultValue: "写")
                return "\(readPrefix) \(ReportUIHelper.formatVolume(val.diskReadBytes)) · \(writePrefix) \(ReportUIHelper.formatVolume(val.diskWriteBytes))"
            },
            getPeak: { $0.diskDayPeakBytes },
            minThreshold: 1024,
            tag: "disk"
        ) : []

        let netList = isDirect ? makeList(
            getValue: { $0.val.netDownBytes + $0.val.netUpBytes },
            format: { ReportUIHelper.formatVolume($0) },
            getTierHint: { item in
                let val = item.val
                return "↓ \(ReportUIHelper.formatVolume(val.netDownBytes)) · ↑ \(ReportUIHelper.formatVolume(val.netUpBytes))"
            },
            getPeak: { $0.netDayPeakBytes },
            minThreshold: 1024,
            tag: "net"
        ) : []

        // 高负载告警分组：合并内存中的活跃事件与持久化历史事件，按事件 ID 去重
        var alertGroups: [String: [ProcessAlertEpisode]] = [:]
        var mergedByID: [UUID: ProcessAlertEpisode] = [:]
        for alert in processData.alerts {
            mergedByID[alert.id] = alert
        }
        for restored in persistedEpisodes(processData.persistedEvents) where mergedByID[restored.id] == nil {
            mergedByID[restored.id] = restored
        }
        for alert in mergedByID.values {
            let canonicalKey = aliasMap[alert.appKey] ?? alert.appKey
            alertGroups[canonicalKey, default: []].append(alert)
        }

        // 仅保留与本期有交集的事件并按区间裁剪
        let clippedGroups = alertGroups.compactMap { (appKey, episodes) -> (String, [ProcessAlertEpisode])? in
            let clipped = episodes.compactMap { clipEpisode($0, from: from, to: to)?.episode }
            return clipped.isEmpty ? nil : (appKey, clipped)
        }

        let highLoadItems = clippedGroups.map { (appKey, episodes) -> ReportHighLoadAppGroup in
            let name = episodes.first?.name ?? appKey
            let isOngoing = episodes.contains { $0.state == .ongoing }
            let earliest = episodes.map(\.startedAt).min()
            let maxDur = episodes.map(\.continuousHighSeconds).max() ?? 0
            let iconData = processData.identities[appKey]?.iconPNG
            return ReportHighLoadAppGroup(
                id: appKey,
                appKey: appKey,
                name: name,
                isOngoing: isOngoing,
                earliestStart: earliest,
                maxDurationSeconds: maxDur,
                episodes: episodes,
                iconData: iconData
            )
        }.sorted { a, b in
            if a.isOngoing != b.isOngoing { return a.isOngoing }
            return a.maxDurationSeconds > b.maxDurationSeconds
        }

        return ReportAppRankings(
            cpuList: cpuList,
            memList: memList,
            gpuList: gpuList,
            diskList: diskList,
            netList: netList,
            highLoadAlerts: highLoadItems,
            hasLegacyNameIdentities: hasLegacyInRange
        )
    }

    /// 提取单个应用在五大维度上的跨分类画像摘要。
    static func appCrossMetricProfile(appKey: String, in rankings: ReportAppRankings) -> ReportAppProfile {
        ReportAppProfile(
            cpuText: rankings.cpuList.first(where: { $0.appKey == appKey })?.valueText,
            memoryText: rankings.memList.first(where: { $0.appKey == appKey })?.valueText,
            gpuText: rankings.gpuList.first(where: { $0.appKey == appKey })?.valueText,
            diskText: rankings.diskList.first(where: { $0.appKey == appKey })?.valueText,
            networkText: rankings.netList.first(where: { $0.appKey == appKey })?.valueText
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

        // 分别跟踪内存维度与热状态维度的最后有效观测时间点（不超过快照时刻 now）
        let lastMemObsEnd = rows.compactMap { row -> Date? in
            let hasMemObs = (row.validMemS ?? 0) > 0 ||
                (row.memNormalS ?? 0) > 0 || (row.memWarnS ?? 0) > 0 || (row.memCritS ?? 0) > 0
            guard hasMemObs else { return nil }
            return min(now, Date(timeIntervalSince1970: TimeInterval(row.t) + span))
        }.max()

        let lastThermalObsEnd = rows.compactMap { row -> Date? in
            let hasThermalObs = (row.validThermalS ?? 0) > 0 ||
                (row.thNominalS ?? 0) > 0 || (row.thFairS ?? 0) > 0 || (row.thSeriousS ?? 0) > 0 || (row.thCritS ?? 0) > 0
            guard hasThermalObs else { return nil }
            return min(now, Date(timeIntervalSince1970: TimeInterval(row.t) + span))
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
                let ratioPct = min(100, Int((pressureSeconds / max(spanSec, 1) * 100).rounded()))
                let severityLabel: String = {
                    switch spec.kind {
                    case .memory:
                        return worstLevel >= 2
                            ? String(localized: "stats.r.severityCritical", defaultValue: "紧急")
                            : String(localized: "stats.r.severityWarning", defaultValue: "警告")
                    case .thermal:
                        return StatisticsDisplayFormat.thermalStateLabel(Double(worstLevel))
                    }
                }()
                let detail = String(format: String(localized: "stats.r.eventRatioDetail", defaultValue: "%@ · 占比 %d%%"), severityLabel, ratioPct)
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
                let rowEnd = min(now, rowDate.addingTimeInterval(span))

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

    // MARK: - 智能洞察生成（对比环比、压力归因、长期趋势、可执行跳转）

    static func generateInsights(
        rows: [StatisticsRow],
        hourlyRows: [StatisticsRow],
        source: ReportSourceGranularity,
        from: Date,
        to: Date,
        systemSleepIntervals: [SystemSleepInterval] = []
    ) -> [ReportInsightItem] {
        let coverage = coverageRatio(rows: rows, from: from, to: to, systemSleepIntervals: systemSleepIntervals)
        let events = deriveAlertEvents(rows: rows, source: source, now: to)
        let thermal = computeThermalMetrics(rows: rows)
        let disk = computeDiskMetrics(rows: rows, isHourly: false)
        let battery = computeBatteryMetrics(rows: rows, batteryHistory: [], from: from, to: to, hardwareHasBattery: false)
        return generateInsights(
            rows: rows,
            hourlyRows: hourlyRows,
            previousRows: [],
            source: source,
            from: from,
            to: to,
            coverageRatio: coverage,
            events: events,
            apps: ReportAppRankings(cpuList: [], memList: [], gpuList: [], diskList: [], netList: [], highLoadAlerts: []),
            battery: battery,
            thermal: thermal,
            disk: disk,
            systemSleepIntervals: systemSleepIntervals
        )
    }

    static func generateInsights(
        rows: [StatisticsRow],
        hourlyRows: [StatisticsRow],
        previousRows: [StatisticsRow],
        source: ReportSourceGranularity,
        from: Date,
        to: Date,
        coverageRatio: Double?,
        events: [ReportEventItem],
        apps: ReportAppRankings,
        battery: ReportBatteryMetrics,
        thermal: ReportThermalMetrics,
        disk: ReportDiskMetrics,
        systemSleepIntervals: [SystemSleepInterval] = [],
        calendar: Calendar = .current
    ) -> [ReportInsightItem] {
        guard !rows.isEmpty else { return [] }
        var insights: [ReportInsightItem] = []

        // 1. 系统压力归因（将压力事件、并发 Swap/温度与高占用应用关联）
        if !events.isEmpty {
            let memEvents = events.filter { $0.kind == .memory }
            let thEvents = events.filter { $0.kind == .thermal }
            let totalPressureSec = events.map(\.pressureSeconds).reduce(0, +)
            let worstEvent = events.max(by: { $0.worstLevel < $1.worstLevel }) ?? events[0]
            let isCritical = events.contains {
                ($0.kind == .memory && $0.worstLevel >= 2) || ($0.kind == .thermal && $0.worstLevel >= 2)
            }

            var detailParts: [String] = []
            detailParts.append(String(
                format: String(localized: "stats.r.insight.pressureSummary", defaultValue: "累计出现 %d 次系统压力（内存 %d · 热状态 %d），有效持续 %@"),
                events.count, memEvents.count, thEvents.count, StatisticsDisplayFormat.duration(totalPressureSec)
            ))
            if !memEvents.isEmpty, let peakSwap = maximum(of: rows, keyPath: \.memSwapAvg), peakSwap > 256 * 1024 * 1024 {
                detailParts.append(String(
                    format: String(localized: "stats.r.insight.pressureSwap", defaultValue: "同期 Swap 峰值达 %@"),
                    ReportUIHelper.formatBytes(peakSwap)
                ))
            }
            if !thEvents.isEmpty, let peakTemp = maximum(of: rows, keyPath: \.cpuTempAvg) {
                detailParts.append(String(
                    format: String(localized: "stats.r.insight.pressureTemp", defaultValue: "CPU 温度最高 %.1f°C"),
                    peakTemp
                ))
            }
            if !apps.highLoadAlerts.isEmpty {
                let topNames = apps.highLoadAlerts.prefix(3).map(\.name).joined(separator: "、")
                detailParts.append(String(
                    format: String(localized: "stats.r.insight.pressureApps", defaultValue: "同期高占用应用：%@"),
                    topNames
                ))
            }

            insights.append(ReportInsightItem(
                id: "pressure-attribution",
                systemIcon: "exclamationmark.triangle.fill",
                colorName: isCritical ? "red" : "orange",
                title: String(localized: "stats.r.insight.pressureTitle", defaultValue: "系统压力归因"),
                detail: detailParts.joined(separator: "；"),
                severity: isCritical ? .critical : .warning,
                destination: worstEvent.kind == .memory ? .memory : .thermal,
                focusStart: worstEvent.start,
                focusEnd: worstEvent.end,
                actionTitle: String(localized: "stats.r.insight.actionInspectWindow", defaultValue: "定位压力时段")
            ))
        }

        // 2. 周期环比变化（对比上一等长周期的内存压力、功耗与磁盘写入）
        if !previousRows.isEmpty {
            let span = to.timeIntervalSince(from)
            let prevStart = from.addingTimeInterval(-span)
            let prevCoverage = self.coverageRatio(rows: previousRows, from: prevStart, to: from, systemSleepIntervals: systemSleepIntervals) ?? 0
            if prevCoverage >= 0.3 {
                if let curMemP = weightedAverage(of: rows, keyPath: \.memPressureAvg),
                   let prevMemP = weightedAverage(of: previousRows, keyPath: \.memPressureAvg),
                   abs(curMemP - prevMemP) >= 8.0 {
                    let delta = curMemP - prevMemP
                    let isUp = delta > 0
                    let detail = String(
                        format: String(localized: "stats.r.insight.momMemDetail", defaultValue: "本期平均内存压力 %.0f%%，较上一周期（%.0f%%）%@ %.0f 个百分点"),
                        curMemP,
                        prevMemP,
                        isUp ? String(localized: "stats.r.insight.up", defaultValue: "上升") : String(localized: "stats.r.insight.down", defaultValue: "下降"),
                        abs(delta)
                    )
                    insights.append(ReportInsightItem(
                        id: "mom-memory",
                        systemIcon: isUp ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                        colorName: isUp ? "orange" : "blue",
                        title: String(localized: "stats.r.insight.momMemTitle", defaultValue: "内存压力环比变化"),
                        detail: detail,
                        severity: (isUp && curMemP >= 40) ? .warning : .info,
                        destination: .memory,
                        actionTitle: String(localized: "stats.r.insight.actionViewMemory", defaultValue: "查看内存趋势")
                    ))
                }

                if let curPower = weightedAverage(of: rows, keyPath: \.powerAvg),
                   let prevPower = weightedAverage(of: previousRows, keyPath: \.powerAvg),
                   prevPower > 1.0,
                   abs(curPower - prevPower) / prevPower >= 0.20 {
                    let pct = ((curPower - prevPower) / prevPower) * 100
                    let isUp = pct > 0
                    let detail = String(
                        format: String(localized: "stats.r.insight.momPowerDetail", defaultValue: "平均整机功耗 %.1f W，较上一周期（%.1f W）%@ %.0f%%"),
                        curPower,
                        prevPower,
                        isUp ? String(localized: "stats.r.insight.up", defaultValue: "上升") : String(localized: "stats.r.insight.down", defaultValue: "下降"),
                        abs(pct)
                    )
                    insights.append(ReportInsightItem(
                        id: "mom-power",
                        systemIcon: "bolt.circle.fill",
                        colorName: isUp ? "yellow" : "blue",
                        title: String(localized: "stats.r.insight.momPowerTitle", defaultValue: "整机功耗环比变化"),
                        detail: detail,
                        severity: .info,
                        destination: .power,
                        actionTitle: String(localized: "stats.r.insight.actionViewPower", defaultValue: "查看功耗曲线")
                    ))
                }
            }
        }

        // 3. 内存 Swap 活跃提示（未触发压力事件但 Swap 已升高时提醒）
        if let peakSwap = maximum(of: rows, keyPath: \.memSwapAvg),
           peakSwap >= 512 * 1024 * 1024 {
            let avgSwap = weightedAverage(of: rows, keyPath: \.memSwapAvg) ?? peakSwap
            let isElevated = peakSwap >= 2 * 1024 * 1024 * 1024
            let detail = String(
                format: String(localized: "stats.r.insight.swapDetail", defaultValue: "交换分区 (Swap) 均值 %@，峰值达 %@，说明内存常驻工作集接近物理容量上限"),
                ReportUIHelper.formatBytes(avgSwap),
                ReportUIHelper.formatBytes(peakSwap)
            )
            insights.append(ReportInsightItem(
                id: "swap-activity",
                systemIcon: "memorychip",
                colorName: isElevated ? "orange" : "blue",
                title: String(localized: "stats.r.insight.swapTitle", defaultValue: "交换分区 (Swap) 使用偏高"),
                detail: detail,
                severity: isElevated ? .warning : .info,
                destination: .memory,
                actionTitle: String(localized: "stats.r.insight.actionViewMemory", defaultValue: "查看内存趋势")
            ))
        }

        // 4. 热状态与散热表现（严格遵循 0~3 档位定义，区分无风扇与传感器受限）
        let maxThermal = maximum(of: rows, keyPath: \.cpuThermalAvg)
        let maxTemp = maximum(of: rows, keyPath: \.cpuTempAvg)
        if let thIdx = StatisticsDisplayFormat.thermalLevelIndex(maxThermal), thIdx >= 1 || (maxTemp ?? 0) >= 85 {
            var parts: [String] = []
            if let maxThermal, thIdx >= 1 {
                parts.append(String(
                    format: String(localized: "stats.r.insight.thermalPeakState", defaultValue: "系统热状态最高触及「%@」"),
                    StatisticsDisplayFormat.thermalStateLabel(maxThermal)
                ))
            }
            if let maxTemp {
                parts.append(String(
                    format: String(localized: "stats.r.insight.thermalPeakTemp", defaultValue: "CPU 温度最高 %.1f°C"),
                    maxTemp
                ))
            }
            if !thermal.hasFans {
                parts.append(String(localized: "stats.r.insight.fanlessNote", defaultValue: "当前为被动散热机型"))
            } else if !thermal.fanSensorAvailable {
                parts.append(String(localized: "stats.r.insight.fanUnavailableNote", defaultValue: "当前运行环境未读取风扇转速"))
            } else if let fanMax = thermal.fanMaxRPM, fanMax > 0 {
                parts.append(String(
                    format: String(localized: "stats.r.insight.fanPeakNote", defaultValue: "风扇最高提速至 %.0f RPM"),
                    fanMax
                ))
            }
            insights.append(ReportInsightItem(
                id: "thermal-behavior",
                systemIcon: "flame.fill",
                colorName: thIdx >= 2 ? "red" : "orange",
                title: String(localized: "stats.r.insight.thermalTitle", defaultValue: "温控与散热响应"),
                detail: parts.joined(separator: "，"),
                severity: thIdx >= 2 ? .critical : .warning,
                destination: .thermal,
                actionTitle: String(localized: "stats.r.insight.actionViewThermal", defaultValue: "查看热压力详情")
            ))
        }

        // 5. 电池长期健康与循环变化
        if battery.isSupported, battery.dailyHistory.count >= 2,
           let first = battery.dailyHistory.first,
           let last = battery.dailyHistory.last {
            var parts: [String] = []
            if let latestHealth = last.healthPercent {
                if let firstHealth = first.healthPercent, abs(latestHealth - firstHealth) >= 0.5 {
                    parts.append(String(
                        format: String(localized: "stats.r.insight.battHealthDelta", defaultValue: "最大容量 %.1f%%（期内变化 %+.1f%%）"),
                        latestHealth, latestHealth - firstHealth
                    ))
                } else {
                    parts.append(String(
                        format: String(localized: "stats.r.insight.battHealthLatest", defaultValue: "当前最大容量 %.1f%%"),
                        latestHealth
                    ))
                }
            }
            if let latestCycle = last.cycleCount {
                if let firstCycle = first.cycleCount, latestCycle > firstCycle {
                    parts.append(String(
                        format: String(localized: "stats.r.insight.battCycleDelta", defaultValue: "循环次数 %d 次（期内增加 +%d 次）"),
                        latestCycle, latestCycle - firstCycle
                    ))
                } else {
                    parts.append(String(
                        format: String(localized: "stats.r.insight.battCycleLatest", defaultValue: "当前循环 %d 次"),
                        latestCycle
                    ))
                }
            }
            if !parts.isEmpty {
                insights.append(ReportInsightItem(
                    id: "battery-health",
                    systemIcon: "battery.100",
                    colorName: "green",
                    title: String(localized: "stats.r.insight.battTitle", defaultValue: "电池健康与循环趋势"),
                    detail: parts.joined(separator: "，"),
                    severity: .neutral,
                    destination: .power,
                    actionTitle: String(localized: "stats.r.insight.actionViewPower", defaultValue: "查看电池档案")
                ))
            }
        }

        // 6. 磁盘持续写入强度（大额写入估算日均强度，辅助评估 SSD 磨损）
        if let writeTotal = disk.totalWriteBytes, writeTotal >= 5_000_000_000 {
            let daysSpan = max(1.0, to.timeIntervalSince(from) / 86400.0)
            let dailyAvgWrite = writeTotal / daysSpan
            let detail = String(
                format: String(localized: "stats.r.insight.diskWriteDetail", defaultValue: "期内累计磁盘写入 %@，折合日均写入 %@/天"),
                ReportUIHelper.formatVolume(writeTotal),
                ReportUIHelper.formatVolume(dailyAvgWrite)
            )
            insights.append(ReportInsightItem(
                id: "disk-write-intensity",
                systemIcon: "internaldrive",
                colorName: "blue",
                title: String(localized: "stats.r.insight.diskTitle", defaultValue: "磁盘写入强度"),
                detail: detail,
                severity: dailyAvgWrite >= 50_000_000_000 ? .warning : .info,
                destination: .disk,
                actionTitle: String(localized: "stats.r.insight.actionViewDisk", defaultValue: "查看磁盘 I/O")
            ))
        }

        // 7. 高峰活动时段（优先小时表，单日稀疏时回退当前采样行；高负载仅中性提示，不染红）
        let rhythmRows = !hourlyRows.isEmpty ? hourlyRows : rows
        var hourSlots: [Int: (sum: Double, frames: Int)] = [:]
        for r in rhythmRows {
            guard let cpu = r.cpuAvg, r.n > 0 else { continue }
            let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(r.t)))
            var entry = hourSlots[hour] ?? (0.0, 0)
            entry.sum += cpu * Double(r.n)
            entry.frames += r.n
            hourSlots[hour] = entry
        }
        if let best = hourSlots.max(by: {
            ($0.value.frames > 0 ? $0.value.sum / Double($0.value.frames) : 0) <
            ($1.value.frames > 0 ? $1.value.sum / Double($1.value.frames) : 0)
        }) {
            let avg = best.value.frames > 0 ? best.value.sum / Double(best.value.frames) : 0
            if avg > 5.0 {
                let slotStr = String(format: "%02d:00–%02d:00", best.key, (best.key + 1) % 24)
                let detail = String(
                    format: String(localized: "stats.r.insight.busiestDetail", defaultValue: "%@ 算力活动最集中，该时段 CPU 平均占用 %.1f%%"),
                    slotStr, avg
                )
                insights.append(ReportInsightItem(
                    id: "busiest-hour",
                    systemIcon: "clock",
                    colorName: "blue",
                    title: String(localized: "stats.r.insight.busiestTitle", defaultValue: "活跃高峰时段"),
                    detail: detail,
                    severity: .neutral,
                    destination: .cpu,
                    actionTitle: String(localized: "stats.r.insight.actionViewCpu", defaultValue: "查看处理器趋势")
                ))
            }
        }

        // 8. 数据完整度提醒（仅在覆盖率明显偏低时出现）
        if let coverageRatio, coverageRatio < 0.90 {
            let totalCover = rows.reduce(0.0) { $0 + max(0, coverSeconds(for: $1)) }
            let detail = String(
                format: String(localized: "stats.r.coverageInsight", defaultValue: "所选时段累计有效采样 %@，清醒时间覆盖率 %.1f%%（已排除系统确认的休眠）"),
                ReportUIHelper.formatHours(totalCover), coverageRatio * 100
            )
            insights.append(ReportInsightItem(
                id: "coverage-caveat",
                systemIcon: "info.circle",
                colorName: "gray",
                title: String(localized: "stats.r.insight.coverageTitle", defaultValue: "监测覆盖存在空缺"),
                detail: detail,
                severity: .info,
                destination: .details,
                actionTitle: String(localized: "stats.r.insight.actionViewDetails", defaultValue: "查看采样记录")
            ))
        }

        return insights
    }

    // MARK: - 预计算图表序列缓存

    static func buildChartCache(rows: [StatisticsRow], granularity: ReportSourceGranularity) -> ReportChartCache {
        let bucketSec = granularity.bucketSeconds
        func series(
            _ keyPath: KeyPath<StatisticsRow, Double?>,
            id: String,
            transform: ((Double) -> Double)? = nil
        ) -> ReportChartSeries {
            let pts = buildTimeSeries(
                rows: rows,
                keyPath: keyPath,
                seriesID: id,
                granularitySeconds: bucketSec,
                transform: transform
            )
            return ReportChartSeries.from(pts, seriesID: id)
        }

        let toGiB: (Double) -> Double = { $0 / 1_073_741_824.0 }
        let toMiB: (Double) -> Double = { $0 / 1_048_576.0 }
        let toDecimalMBps: (Double) -> Double = { rateFromTotal(totalBytes: $0, bucketSeconds: bucketSec) / 1_000_000.0 }

        return ReportChartCache(
            cpuAvg: series(\.cpuAvg, id: "cpuAvg"),
            cpuPeak: series(\.cpuMax, id: "cpuPeak"),
            cpuP: series(\.cpuPAvg, id: "cpuP"),
            cpuE: series(\.cpuEAvg, id: "cpuE"),
            gpuAvg: series(\.gpuAvg, id: "gpuAvg"),
            gpuPeak: series(\.gpuMax, id: "gpuPeak"),
            gpuVramMB: series(\.gpuMemAvg, id: "gpuVram", transform: toMiB),
            memUsedGB: series(\.memUsedAvg, id: "memUsed", transform: toGiB),
            memCompressedGB: series(\.memCompAvg, id: "memComp", transform: toGiB),
            memPressure: series(\.memPressureAvg, id: "memPressure"),
            memSwapMB: series(\.memSwapAvg, id: "memSwap", transform: toMiB),
            netDownMBps: series(\.netDown, id: "netDown", transform: toDecimalMBps),
            netUpMBps: series(\.netUp, id: "netUp", transform: toDecimalMBps),
            diskReadMBps: series(\.diskRead, id: "diskRead", transform: toDecimalMBps),
            diskWriteMBps: series(\.diskWrite, id: "diskWrite", transform: toDecimalMBps),
            powerWatts: series(\.powerAvg, id: "power"),
            batteryLevel: series(\.battLevelAvg, id: "battLevel"),
            batteryTemp: series(\.battTempAvg, id: "battTemp"),
            cpuTemp: series(\.cpuTempAvg, id: "cpuTemp"),
            thermalState: series(\.cpuThermalAvg, id: "thermalState"),
            fanRPM: series(\.fanAvg, id: "fan"),
            memUsagePct: series(\.memPctAvg, id: "memUsagePct")
        )
    }

    // MARK: - 每日汇总表聚合 (供单测保留，主聚合不再无谓重复计算)

    static func aggregateDailySummary(
        minutes: [StatisticsRow],
        hours: [StatisticsRow],
        days: [StatisticsRow],
        from: Date,
        to: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [ReportDailySummaryRow] {
        var dayMap: [Date: StatisticsRow] = [:]
        for r in days {
            let d = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(r.t)))
            dayMap[d] = r
        }

        var results: [ReportDailySummaryRow] = []
        var currentDay = calendar.startOfDay(for: from)
        let endDay = calendar.startOfDay(for: to)
        let today = calendar.startOfDay(for: now)

        while currentDay <= endDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay.addingTimeInterval(86400)
            var targetRow = dayMap[currentDay]

            if targetRow == nil && currentDay == today {
                let dayMinutes = filterRows(minutes, from: currentDay, to: min(nextDay, now))
                if !dayMinutes.isEmpty {
                    targetRow = aggregateRows(dayMinutes, timestamp: Int64(currentDay.timeIntervalSince1970))
                }
            }

            if targetRow == nil {
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

        // 上一等长周期（用于洞察中的周期环比分析）
        let span = to.timeIntervalSince(from)
        let prevFrom = from.addingTimeInterval(-span)
        let prevGranularity = pickSource(
            from: prevFrom,
            to: from,
            minutes: snapshot.minutes,
            hours: snapshot.hours,
            days: snapshot.days
        )
        let prevSourceRows: [StatisticsRow] = switch prevGranularity {
        case .minutes: snapshot.minutes
        case .hours: snapshot.hours
        case .days: snapshot.days
        }
        let previousFiltered = filterRows(prevSourceRows, from: prevFrom, to: from)

        let coverageRatioValue = coverageRatio(rows: filtered, from: from, to: to, systemSleepIntervals: snapshot.systemSleepIntervals)
        let coveredSeconds = filtered.reduce(0.0) { $0 + max(0, coverSeconds(for: $1)) }

        let apps = aggregateApps(
            processData: snapshot.process,
            from: from,
            to: to,
            isDirect: snapshot.meta.isDirect,
            calendar: calendar
        )
        let appsHasRangeData = !apps.cpuList.isEmpty || !apps.memList.isEmpty
            || !apps.gpuList.isEmpty || !apps.diskList.isEmpty || !apps.netList.isEmpty

        let quality = dataQuality(
            rows: filtered,
            coverageRatio: coverageRatioValue,
            granularity: granularity,
            appsEstimateLeadingSample: appsHasRangeData
        )

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
            hardwareHasBattery: hardwareHasBattery,
            calendar: calendar
        )
        let thermal = computeThermalMetrics(
            rows: filtered,
            hardwareHasFans: hardwareHasFans,
            fanSensorAvailable: fanSensorAvailable
        )
        let events = deriveAlertEvents(rows: filtered, source: granularity, now: snapshot.capturedAt)
        let insights = generateInsights(
            rows: filtered,
            hourlyRows: hourlyFiltered,
            previousRows: previousFiltered,
            source: granularity,
            from: from,
            to: to,
            coverageRatio: coverageRatioValue,
            events: events,
            apps: apps,
            battery: battery,
            thermal: thermal,
            disk: disk,
            systemSleepIntervals: snapshot.systemSleepIntervals,
            calendar: calendar
        )

        // R06: 7x24 热力图始终使用小时数据输入
        let heatmap = range == .today ? nil : buildHeatmap(hourlyRows: hourlyFiltered, calendar: calendar)
        let chartCache = buildChartCache(rows: filtered, granularity: granularity)

        return ReportActiveRangeModel(
            range: range,
            granularity: granularity,
            from: from,
            to: to,
            isSingleDay: isSingleDay,
            rows: filtered,
            coverageRatio: coverageRatioValue,
            quality: quality,
            coveredSeconds: coveredSeconds,
            updatedAt: snapshot.capturedAt,
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
            dailySummaryRows: [],
            chartCache: chartCache
        )
    }

    private static func parseDayKey(_ day: Int64, calendar: Calendar = .current) -> Date {
        let y = Int(day / 10000)
        let m = Int((day % 10000) / 100)
        let d = Int(day % 100)
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return calendar.date(from: components) ?? Date()
    }
}
