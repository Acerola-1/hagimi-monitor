import Foundation

func percent(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

func bytes(_ value: Double) -> String {
    byteFormatter.string(fromByteCount: Int64(max(0, value)))
}

func memoryBytes(_ value: Double) -> String {
    memoryByteFormatter.string(fromByteCount: Int64(max(0, value)))
}

func wattString(_ value: Double?, rounded: Bool = false) -> String {
    guard let value else {
        return "--"
    }
    if rounded {
        return "\(Int(value.rounded())) W"
    }
    return "\(String(format: "%.1f", value)) W"
}

func wattStringAllowZero(_ value: Double?) -> String {
    guard let value else {
        return "--"
    }
    return value == 0 ? "0 W" : "\(String(format: "%.1f", value)) W"
}

func nonZeroWatts(_ value: Double?) -> Double? {
    guard let value, value >= 0.05 else {
        return nil
    }
    return value
}

private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter
}()

private let memoryByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .memory
    return formatter
}()

func bytesPerSecond(_ value: Double) -> String {
    let safeValue = max(0, value)
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var scaled = safeValue
    var unitIndex = 0

    while scaled >= 1024, unitIndex < units.count - 1 {
        scaled /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(Int(scaled.rounded())) \(units[unitIndex])"
    }
    return "\(String(format: scaled >= 10 ? "%.0f" : "%.1f", scaled)) \(units[unitIndex])"
}

func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
        value
    case let value as Float:
        Double(value)
    case let value as Int:
        Double(value)
    case let value as Int64:
        Double(value)
    case let value as UInt64:
        Double(value)
    case let value as NSNumber:
        value.doubleValue
    default:
        nil
    }
}

func signedDoubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Int:
        return Double(value)
    case let value as Int64:
        return Double(value)
    case let value as UInt64:
        if value > UInt64(Int64.max) {
            return Double(Int64(bitPattern: value))
        }
        return Double(value)
    case let value as NSNumber:
        let unsigned = value.uint64Value
        if unsigned > UInt64(Int64.max) {
            return Double(Int64(bitPattern: unsigned))
        }
        return value.doubleValue
    default:
        return doubleValue(value)
    }
}

func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
        value
    case let value as Int64:
        Int(value)
    case let value as UInt64:
        Int(value)
    case let value as NSNumber:
        value.intValue
    default:
        nil
    }
}

func placeholderModule(_ kind: MonitorKind, summary: String) -> MonitorModule {
    MonitorModule(
        kind: kind,
        value: 0,
        summary: summary,
        metrics: [
            MonitorMetric(name: "status", value: "unknown"),
            MonitorMetric(name: "data", value: "--"),
            MonitorMetric(name: "update", value: "--")
        ],
        samples: seedSamples(0)
    )
}

func seedSamples(_ value: Double) -> [Double] {
    Array(repeating: min(100, max(0, value)), count: 28)
}
