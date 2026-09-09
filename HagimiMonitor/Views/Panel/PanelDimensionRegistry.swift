import CoreGraphics
import Foundation

/// 自然尺寸登记簿：按版本管理分区的测量数据，处理环境失效、迟到测量丢弃与运动重基准。
final class PanelDimensionRegistry {
    private(set) var currentRevision: UInt = 1
    private(set) var environment: GeometryEnvironmentToken

    var panelWidth: CGFloat { environment.width }
    var panelHeaderHeight: CGFloat = 34
    var footerHeight: CGFloat = 34
    var contentHeightCap: CGFloat = .infinity

    private(set) var orderedTopLevelIDs: [String] = []
    private(set) var childrenByParent: [String: [String]] = [:]

    /// 各分区的尺寸与层级记录。
    private var registeredSections: [String: SectionNaturalSize] = [:]
    /// 当前版本已测量完成的分区集合。
    private var measuredIDsForCurrentRevision: Set<String> = []
    private var childGroups: [String: PanelChildGroup] = [:]
    private var hasConfiguredStructure = false

    /// 所有在结构中声明的分区 ID（顶级卡片 + 子分区）。
    var allConfiguredIDs: Set<String> {
        var ids = Set(orderedTopLevelIDs)
        for children in childrenByParent.values {
            ids.formUnion(children)
        }
        return ids
    }

    /// 当前版本是否所有必需分区都已完成测量。
    var isReady: Bool {
        let configured = allConfiguredIDs
        guard hasConfiguredStructure else { return false }
        return configured.isSubset(of: measuredIDsForCurrentRevision)
            && configured.isSubset(of: Set(registeredSections.keys))
    }

    init(initialEnvironment: GeometryEnvironmentToken) {
        self.environment = initialEnvironment
    }

    /// 登记分区的结构与拓扑（卡片顺序与父子层级）。
    func configureStructure(
        topLevelIDs: [String],
        hierarchy: [String: [String]] = [:],
        childGroups: [String: PanelChildGroup] = [:]
    ) {
        hasConfiguredStructure = true
        orderedTopLevelIDs = topLevelIDs
        childrenByParent = hierarchy
        self.childGroups = childGroups

        // 清理不再存在的旧分区
        var validIDs = Set(topLevelIDs)
        for children in hierarchy.values {
            validIDs.formUnion(children)
        }
        registeredSections = registeredSections.filter { validIDs.contains($0.key) }
        measuredIDsForCurrentRevision.formIntersection(validIDs)
    }

    /// 检查环境是否变更（宽度、语言、字号、缩放、结构）。如变更则递增 revision 并使测量失效。
    func updateEnvironment(_ newEnvironment: GeometryEnvironmentToken) -> Bool {
        guard newEnvironment != environment else { return false }
        environment = newEnvironment
        currentRevision &+= 1
        measuredIDsForCurrentRevision.removeAll()
        return true
    }

    /// 上报某个分区的自然测量高度。若 revision 早于当前版本，直接丢弃。
    @discardableResult
    func reportMeasurement(
        id: String,
        parentID: String? = nil,
        headerHeight: CGFloat,
        detailHeight: CGFloat,
        isAvailable: Bool = true,
        revision: UInt,
        collapsedDetailHeight: CGFloat = 0
    ) -> Bool {
        // 迟到旧版本测量直接丢弃，防止污染当前几何
        guard revision == currentRevision, allConfiguredIDs.contains(id) else { return false }

        registeredSections[id] = SectionNaturalSize(
            id: id,
            parentID: parentID,
            headerHeight: max(0, headerHeight),
            detailHeight: max(0, detailHeight),
            isAvailable: isAvailable,
            collapsedDetailHeight: max(0, collapsedDetailHeight)
        )
        measuredIDsForCurrentRevision.insert(id)
        return true
    }

    /// 标记某个分区的可用性变更（如设备拔出/可用内容消失）。
    func setSectionAvailability(id: String, isAvailable: Bool) {
        guard var section = registeredSections[id], section.isAvailable != isAvailable else { return }
        section.isAvailable = isAvailable
        registeredSections[id] = section
    }

    /// 生成当前已就绪的不可变几何快照。如尚未全部就绪，返回 nil。
    func makeSnapshot() -> GeometrySnapshot? {
        guard isReady else { return nil }
        return GeometrySnapshot(
            revision: currentRevision,
            environment: environment,
            panelWidth: environment.width,
            panelHeaderHeight: panelHeaderHeight,
            footerHeight: footerHeight,
            contentHeightCap: contentHeightCap,
            orderedTopLevelIDs: orderedTopLevelIDs,
            sections: registeredSections,
            childrenByParent: childrenByParent, childGroups: childGroups
        )
    }

