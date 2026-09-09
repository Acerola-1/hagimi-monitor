import Foundation

// MARK: - 通信事件(10.4)

/// 一次 DDC 通信事件(诊断记录)。
nonisolated struct DisplayDiagnosticEvent: Equatable, Sendable {
    /// 关联操作与连接代次。
    let requestID: UInt64
    /// 连接代次。
    let generation: UInt64
    let timestamp: Date
    /// 耗时(秒)。
    let duration: TimeInterval
    /// 属性/操作。
    let operation: String
    /// 控制后端。
    let backend: String?
    /// 值来源。
    let source: String?
    /// 目标/结果百分比。
    let percent: Double?
    /// 原始范围。
    let range: UInt16?
    /// 错误码(成功为 nil)。
    let errorCode: Int?
    /// 结构化错误描述。
    let errorMessage: String?
    /// 门禁原因。
    let gateReason: String?
    /// 是否超时。
    let timedOut: Bool
}

// MARK: - 环形缓冲(10.4)

/// 每连接最近 N 条事件的有界环形缓冲。1000 事件只保留最新 100 条。
nonisolated final class DisplayDiagnosticsLog {
    private let capacity: Int
    private var events: [DisplayDiagnosticEvent] = []
    private let lock = NSLock()

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    func append(_ event: DisplayDiagnosticEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    func recent() -> [DisplayDiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        events.removeAll()
    }
}

// MARK: - 结构化导出(10.4/10.5)

/// 诊断导出:结构化文本,默认脱敏,不自动上传。
nonisolated enum DisplayDiagnosticsExporter {
    /// 生成可复制的诊断文本。
    /// - Parameters:
    ///   - appVersion: 应用版本。
    ///   - osVersion: 系统版本。
    ///   - architecture: 芯片架构。
    ///   - schemaVersion: 导出 schema 版本。
    ///   - displaySummary: 脱敏后的显示器身份摘要。
    ///   - events: 通信事件。
    static func export(
        appVersion: String,
        osVersion: String,
        architecture: String,
        schemaVersion: Int,
        displaySummary: String,
        events: [DisplayDiagnosticEvent]
    ) -> String {
        var lines: [String] = []
        lines.append("HagimiMonitor 显示器诊断")
        lines.append("schemaVersion: \(schemaVersion)")
        lines.append("app: \(appVersion)")
        lines.append("os: \(osVersion)")
        lines.append("arch: \(architecture)")
        lines.append("display: \(displaySummary)")
        lines.append("--- 通信事件 ---")
        for event in events {
            var parts: [String] = []
            parts.append("req=\(event.requestID)")
            parts.append("gen=\(event.generation)")
            parts.append("op=\(event.operation)")
            if let backend = event.backend { parts.append("backend=\(backend)") }
            if let source = event.source { parts.append("source=\(source)") }
            if let percent = event.percent { parts.append(String(format: "pct=%.1f", percent)) }
            if let range = event.range { parts.append("range=\(range)") }
            parts.append(String(format: "dur=%.3fs", event.duration))
            if let code = event.errorCode { parts.append("err=\(code)") }
            if let message = event.errorMessage { parts.append("msg=\(message)") }
            if let gate = event.gateReason { parts.append("gate=\(gate)") }
            if event.timedOut { parts.append("timeout") }
            lines.append(parts.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
