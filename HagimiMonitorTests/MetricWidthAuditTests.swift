import AppKit
import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 指标格宽度审计:各语言「标签宽 + 最坏值宽」必须落在该语言判定为
/// 半行的半格预算内。审计口径与渲染一致(字体、间距取 StaticMetricSizing /
/// MetricGridMetrics),数据源是 Localizable.xcstrings 与 auditInventory
/// 登记表。整行/半行的布局决策在 fullRowMetricIDsByLanguage:从某语言
/// 登记中移除条目,该语言立即恢复半行审计——放不下会被拦截,登记即
/// 布局决策。
struct MetricWidthAuditTests {
    private let languages = ["zh-Hans", "en"]

    /// xcstrings 源文件:测试文件位于 HagimiMonitorTests/,仓库根为上两级。
    private let xcstringsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")

    private func localized(_ key: String, _ lang: String) throws -> String {
        let data = try Data(contentsOf: xcstringsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let value = (json?["strings"] as? [String: Any])?[key]
            .flatMap { $0 as? [String: Any] }?["localizations"]
            .flatMap { $0 as? [String: Any] }?[lang]
            .flatMap { $0 as? [String: Any] }?["stringUnit"]
            .flatMap { $0 as? [String: Any] }?["value"]
            .flatMap { $0 as? String }
        #expect(value != nil, "缺少本地化:\(key) [\(lang)]")
        return value ?? "<缺失:\(key)>"
    }

    /// 与渲染同规格的单行文本宽度。
    private func width(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// 值段宽度:数字 + 2pt 间距 + 单位(splitValue 的 HStack spacing)。
    private func valueWidth(_ worst: StaticMetricSizing.WorstValue) -> CGFloat {
        var result = width(worst.number, font: StaticMetricSizing.valueFont)
        if let unit = worst.unit {
            result += 2 + width(unit, font: StaticMetricSizing.unitFont)
        }
        return result
    }

    private func isHalfRow(_ entry: StaticMetricSizing.AuditEntry, language: String) -> Bool {
        !StaticMetricSizing.isFullRow(kind: entry.kind, name: entry.name, language: language)
    }

    @Test func measuredMetricsFitBudgetInHalfRowLanguages() throws {
        let budget = StaticMetricSizing.halfCellContentWidth
        let spacing = StaticMetricSizing.cellHorizontalSpacing

        for entry in StaticMetricSizing.auditInventory {
            guard case let .measured(worst) = entry.layout else { continue }
            for lang in languages where isHalfRow(entry, language: lang) {
                let label = try localized(entry.labelKey, lang)
                let total = width(label, font: StaticMetricSizing.labelFont)
                    + spacing + valueWidth(worst)
                #expect(total <= budget, """
                [\(lang)] \(entry.kind.rawValue).\(entry.name) 超预算:\
                「\(label)」+「\(worst.number)\(worst.unit.map { " \($0)" } ?? "")」\
                = \(Int(total))pt > \(Int(budget))pt
                """)
            }
        }
    }

    @Test func enumMetricsFitBudgetInHalfRowLanguages() throws {
        let budget = StaticMetricSizing.halfCellContentWidth
        let spacing = StaticMetricSizing.cellHorizontalSpacing

        for entry in StaticMetricSizing.auditInventory {
            guard case let .enumMeasured(valueKeys) = entry.layout else { continue }
            for lang in languages where isHalfRow(entry, language: lang) {
                // 最坏值 = 该语言下最长的枚举文案
                let candidates = try valueKeys.map { try localized($0, lang) }
                let worst = candidates.max {
                    width($0, font: StaticMetricSizing.valueFont) < width($1, font: StaticMetricSizing.valueFont)
                } ?? ""
                let label = try localized(entry.labelKey, lang)
                let total = width(label, font: StaticMetricSizing.labelFont)
                    + spacing + width(worst, font: StaticMetricSizing.valueFont)
                #expect(total <= budget, """
                [\(lang)] \(entry.kind.rawValue).\(entry.name) 超预算:\
                「\(label)」+「\(worst)」= \(Int(total))pt > \(Int(budget))pt
                """)
            }
        }
    }

    /// 整行登记(结构性 + 各语言)中的每个键都必须有对应的审计条目。
    @Test func registryKeysCoveredByAuditInventory() {
        let auditKeys = Set(StaticMetricSizing.auditInventory.map { "\($0.kind.rawValue).\($0.name)" })
        var registryKeys = StaticMetricSizing.structuralFullRowMetricIDs
        for set in StaticMetricSizing.fullRowMetricIDsByLanguage.values {
            registryKeys.formUnion(set)
        }
        for key in registryKeys {
            #expect(auditKeys.contains(key), "整行登记 \(key) 缺少 auditInventory 条目")
        }
    }

    /// 网格外特殊形态不得出现在任何整行登记中。
    @Test func specialFormEntriesStayOutOfRegistries() {
        for entry in StaticMetricSizing.auditInventory {
            guard case .specialForm = entry.layout else { continue }
            let key = "\(entry.kind.rawValue).\(entry.name)"
            #expect(!StaticMetricSizing.structuralFullRowMetricIDs.contains(key), """
            \(key) 是网格外形态,不应登记结构性整行
            """)
            for (language, set) in StaticMetricSizing.fullRowMetricIDsByLanguage {
                #expect(!set.contains(key), """
                \(key) 是网格外形态,不应出现在 [\(language)] 整行登记
                """)
            }
        }
    }

    /// 所有审计条目的标签键两语齐备(压缩改文案时防漏删)。
    @Test func everyAuditLabelExistsInAllLanguages() throws {
        for entry in StaticMetricSizing.auditInventory {
            for lang in languages {
                _ = try localized(entry.labelKey, lang)
            }
        }
    }
}
