import Foundation
import SwiftData
import os.log

/// 统计模块的版本化 Schema 定义。
enum StatisticsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        HourlySample.self,
        DailyAggregate.self,
    ]
}

enum StatisticsSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        HourlySample.self,
        DailyAggregate.self,
        SystemEvent.self,
    ]
}

/// 统计模块的 Schema 迁移计划。
enum StatisticsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        StatisticsSchemaV1.self,
        StatisticsSchemaV2.self,
    ]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: StatisticsSchemaV1.self, toVersion: StatisticsSchemaV2.self),
    ]
}

/// 统计模块的共享 SwiftData 容器。
///
/// Recorder（写）与 Aggregator（读）必须使用同一个 `ModelContainer`，
/// 否则跨容器的写入对读取不可见，且并发访问同一 SQLite 文件会锁冲突。
@MainActor
enum StatisticsStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "hagimi",
        category: "StatisticsStore"
    )

    /// 全局唯一容器。创建失败时降级为内存容器，保证 App 不因统计功能崩溃。
    static let container: ModelContainer = {
        do {
            // 必须用 versionedSchema，不能用 Schema(models:) 创建匿名 schema，
            // 否则 staged migration 找不到版本匹配 → "unknown model version" 错误。
            let c = try ModelContainer(
                for: Schema(versionedSchema: StatisticsSchemaV2.self),
                migrationPlan: StatisticsMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
            )
            logger.info("StatisticsStore: persistent container created at \(c.configurations.first?.url.path ?? "unknown", privacy: .public)")
            return c
        } catch {
            logger.error("StatisticsStore: FAILED to create persistent container: \(String(describing: error), privacy: .public)")
            // 降级：内存容器。统计数据不持久化，但不影响 App 运行。
            let fallback = try! ModelContainer(
                for: Schema(versionedSchema: StatisticsSchemaV2.self),
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            logger.warning("StatisticsStore: fell back to IN-MEMORY container (data will NOT persist)")
            return fallback
        }
    }()
}
