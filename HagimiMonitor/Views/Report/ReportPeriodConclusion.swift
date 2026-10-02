import Foundation

/// 所选时段的综合结论模型。根据已观测到的系统压力事件、覆盖时长与数据质量生成文本结论。
nonisolated enum ReportPeriodConclusion: Sendable, Equatable {

    enum Kind: Sendable, Equatable {
        /// 没有有效观测，无法判断。
        case noObservation
        /// 观测不足，无法给出结论。
        case insufficient
        /// 观测充分且未发现系统压力。
        case calm
        /// 发现系统压力事件。
        case pressure
    }

    struct Summary: Sendable, Equatable {
        let kind: Kind
        /// 主句（已本地化）。
        let headline: String
        /// 补充说明：压力类型/数量、覆盖限制或不可判断的原因。
        let detail: String?
        /// 是否需要以警示语气呈现（仅真实系统压力为真）。
        let isElevated: Bool
    }

    /// 生成时段结论。
    ///
    /// - Parameters:
    ///   - events: 本期的系统压力事件（内存/热）。
    ///   - appAlertCount: 本期高占用应用数。它只作为补充信息，不与系统压力混为一谈。
    ///   - coveredSeconds: 本期有效观测秒数。
    ///   - quality: 本期质量标记，用于说明部分覆盖或旧版估算。
    ///   - minimumCoverageSeconds: 判定「观测不足」的下限，与设置页保持一致语义。
    static func summary(
        events: [ReportEventItem],
        appAlertCount: Int,
        coveredSeconds: Double,
        quality: StatisticsDataQuality,
        minimumCoverageSeconds: Double = 30 * 60
    ) -> Summary {
        var parts: [String] = []

        // 系统压力事件优先陈述。
        let memoryEvents = events.filter { $0.kind == .memory }
        let thermalEvents = events.filter { $0.kind == .thermal }
        if !memoryEvents.isEmpty || !thermalEvents.isEmpty {
            var kinds: [String] = []
            if !memoryEvents.isEmpty {
                kinds.append(String(localized: "stats.r.alertMem"))
            }
            if !thermalEvents.isEmpty {
                kinds.append(String(localized: "stats.r.alertThermal"))
            }
            let detail = String(
                format: String(localized: "stats.report.conclusion.pressureDetail"),
                kinds.joined(separator: String(localized: "stats.report.conclusion.and")),
                memoryEvents.count + thermalEvents.count
            )
            parts.append(detail)
            appendSupplement(&parts, appAlertCount: appAlertCount, quality: quality)
            return Summary(
                kind: .pressure,
                headline: String(localized: "stats.report.conclusion.pressure"),
                detail: parts.joined(separator: " · "),
                isElevated: true
            )
        }

        // 区分无有效观测与观测时长不足。
        if quality.contains(.noObservation) || coveredSeconds <= 0 {
            return Summary(
                kind: .noObservation,
                headline: String(localized: "stats.report.conclusion.noObservation"),
                detail: String(localized: "stats.report.conclusion.noObservationDetail"),
                isElevated: false
            )
        }
        if coveredSeconds < minimumCoverageSeconds {
            return Summary(
                kind: .insufficient,
                headline: String(localized: "stats.report.conclusion.insufficient"),
                detail: String(
                    format: String(localized: "stats.report.conclusion.recorded"),
                    StatisticsDisplayFormat.duration(coveredSeconds)
                ),
                isElevated: false
            )
        }

        // 观测充分且无系统压力事件。
        appendSupplement(&parts, appAlertCount: appAlertCount, quality: quality)
        return Summary(
            kind: .calm,
            headline: String(localized: "stats.report.conclusion.calm"),
            detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            isElevated: false
        )
    }

    /// 追加高占用应用数量与数据质量限制等补充说明。
    private static func appendSupplement(
        _ parts: inout [String],
        appAlertCount: Int,
        quality: StatisticsDataQuality
    ) {
        if appAlertCount > 0 {
            parts.append(String(format: String(localized: "stats.report.conclusion.appsNote"), appAlertCount))
        }
        if quality.contains(.legacyDailyEstimate) {
            parts.append(String(localized: "stats.quality.legacyDaily"))
        } else if quality.contains(.partialCoverage) {
            parts.append(String(localized: "stats.quality.partial"))
        }
    }
}
