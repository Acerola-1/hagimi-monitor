import Foundation

/// 健康度采用系统报告的「最大容量」，不从电池芯片容量反推或再次平滑。
/// 进程读取只在独立队列按需进行；采样线程始终立即取得有时限的缓存。
nonisolated final class BatteryHealthProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cache = Cache()
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.battery-health", qos: .utility)
    private let load: @Sendable () -> [[String: Any]]?
    private let now: @Sendable () -> Date

    init(
        load: @escaping @Sendable () -> [[String: Any]]? = {
            SystemProfilerRunner.shared.items(for: "SPPowerDataType")
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.load = load
        self.now = now
    }

    func percent() -> Double? {
        let date = now()
        lock.lock()
        let value = cache.value(at: date)
        let shouldRefresh = cache.beginRefresh(at: date)
        lock.unlock()

        if shouldRefresh {
            queue.async { [self] in
                let items = load()
                let percent = items.flatMap(Self.parse)
                lock.lock()
                cache.finishRefresh(percent: percent, failed: items == nil, at: now())
                lock.unlock()
            }
        }
        return value.map(Double.init)
    }

    /// 只接收内置电池的系统百分比；容量、电量、适配器及 UPS 条目不能充当健康度。
    static func parse(_ items: [[String: Any]]) -> Int? {
        for item in items {
            if item["_name"] as? String == "spbattery_information",
               let health = item["sppower_battery_health_info"] as? [String: Any],
               let value = parsePercent(health["sppower_battery_health_maximum_capacity"]) {
                return value
            }
            if let children = item["_items"] as? [[String: Any]], let value = parse(children) {
                return value
            }
        }
        return nil
    }

    private static func parsePercent(_ raw: Any?) -> Int? {
        let value: Int?
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasSuffix("%") else { return nil }
            value = Int(trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let number = raw as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,
                  (0...100).contains(number.doubleValue) {
            value = number.intValue
        } else {
            return nil
        }
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    /// 成功结果每五分钟更新；失败一分钟后重试，旧结果最多保留十五分钟。
    /// 成功报告若已没有健康度则立即清除，不把换电池或字段缺失伪装成旧读数。
    struct Cache {
        private var percent: Int?
        private var sampledAt: Date?
        private var nextRefreshAt = Date.distantPast
        private var refreshing = false

        func value(at date: Date) -> Int? {
            guard let sampledAt, (0..<900).contains(date.timeIntervalSince(sampledAt)) else { return nil }
            return percent
        }

        mutating func beginRefresh(at date: Date) -> Bool {
            guard !refreshing, date >= nextRefreshAt else { return false }
            refreshing = true
            return true
        }

        mutating func finishRefresh(percent: Int?, failed: Bool, at date: Date) {
            refreshing = false
            if !failed {
                self.percent = percent
                sampledAt = date
            }
            nextRefreshAt = date.addingTimeInterval(failed ? 60 : 300)
        }
    }
}
