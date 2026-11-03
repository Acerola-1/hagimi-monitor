import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 中英文格式占位符必须在同一位置接受同一类型。
/// 高负载通知的时长是带单位的字符串，占位符用 `%@`。
struct LocalizationFormatAgreementTests {
    private let xcstringsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")

    @Test func englishAndChineseFormatSpecifiersAgree() throws {
        let strings = try loadStrings()
        var mismatches: [String] = []
        for (key, entry) in strings {
            guard let locations = entry["localizations"] as? [String: Any] else { continue }
            let english = stringValue(locations["en"])
            let chinese = stringValue(locations["zh-Hans"])
            guard let english, let chinese else { continue }
            let englishSignature = formatSignature(english)
            let chineseSignature = formatSignature(chinese)
            if englishSignature != chineseSignature {
                mismatches.append("\(key): en \(englishSignature) / zh \(chineseSignature)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
    }

    @Test func highLoadNotificationSeparatesDurationFromAverage() throws {
        let strings = try loadStrings()
        let usage = ProcessAlertCenter.notificationUsageText(
            StatisticsDisplayFormat.applicationObservationValue(
                4 * StatisticsMetricDefinition.gibibyte,
                metric: .memory
            )
        )
        #expect(usage == "4 GB")

        let chineseTitle = try #require(localized(strings, "alert.process.highload.memory.title", "zh-Hans"))
        let chineseBody = try #require(localized(strings, "alert.process.highload.body", "zh-Hans"))
        let chinese = ProcessAlertCenter.highLoadNotificationCopy(
            name: "Dia",
            duration: "2 分钟",
            usage: usage,
            titleFormat: chineseTitle,
            bodyFormat: chineseBody
        )
        #expect(chinese.title == "Dia 内存占用偏高")
        #expect(chinese.body == "已持续 2 分钟，平均约 4 GB。")

        let englishTitle = try #require(localized(strings, "alert.process.highload.memory.title", "en"))
        let englishBody = try #require(localized(strings, "alert.process.highload.body", "en"))
        let english = ProcessAlertCenter.highLoadNotificationCopy(
            name: "Dia",
            duration: "2 min",
            usage: usage,
            titleFormat: englishTitle,
            bodyFormat: englishBody
        )
        #expect(english.title == "Dia’s memory use is high")
        #expect(english.body == "High for 2 min, averaging about 4 GB.")

        for key in [
            "alert.process.highload.cpu.title",
            "alert.process.highload.gpu.title",
            "alert.process.highload.network.title",
        ] {
            #expect(localized(strings, key, "zh-Hans") != nil)
            #expect(localized(strings, key, "en") != nil)
        }
    }

    private func localized(_ strings: [String: [String: Any]], _ key: String, _ language: String) -> String? {
        let locations = strings[key]?["localizations"] as? [String: Any]
        return stringValue(locations?[language])
    }

    private func loadStrings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: xcstringsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(json?["strings"] as? [String: [String: Any]])
    }

    private func stringValue(_ localization: Any?) -> String? {
        ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// 位置 → 转换符。无编号的占位符按出现顺序记为 1、2、3。`%%` 忽略。
    private func formatSignature(_ value: String) -> [Int: String] {
        let source = value.replacingOccurrences(of: "%%", with: "")
        guard let regex = try? NSRegularExpression(
            pattern: #"%(\d+\$)?[-+0#]*(?:\d+)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDuUfFeEgGxXoOscCp])"#
        ) else {
            return [:]
        }
        let range = NSRange(source.startIndex..., in: source)
        var signature: [Int: String] = [:]
        var nextPosition = 1
        for match in regex.matches(in: source, range: range) {
            let type = Range(match.range(at: 2), in: source).map { String(source[$0]) } ?? "?"
            let position: Int
            if let positionRange = Range(match.range(at: 1), in: source) {
                let raw = source[positionRange].dropLast()
                position = Int(raw) ?? nextPosition
            } else {
                position = nextPosition
                nextPosition += 1
            }
            signature[position] = type
        }
        return signature
    }
}