    /// 生成安全收起态快照（用于初始化尚未全部测齐时，防止零高度启动）。
    func makeRestingFallbackSnapshot(
        safeHeaderHeight: CGFloat = MonitorConstants.panelRowHeaderHeight
    ) -> GeometrySnapshot {
        var safeSections: [String: SectionNaturalSize] = [:]
        for id in orderedTopLevelIDs {
            safeSections[id] = SectionNaturalSize(
                id: id,
                parentID: nil,
                headerHeight: safeHeaderHeight,
                detailHeight: 0,
                isAvailable: true
            )
        }
        return GeometrySnapshot(
            revision: currentRevision,
            environment: environment,
            panelWidth: environment.width,
            panelHeaderHeight: panelHeaderHeight,
            footerHeight: footerHeight,
            contentHeightCap: contentHeightCap,
            orderedTopLevelIDs: orderedTopLevelIDs,
            sections: safeSections,
            childrenByParent: [:]
        )
    }

    /// 换版时保留点数与速度，包括硬边界外尚在衰减的解析状态；父级只计入可见子高度。
    static func rebaseline(
        currentPhases: [String: CGFloat],
        currentVelocities: [String: CGFloat],
        oldSnapshot: GeometrySnapshot,
        newSnapshot: GeometrySnapshot,
        closedSections: Set<String> = []
    ) -> (phases: [String: CGFloat], velocities: [String: CGFloat]) {
        var newPhases: [String: CGFloat] = [:]
        var newVelocities: [String: CGFloat] = [:]

        typealias Sample = (height: CGFloat, velocity: CGFloat)
        var oldSamples: [String: Sample] = [:]
        var newSamples: [String: Sample] = [:]
        var oldVisiting: Set<String> = []
        var newVisiting: Set<String> = []

        func natural(_ id: String, in snapshot: GeometrySnapshot,
                     childSample: (String) -> Sample) -> Sample {
            guard let section = snapshot.sections[id], section.isAvailable else { return (0, 0) }
            let group = snapshot.childGroup(id)
            var result: Sample = (section.detailHeight + group.top + group.bottom, 0)
            var childCount = 0
            for childID in snapshot.childrenByParent[id] ?? [] {
                guard let child = snapshot.sections[childID], child.isAvailable else { continue }
                if childCount > 0 || section.detailHeight > 0 { result.height += group.spacing }
                let sample = childSample(childID)
                result.height += child.headerHeight
                if closedSections.contains(childID) {
                    result.height += child.collapsedDetailHeight
                } else {
                    result.height += max(0, sample.height)
                    if sample.height > 0 || (sample.height == 0 && sample.velocity > 0) {
                        result.velocity += sample.velocity
                    }
                }
                childCount += 1
            }
            return result
        }

        func oldSample(_ id: String) -> Sample {
            if let cached = oldSamples[id] { return cached }
            guard oldVisiting.insert(id).inserted else { return (0, 0) }
            defer { oldVisiting.remove(id) }
            let size = natural(id, in: oldSnapshot, childSample: oldSample)
            let phase = currentPhases[id] ?? 0
            let velocity = currentVelocities[id] ?? 0
            let base = oldSnapshot.sections[id]?.collapsedDetailHeight ?? 0
            let span = size.height - base
            let result: Sample = (base + span * phase, span * velocity + size.velocity * phase)
            oldSamples[id] = result
            return result
        }

        func rebase(_ id: String) -> Sample {
            if let cached = newSamples[id] { return cached }
            guard newVisiting.insert(id).inserted else { return (0, 0) }
            defer { newVisiting.remove(id) }
            let size = natural(id, in: newSnapshot, childSample: rebase)
            let previous = oldSample(id)
            let base = newSnapshot.sections[id]?.collapsedDetailHeight ?? 0
            let span = size.height - base
            if abs(span) > 0.0001 {
                let phase = (previous.height - base) / span
                newPhases[id] = phase
                // 父视口的速度同时包含自身相位变化和子分区的高度变化。
                newVelocities[id] = (previous.velocity - phase * size.velocity) / span
                newSamples[id] = previous
            } else {
                newPhases[id] = 0
                newVelocities[id] = 0
                newSamples[id] = (base, 0)
            }
            return newSamples[id]!
        }

        for id in newSnapshot.orderedTopLevelIDs { _ = rebase(id) }

        return (newPhases, newVelocities)
    }
}
