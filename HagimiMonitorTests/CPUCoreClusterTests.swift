import Testing
@testable import HagimiMonitorDirect

/// IORegistry 簇字母 → 核心类别的归类规则测试。
/// 规则背景:M1–M4 为 P/E 两簇;M5 Pro/Max 实测为 P/M/E 三簇
/// (hwloc #839),P 与 M 并存时 P 为超核、M 为性能核;未知字母
/// 归入高占用组,防止新代际把核误划进能效组。
struct CPUCoreClusterTests {
    private func clusters(_ mapping: [Int: Character]) -> CPUCoreClusters {
        CPUCoreClusters(logicalClusters: mapping)
    }

    @Test func emptyRegistryProducesNoGroups() {
        let result = clusters([:])
        #expect(result.superCore.isEmpty)
        #expect(result.performance.isEmpty)
        #expect(result.efficiency.isEmpty)
    }

    @Test func m4TwoClusterTopology() {
        // 实测 M4:E 核占逻辑 0-5,P 核占 6-9。
        var mapping: [Int: Character] = [:]
        for index in 0..<6 { mapping[index] = "E" }
        for index in 6..<10 { mapping[index] = "P" }

        let result = clusters(mapping)
        #expect(result.efficiency == Set(0..<6))
        #expect(result.performance == Set(6..<10))
        #expect(result.superCore.isEmpty)
    }

    @Test func m5ProThreeClusterTopology() {
        // hwloc #839 实测 M5 Pro:P/M/E 三簇,P 为超核、M 为性能核。
        let result = clusters([0: "P", 1: "P", 2: "M", 3: "M", 4: "M", 5: "M", 6: "E", 7: "E", 8: "E", 9: "E", 10: "E", 11: "E"])
        #expect(result.superCore == [0, 1])
        #expect(result.performance == Set(2..<6))
        #expect(result.efficiency == Set(6..<12))
    }

    @Test func standaloneMWithNoCompanionCountsAsPerformance() {
        // M 簇单独出现(无 P/S)时按高占用组处理,不落进能效组。
        let result = clusters([0: "M", 1: "M", 2: "E"])
        #expect(result.performance == [0, 1])
        #expect(result.efficiency == [2])
        #expect(result.superCore.isEmpty)
    }

    @Test func reservedSLetterCountsAsSuperCore() {
        // 预留字母 S:独立超核簇,与 P 并存时 P 仍为性能核。
        let result = clusters([0: "S", 1: "S", 2: "P", 3: "P", 4: "E"])
        #expect(result.superCore == [0, 1])
        #expect(result.performance == [2, 3])
        #expect(result.efficiency == [4])
    }

    @Test func unknownLetterJoinsHighUsageGroup() {
        // 未知字母(新代际)不得误划进能效组。
        let result = clusters([0: "X", 1: "E"])
        #expect(result.performance == [0])
        #expect(result.efficiency == [1])
        #expect(result.superCore.isEmpty)
    }

    @Test func coreKindLookupPerGroup() {
        let result = clusters([0: "P", 1: "P", 2: "M", 3: "E"])
        #expect(cpuCoreKind(at: 0, clusters: result) == .superCore)
        #expect(cpuCoreKind(at: 2, clusters: result) == .performance)
        #expect(cpuCoreKind(at: 3, clusters: result) == .efficiency)
    }

    @Test func coreKindLookupOnEmptyClustersDefaultsToEfficiency() {
        // 空归类(拓扑读不到)时不产出 core-split,单核类别仅作兜底。
        let result = clusters([:])
        #expect(cpuCoreKind(at: 0, clusters: result) == .efficiency)
    }
}
