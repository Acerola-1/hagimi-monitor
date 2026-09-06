import Foundation
import Testing
@testable import HagimiMonitorDirect

struct PanelGeometryTests {
    @Test func nestedInsetsAndReplacementEndpointsComposeAtEveryWidth() {
        for width: CGFloat in [300, 340, 460] {
            for expandedHeight: CGFloat in [50, 180] {
                let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
                    width: width, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "display"))
                registry.configureStructure(topLevelIDs: ["display"], hierarchy: ["display": ["archive"], "archive": ["leaf"]],
                    childGroups: ["display": PanelChildGroup(ids: ["archive"], leading: 38, trailing: 10, top: 9, bottom: 9),
                                  "archive": PanelChildGroup(ids: ["leaf"], leading: 22)])
                registry.reportMeasurement(id: "display", headerHeight: 34, detailHeight: 0, revision: 1)
                registry.reportMeasurement(id: "archive", parentID: "display", headerHeight: 18,
                    detailHeight: expandedHeight, revision: 1, collapsedDetailHeight: 100)
                registry.reportMeasurement(id: "leaf", parentID: "archive", headerHeight: 0, detailHeight: 0, revision: 1)
                let snapshot = registry.makeSnapshot()!
                for phase: CGFloat in [0, 0.5, 1] {
                    let frame = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 1, "archive": phase])
                    #expect(frame.childFrames["archive"]!.width == width - 60)
                    #expect(frame.childFrames["archive"]!.minX == 38)
                    #expect(frame.childFrames["leaf"]!.width == width - 82)
                    let detail = 100 + (expandedHeight + 6 - 100) * phase
                    #expect(frame.revealHeights["archive"] == detail)
                    #expect(frame.revealHeights["display"] == 9 + 18 + detail + 9)
                    #expect(frame.sectionFrames["archive"]!.minY == 43)
                }
                let closed = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 0, "archive": 1])
                #expect(closed.cardFrames["display"]!.height == 34)
                #expect(closed.sectionFrames["archive"] == nil)
            }
        }
    }

    @Test func shrinkingReplacementRebasesPhysicalHeightAndVelocity() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "archive"))
        registry.configureStructure(topLevelIDs: ["archive"])
        registry.reportMeasurement(id: "archive", headerHeight: 18, detailHeight: 50, revision: 1, collapsedDetailHeight: 100)
        let old = registry.makeSnapshot()!
        registry.reportMeasurement(id: "archive", headerHeight: 18, detailHeight: 30, revision: 1, collapsedDetailHeight: 110)
        let new = registry.makeSnapshot()!
        let rebased = PanelDimensionRegistry.rebaseline(currentPhases: ["archive": 0.4], currentVelocities: ["archive": 2], oldSnapshot: old, newSnapshot: new)
        #expect(abs(rebased.phases["archive"]! - 0.375) < 0.000001)
        #expect(abs(rebased.velocities["archive"]! - 1.25) < 0.000001)
        #expect(PanelGeometrySolver.solve(snapshot: new, phases: rebased.phases).revealHeights["archive"] == 80)
    }

    @Test func emptyModuleSelectionStillProducesHeaderAndFooterGeometry() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: ""))
        #expect(!registry.isReady)
        registry.configureStructure(topLevelIDs: [])
        registry.panelHeaderHeight = 22
        registry.footerHeight = 32.5
        #expect(registry.isReady)
        let frame = PanelGeometrySolver.solve(snapshot: registry.makeSnapshot()!, phases: [:])
        #expect(frame.bodyDocumentHeight == 32.5)
        #expect(frame.windowContentSize == CGSize(width: 340, height: 72.5))
        #expect(frame.cardFrames["__footer__"]?.minY == 0)
    }


    @Test func nestedRebasePreservesParentAndChildVisibleVelocities() {
        let environment = GeometryEnvironmentToken(width: 340, localeIdentifier: "en", dynamicTypeSize: "default",
            backingScale: 2, structureSignature: "display,archive")
        let old = GeometrySnapshot(revision: 1, environment: environment, panelWidth: 340, panelHeaderHeight: 22,
            footerHeight: 32.5, contentHeightCap: 1000, orderedTopLevelIDs: ["display"], sections: [
                "display": SectionNaturalSize(id: "display", headerHeight: 34, detailHeight: 40),
                "archive": SectionNaturalSize(id: "archive", parentID: "display", headerHeight: 30, detailHeight: 120)
            ], childrenByParent: ["display": ["archive"]])
        var updated = old
        updated.sections["display"]?.detailHeight = 75
        updated.sections["archive"]?.detailHeight = 25
        let phases: [String: CGFloat] = ["display": 0.6, "archive": 0.7]
        let velocities: [String: CGFloat] = ["display": 1.2, "archive": -0.4]
        let rebased = PanelDimensionRegistry.rebaseline(currentPhases: phases, currentVelocities: velocities,
            oldSnapshot: old, newSnapshot: updated)
        let before = PanelGeometrySolver.solve(snapshot: old, phases: phases)
        let after = PanelGeometrySolver.solve(snapshot: updated, phases: rebased.phases)
        for id in phases.keys {
            #expect(abs(before.revealHeights[id]! - after.revealHeights[id]!) < 0.0001)
        }
        let dt: CGFloat = 0.00001
        let advancedOld = phases.mapValues { $0 }
        let oldNext = PanelGeometrySolver.solve(snapshot: old,
            phases: Dictionary(uniqueKeysWithValues: advancedOld.map { ($0.key, $0.value + velocities[$0.key]! * dt) }))
        let newNext = PanelGeometrySolver.solve(snapshot: updated,
            phases: Dictionary(uniqueKeysWithValues: rebased.phases.map { ($0.key, $0.value + rebased.velocities[$0.key]! * dt) }))
        for id in phases.keys {
            let oldSpeed = (oldNext.revealHeights[id]! - before.revealHeights[id]!) / dt
            let newSpeed = (newNext.revealHeights[id]! - after.revealHeights[id]!) / dt
            #expect(abs(oldSpeed - newSpeed) < 0.01)
        }
    }


    @Test func registryTracksStableIDsAndDiscardsStaleRevisions() {
        let env1 = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu,gpu,memory"
        )
        let registry = PanelDimensionRegistry(initialEnvironment: env1)
        registry.configureStructure(topLevelIDs: ["cpu", "gpu", "memory"])

        #expect(registry.currentRevision == 1)
        #expect(!registry.isReady)

        // 登记部分卡片测量
        let r1 = registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 120, revision: 1)
        #expect(r1)
        #expect(!registry.isReady)

        // 环境变化（如语言变简中）触发 revision 失效
        let env2 = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "zh_CN",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu,gpu,memory"
        )
        let invalidated = registry.updateEnvironment(env2)
        #expect(invalidated)
        #expect(registry.currentRevision == 2)
        #expect(!registry.isReady)

        // 迟到的旧 revision 1 结果上报，应被直接丢弃
        let staleReport = registry.reportMeasurement(id: "gpu", headerHeight: 34, detailHeight: 100, revision: 1)
        #expect(!staleReport)

        // 补齐新 revision 2 的测量
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 120, revision: 2)
        registry.reportMeasurement(id: "gpu", headerHeight: 34, detailHeight: 100, revision: 2)
        registry.reportMeasurement(id: "memory", headerHeight: 34, detailHeight: 80, revision: 2)

        #expect(registry.isReady)
        let snapshot = registry.makeSnapshot()
        #expect(snapshot != nil)
        #expect(snapshot?.revision == 2)
        #expect(snapshot?.sections.count == 3)

        registry.configureStructure(topLevelIDs: ["memory", "cpu"])
        #expect(!registry.reportMeasurement(id: "gpu", headerHeight: 34, detailHeight: 999, revision: 2))
        #expect(registry.makeSnapshot()?.orderedTopLevelIDs == ["memory", "cpu"])
        #expect(registry.makeSnapshot()?.sections["gpu"] == nil)
    }

    @Test func sameEnvironmentDoesNotInvalidate() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu,gpu"
        )
        let registry = PanelDimensionRegistry(initialEnvironment: env)
        registry.configureStructure(topLevelIDs: ["cpu", "gpu"])

        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 120, revision: 1)
        registry.reportMeasurement(id: "gpu", headerHeight: 34, detailHeight: 100, revision: 1)
        #expect(registry.isReady)

        // 普通采样刷新或重设同一环境：不失效，不变 revision
        let changed = registry.updateEnvironment(env)
        #expect(!changed)
        #expect(registry.currentRevision == 1)
        #expect(registry.isReady)
    }


    @Test func solverComputesConsistentSpacingAndMargins() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu,gpu"
        )
        let snapshot = GeometrySnapshot(
            revision: 1,
            environment: env,
            panelWidth: 340,
            panelHeaderHeight: 34,
            footerHeight: 34,
            contentHeightCap: 1000,
            orderedTopLevelIDs: ["cpu", "gpu"],
            sections: [
                "cpu": SectionNaturalSize(id: "cpu", parentID: nil, headerHeight: 34, detailHeight: 100, isAvailable: true),
                "gpu": SectionNaturalSize(id: "gpu", parentID: nil, headerHeight: 34, detailHeight: 80, isAvailable: true)
            ],
            childrenByParent: [:]
        )

        // 全收起态
        let collapsedFrame = PanelGeometrySolver.solve(
            snapshot: snapshot,
            phases: ["cpu": 0, "gpu": 0]
        )

        #expect(collapsedFrame.cardFrames["cpu"]?.origin.y == 0.0)
        #expect(collapsedFrame.cardFrames["cpu"]?.height == 34.0)
        // 卡片间距 6pt
        #expect(collapsedFrame.cardFrames["gpu"]?.origin.y == CGFloat(34 + 6))
        #expect(collapsedFrame.cardFrames["gpu"]?.height == 34.0)

        // 底部按钮间距 6pt，位置为 34 + 6 + 34 + 6 = 80
        #expect(collapsedFrame.cardFrames["__footer__"]?.origin.y == CGFloat(80))
        #expect(collapsedFrame.cardFrames["__footer__"]?.height == 34.0)
        #expect(collapsedFrame.bodyDocumentHeight == CGFloat(80 + 34)) // 114

        // 窗口总高度: topMargin(8) + header(34) + headerToBody(4) + body(114) + bottomMargin(6) = 166
        #expect(collapsedFrame.windowContentSize.height == CGFloat(166))
        #expect(collapsedFrame.windowContentSize.width == 340.0)
        #expect(!collapsedFrame.isCapped)

        // cpu 展开态 (phase = 1.0)
        let expandedFrame = PanelGeometrySolver.solve(
            snapshot: snapshot,
            phases: ["cpu": 1.0, "gpu": 0]
        )
        #expect(expandedFrame.cardFrames["cpu"]?.height == 134.0)
        #expect(expandedFrame.cardFrames["gpu"]?.origin.y == CGFloat(134 + 6))
        #expect(expandedFrame.bodyDocumentHeight == CGFloat(114 + 100))
        #expect(expandedFrame.windowContentSize.height == CGFloat(166 + 100))
    }

    @Test func solverEnforcesViewportCapAndMaintainsBottomMargin() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu"
        )
        // 封顶可用空间设为 150
        let snapshot = GeometrySnapshot(
            revision: 1,
            environment: env,
            panelWidth: 340,
            panelHeaderHeight: 34,
            footerHeight: 34,
            contentHeightCap: 150,
            orderedTopLevelIDs: ["cpu"],
            sections: [
                "cpu": SectionNaturalSize(id: "cpu", parentID: nil, headerHeight: 34, detailHeight: 300, isAvailable: true)
            ],
            childrenByParent: [:]
        )

        let frame = PanelGeometrySolver.solve(
            snapshot: snapshot,
            phases: ["cpu": 1.0]
        )

        #expect(frame.isCapped)
        // availableViewportCap = 150 - (8 + 34 + 4 + 6) = 98
        #expect(frame.viewportHeight == 98)
        #expect(frame.windowContentSize.height == 150)
    }


    @Test func nestedSectionsCalculateHierarchicalHeightsWithoutDoubleCounting() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "display"
        )
        let snapshot = GeometrySnapshot(
            revision: 1,
            environment: env,
            panelWidth: 340,
            panelHeaderHeight: 34,
            footerHeight: 0,
            contentHeightCap: 1000,
            orderedTopLevelIDs: ["display"],
            sections: [
                "display": SectionNaturalSize(id: "display", parentID: nil, headerHeight: 34, detailHeight: 40, isAvailable: true),
                "disp1": SectionNaturalSize(id: "disp1", parentID: "display", headerHeight: 30, detailHeight: 50, isAvailable: true),
                "disp2": SectionNaturalSize(id: "disp2", parentID: "display", headerHeight: 30, detailHeight: 50, isAvailable: true)
            ],
            childrenByParent: ["display": ["disp1", "disp2"]]
        )

        // 1. 外层关闭，即使内层 phase 为 1，外层 revealHeight 也应为 0
        let frameOuterClosed = PanelGeometrySolver.solve(
            snapshot: snapshot,
            phases: ["display": 0, "disp1": 1.0, "disp2": 1.0]
        )
        #expect(frameOuterClosed.revealHeights["display"] == 0)
        #expect(frameOuterClosed.cardFrames["display"]?.height == 34)

        // 2. 外层展开 (phase = 1.0)，内层均收起 (phase = 0)
        // 合成明细高 = display 自有(40) + 间距(6) + disp1 header(30) + 间距(6) + disp2 header(30) = 112
        let frameOuterOpen = PanelGeometrySolver.solve(
            snapshot: snapshot,
            phases: ["display": 1.0, "disp1": 0, "disp2": 0]
        )
        #expect(frameOuterOpen.revealHeights["display"] == CGFloat(112))
        #expect(frameOuterOpen.childFrames["disp1"]?.origin.y == CGFloat(40 + 6))
        #expect(frameOuterOpen.childFrames["disp2"]?.origin.y == CGFloat(40 + 6 + 30 + 6))

        // 3. 设备移除 (disp2 isAvailable = false)
        var updatedSections = snapshot.sections
        updatedSections["disp2"]?.isAvailable = false
        var snapshotWithRemovedDevice = snapshot
        snapshotWithRemovedDevice.sections = updatedSections

        let frameRemovedDevice = PanelGeometrySolver.solve(
            snapshot: snapshotWithRemovedDevice,
            phases: ["display": 1.0, "disp1": 0, "disp2": 0]
        )
        // disp2 被移除，不再参与计算：40 + 6 + 30 = 76
        #expect(frameRemovedDevice.revealHeights["display"] == 76)
        #expect(frameRemovedDevice.childFrames["disp2"] == nil)
    }


    @Test func registryProvidesSafeRestingSnapshotWhenUnready() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu,gpu"
        )
        let registry = PanelDimensionRegistry(initialEnvironment: env)
        registry.configureStructure(topLevelIDs: ["cpu", "gpu"])

        #expect(!registry.isReady)
        #expect(registry.makeSnapshot() == nil)

        // 获取安全收起态快照，防止零尺寸启动
        let safe = registry.makeRestingFallbackSnapshot(safeHeaderHeight: 34)
        #expect(safe.sections["cpu"]?.headerHeight == 34)
        #expect(safe.sections["cpu"]?.detailHeight == 0)

        let safeFrame = PanelGeometrySolver.solve(snapshot: safe, phases: [:])
        #expect(safeFrame.windowContentSize.height > 100)
    }

    @Test func rebaselineConservesVisibleMomentumAcrossDimensionChanges() {
        let env1 = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu"
        )
        let snapshotOld = GeometrySnapshot(
            revision: 1,
            environment: env1,
            panelWidth: 340,
            panelHeaderHeight: 34,
            footerHeight: 0,
            contentHeightCap: 1000,
            orderedTopLevelIDs: ["cpu"],
            sections: [
                "cpu": SectionNaturalSize(id: "cpu", parentID: nil, headerHeight: 34, detailHeight: 100, isAvailable: true)
            ],
            childrenByParent: [:]
        )

        // 假设施加运动到一半：phase = 0.5 (即 50pt reveal)，velocityPhase = 2.0 (即 200pt/s)
        let currentPhases = ["cpu": CGFloat(0.5)]
        let currentVelocities = ["cpu": CGFloat(2.0)]

        // 新版本自然高度因语言切换从 100 变到 200
        var snapshotNew = snapshotOld
        snapshotNew.revision = 2
        snapshotNew.sections["cpu"] = SectionNaturalSize(id: "cpu", parentID: nil, headerHeight: 34, detailHeight: 200, isAvailable: true)

        let rebased = PanelDimensionRegistry.rebaseline(
            currentPhases: currentPhases,
            currentVelocities: currentVelocities,
            oldSnapshot: snapshotOld,
            newSnapshot: snapshotNew
        )

        // 物理位置仍为 50pt，在 200pt 中对应 phase 0.25
        #expect(abs(rebased.phases["cpu"]! - 0.25) < 0.001)
        // 物理速度仍为 200pt/s，在 200pt 中对应 velocityPhase 1.0
        #expect(abs(rebased.velocities["cpu"]! - 1.0) < 0.001)
    }
}

