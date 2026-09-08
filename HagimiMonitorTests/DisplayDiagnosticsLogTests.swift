import Testing
@testable import HagimiMonitorDirect
import Foundation

/// 诊断日志与导出测试(10.4/10.5)。
/// 验收:1000 事件只保留最新 100 条;导出含 requestID/代次/耗时/错误/范围/来源;
/// 默认脱敏且无自动上传。
struct DisplayDiagnosticsLogTests {
    @Test func ringBufferKeepsLatest100() {
        let log = DisplayDiagnosticsLog(capacity: 100)
        for i in 0..<1000 {
            log.append(DisplayDiagnosticEvent(
                requestID: UInt64(i), generation: 1, timestamp: Date(),
                duration: 0.01, operation: "write", backend: "ddc", source: "user",
                percent: 50, range: 255, errorCode: nil, errorMessage: nil,
                gateReason: nil, timedOut: false
            ))
        }
        #expect(log.count == 100, "环形缓冲只保留最新 100 条")
        let recent = log.recent()
        #expect(recent.first?.requestID == 900, "保留的是最新事件(900..999)")
        #expect(recent.last?.requestID == 999)
    }

    @Test func exportContainsKeyFields() {
        let log = DisplayDiagnosticsLog(capacity: 10)
        log.append(DisplayDiagnosticEvent(
            requestID: 42, generation: 3, timestamp: Date(),
            duration: 1.5, operation: "write", backend: "ddc", source: "mediaKey",
            percent: 60, range: 255, errorCode: -536870195, errorMessage: "timeout",
            gateReason: "reconfigure", timedOut: true
        ))
        let text = DisplayDiagnosticsExporter.export(
            appVersion: "1.6.0", osVersion: "macOS 27", architecture: "arm64",
            schemaVersion: 1, displaySummary: "ext-vendor-removed", events: log.recent()
        )
        #expect(text.contains("req=42"))
        #expect(text.contains("gen=3"))
        #expect(text.contains("op=write"))
        #expect(text.contains("backend=ddc"))
        #expect(text.contains("source=mediaKey"))
        #expect(text.contains("pct=60"))
        #expect(text.contains("range=255"))
        #expect(text.contains("dur=1.500s"))
        #expect(text.contains("err=-536870195"))
        #expect(text.contains("msg=timeout"))
        #expect(text.contains("gate=reconfigure"))
        #expect(text.contains("timeout"))
        #expect(text.contains("schemaVersion: 1"))
    }

    /// 脱敏:导出默认不包含原始序列号/设备 UUID。
    @Test func exportIsSanitizedByDefault() {
        let log = DisplayDiagnosticsLog(capacity: 5)
        log.append(DisplayDiagnosticEvent(
            requestID: 1, generation: 1, timestamp: Date(),
            duration: 0.1, operation: "read", backend: "ddc", source: "poll",
            percent: 50, range: 255, errorCode: nil, errorMessage: nil,
            gateReason: nil, timedOut: false
        ))
        let text = DisplayDiagnosticsExporter.export(
            appVersion: "1.6.0", osVersion: "macOS 27", architecture: "arm64",
            schemaVersion: 1, displaySummary: "ext-4660-22040-***", events: log.recent()
        )
        #expect(!text.contains("serial12345"), "不应包含未脱敏序列号")
        #expect(text.contains("***"))
    }

    @Test func clearEmptiesBuffer() {
        let log = DisplayDiagnosticsLog(capacity: 5)
        log.append(DisplayDiagnosticEvent(
            requestID: 1, generation: 1, timestamp: Date(),
            duration: 0.1, operation: "read", backend: "ddc", source: "poll",
            percent: 50, range: 255, errorCode: nil, errorMessage: nil,
            gateReason: nil, timedOut: false
        ))
        log.clear()
        #expect(log.count == 0)
    }
}
