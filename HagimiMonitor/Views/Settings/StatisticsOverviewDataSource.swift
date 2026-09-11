import Combine
import Foundation
import OSLog

/// 设置页统计摘要的验证夹具:从 JSON 读入构造好的统计行,供状态验收(正常/事件/
/// 数据不足/观测中断/无数据/部分缺失)在真机上逐项目测。只作为摘要页的数据来源,
/// 不写入采样与统计链路,也不影响记录器与报表。由环境变量启用:
///   HAGIMI_STATS_FIXTURE=/path/to/scenarios.json
///   HAGIMI_STATS_SCENARIO=<场景名>(缺省取文件内第一个场景)
struct StatisticsOverviewFixture {
    /// 场景内的行按「距当前多少分钟/小时」书写,载入时换算成绝对时间,
    /// 保证「当前状态」的新鲜度判断与真实运行一致。
    let loadedAt: Date
    let rows: [StatisticsOverviewRange: StatisticsRow?]
    let series: [StatisticsOverviewRange: [StatisticsRow]]
    /// 「当前状态」场景的最后一次观测:该行尚未接入摘要页展示,夹具先备好数据,
    /// 接入时直接喂 StatisticsOverviewModel.currentStatus。
    let latest: StatisticsRow?

    static func loadFromEnvironment() -> StatisticsOverviewFixture? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["HAGIMI_STATS_FIXTURE"], !path.isEmpty else { return nil }
        do {
            return try load(path: path, scenario: environment["HAGIMI_STATS_SCENARIO"])
        } catch {
            AppLogger.sampler.error("Statistics fixture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func load(path: String, scenario: String?) throws -> StatisticsOverviewFixture {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let scenarios = root["scenarios"] as? [String: Any], !scenarios.isEmpty else {
            throw FixtureError.missingScenarios
        }
        let key = scenario.flatMap { scenarios[$0] != nil ? $0 : nil } ?? scenarios.keys.sorted().first!
        guard let selected = scenarios[key] as? [String: Any] else {
            throw FixtureError.missingScenario(key)
        }

        let now = Date()
        var rows: [StatisticsOverviewRange: StatisticsRow?] = [:]
        var series: [StatisticsOverviewRange: [StatisticsRow]] = [:]
        if let ranges = selected["ranges"] as? [String: Any] {
            for range in StatisticsOverviewRange.allCases {
                guard let entry = ranges[rangeKey(range)] as? [String: Any] else { continue }
                if let aggregate = entry["aggregate"] as? [String: Any] {
                    rows[range] = try makeRow(aggregate, now: now, unit: .minute)
                }
                if let items = entry["series"] as? [[String: Any]] {
                    series[range] = try items.map { try makeRow($0, now: now, unit: .minute) }
                        .sorted { $0.t < $1.t }
                }
            }
        }
        let latest = (selected["latest"] as? [String: Any]).map { try? makeRow($0, now: now, unit: .minute) } ?? nil
        return StatisticsOverviewFixture(loadedAt: now, rows: rows, series: series, latest: latest)
    }

    private enum Unit {
        case minute
        case hour
    }

    /// 行书写方式:{"minutesAgo": 3, "valid_mem_s": 60, ...} 或 {"hoursAgo": 5, ...}。
    private static func makeRow(_ dictionary: [String: Any], now: Date, unit: Unit) throws -> StatisticsRow {
        let secondsAgo = (dictionary["hoursAgo"] as? Double).map { $0 * 3600 }
            ?? (dictionary["minutesAgo"] as? Double).map { $0 * 60 }
            ?? 0
        let bucketSeconds: TimeInterval = dictionary["hoursAgo"] != nil ? 3600 : 60
        let bucketStart = (now.timeIntervalSince1970 - secondsAgo) / bucketSeconds
        let t = Int64(bucketStart.rounded(.down) * bucketSeconds)

        var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        for (key, value) in dictionary {
            guard let index = StatisticsRow.columns.firstIndex(where: { $0.name == key }) else { continue }
            values[index] = (value as? NSNumber)?.doubleValue
        }
        let frames = (dictionary["n"] as? NSNumber)?.intValue ?? Int(bucketSeconds)
        return StatisticsRow(t: t, n: frames, values: values)
    }

    private static func rangeKey(_ range: StatisticsOverviewRange) -> String {
        switch range {
        case .today: return "today"
        case .week: return "week"
        case .month: return "month"
        }
    }

    enum FixtureError: LocalizedError {
        case missingScenarios
        case missingScenario(String)

        var errorDescription: String? {
            switch self {
            case .missingScenarios: return "fixture has no scenarios"
            case .missingScenario(let key): return "fixture scenario missing: \(key)"
            }
        }
    }
}

/// 统计摘要的数据源:正式运行时跟随 StatisticsRecorder 的发布;夹具验证时读夹具。
/// 只读,不写采样或统计链路。
@MainActor
final class StatisticsOverviewDataSource: ObservableObject {
    @Published private(set) var rows: [StatisticsOverviewRange: StatisticsRow?] = [:]

    private let recorder: StatisticsRecorder?
    private let fixture: StatisticsOverviewFixture?
    private var cancellables: Set<AnyCancellable> = []

    init(recorder: StatisticsRecorder?, fixture: StatisticsOverviewFixture?) {
        self.recorder = recorder
        self.fixture = fixture
        if let fixture {
            rows = fixture.rows
        }
    }

    /// 正式运行时的构造入口:带夹具环境变量时优先走夹具。
    static func make(recorder: StatisticsRecorder) -> StatisticsOverviewDataSource {
        if let fixture = StatisticsOverviewFixture.loadFromEnvironment() {
            return StatisticsOverviewDataSource(recorder: nil, fixture: fixture)
        }
        return StatisticsOverviewDataSource(recorder: recorder, fixture: nil)
    }

    /// 时间基准:夹具用载入时刻(状态稳定,便于目测),正式运行取实时当前时间。
    var referenceNow: Date { fixture?.loadedAt ?? Date() }

    /// 订阅记录器的发布(概览行每分钟封口后刷新);夹具模式无需订阅。
    /// 「当前状态」尚未接入展示,这里不预取最近观测,免得每分钟空跑一次查询。
    func start() {
        guard let recorder else { return }
        rows = recorder.rangeRows
        recorder.$rangeRows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                self?.rows = rows
            }
            .store(in: &cancellables)
    }

    func range(_ range: StatisticsOverviewRange) -> StatisticsRow? {
        rows[range] ?? nil
    }

    func series(_ range: StatisticsOverviewRange, completion: @escaping ([StatisticsRow]) -> Void) {
        if let fixture {
            completion(fixture.series[range] ?? [])
            return
        }
        recorder?.rangeSeries(range, completion: completion)
    }
}
