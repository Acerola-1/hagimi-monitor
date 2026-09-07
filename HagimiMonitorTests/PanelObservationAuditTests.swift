import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 面板树观察源审计:面板视图的失效信号统一经 PanelRefreshGate 门控
/// (隐藏期冻结视图树、呼出补发追平),任何视图直接观察 MonitorStore
/// 都会绕过门控——隐藏态面板随每次采样发布重算,门控形同虚设。
/// 面板根 MonitorPanelView 对 store 只持普通引用,失效源仅 refreshGate;
/// 构建期扫描拦截新增的直接观察。
struct PanelObservationAuditTests {
    /// 扫描范围:面板根视图与面板框架组件目录。
    /// 测试文件位于 HagimiMonitorTests/,仓库根为上两级。
    private let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("HagimiMonitor")

    /// 观察包装器 × MonitorStore 类型。按类型名匹配而非属性名——
    /// 面板树里有属性名为 store、类型为 QuickToolsStore 的观察,按属性名会误报。
    private let observationPattern = try! NSRegularExpression(
        pattern: #"@(ObservedObject|StateObject|EnvironmentObject)\b[^\n]*\bMonitorStore\b"#
    )

    private func panelSourceFiles() throws -> [URL] {
        var files = [sourceRoot.appendingPathComponent("MonitorPanelView.swift")]
        let panelDir = sourceRoot.appendingPathComponent("Views/Panel")
        let names = try FileManager.default.contentsOfDirectory(atPath: panelDir.path)
        files += names
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { panelDir.appendingPathComponent($0) }
        return files
    }

    @Test func panelTreeHasNoDirectMonitorStoreObservation() throws {
        for file in try panelSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                #expect(
                    observationPattern.firstMatch(in: line, range: range) == nil,
                    "面板树出现对 MonitorStore 的直接观察,隐藏态门控被打穿:\(file.lastPathComponent):\(index + 1)"
                )
            }
        }
    }
}