extension PanelGeometryTests {
    private func nestedSnapshot() -> GeometrySnapshot {
        GeometrySnapshot(revision: 1,
            environment: GeometryEnvironmentToken(width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "nested"),
            panelWidth: 340, panelHeaderHeight: 22, footerHeight: 0, contentHeightCap: 1000,
            orderedTopLevelIDs: ["display"], sections: [
                "display": SectionNaturalSize(id: "display", headerHeight: 34, detailHeight: 40),
                "screen": SectionNaturalSize(id: "screen", parentID: "display", headerHeight: 30, detailHeight: 20),
                "archive": SectionNaturalSize(id: "archive", parentID: "screen", headerHeight: 10, detailHeight: 100)
            ], childrenByParent: ["display": ["screen"], "screen": ["archive"]])
    }

    @Test func thirdLevelContributesExactlyOnceAndClosedParentHidesIt() {
        let snapshot = nestedSnapshot()
        let closed = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 1, "screen": 1, "archive": 0])
        let open = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 1, "screen": 1, "archive": 1])
        #expect(open.windowContentSize.height - closed.windowContentSize.height == 100)
        let parentClosed = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 0, "screen": 1, "archive": 1])
        #expect(parentClosed.cardFrames["display"]?.height == 34)
    }

    @Test func unavailableTopLevelCannotRevealAndZeroCapRemainsCapped() {
        var snapshot = nestedSnapshot()
        snapshot.sections["display"]?.isAvailable = false
        let hidden = PanelGeometrySolver.solve(snapshot: snapshot, phases: ["display": 1, "screen": 1, "archive": 1])
        #expect(hidden.revealHeights["display"] == 0)
        snapshot.contentHeightCap = 8 + 22 + 4 + 6
        let capped = PanelGeometrySolver.solve(snapshot: snapshot, phases: [:], scrollOffset: 1000)
        #expect(capped.viewportHeight == 0)
        #expect(capped.isCapped)
        #expect(capped.scrollOffset <= capped.bodyDocumentHeight)
    }

    @Test func shrinkingNaturalHeightPreservesVisiblePointsAndVelocity() {
        let old = nestedSnapshot()
        var new = old
        new.sections["archive"]?.detailHeight = 20
        let result = PanelDimensionRegistry.rebaseline(currentPhases: ["archive": 0.75],
            currentVelocities: ["archive": 2], oldSnapshot: old, newSnapshot: new)
        #expect(result.phases["archive"] == 3.75)
        #expect(result.velocities["archive"] == 10)
    }

    @Test func hiddenChildRebasePreservesLatentMotionWithoutMovingAncestors() {
        let old = nestedSnapshot()
        var new = old
        new.sections["archive"]?.detailHeight = 200
        for phase in [CGFloat(-0.02), 0.001] {
            let phases: [String: CGFloat] = ["display": 0.7, "screen": 0.4, "archive": phase]
            let velocities: [String: CGFloat] = ["display": 0.2, "screen": 0.1, "archive": -0.3]
            let result = PanelDimensionRegistry.rebaseline(currentPhases: phases,
                currentVelocities: velocities, oldSnapshot: old, newSnapshot: new,
                closedSections: ["archive"])
            #expect(abs(result.phases["archive"]! * 200 - phase * 100) < 0.000001)
            #expect(abs(result.velocities["archive"]! * 200 + 30) < 0.000001)
            for id in ["display", "screen"] {
                #expect(abs(result.phases[id]! - phases[id]!) < 0.000001)
                #expect(abs(result.velocities[id]! - velocities[id]!) < 0.000001)
            }
        }
    }
}
