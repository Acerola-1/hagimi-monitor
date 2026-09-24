import AppKit
import Foundation
import CoreGraphics
import Testing
@testable import HagimiMonitorDirect

struct PanelOrderingTests {
    @Test func catalogHasStableUniqueIDs() {
        let scopes = PanelOrderCatalog.scopes
        #expect(Set(scopes.map(\.storageKey)).count == scopes.count)
        #expect(PanelOrderCatalog.ids(for: .modules).contains(PanelOrderCatalog.displayID))
        #expect(PanelOrderCatalog.ids(for: .modules).contains(MonitorKind.fan.id))
        #expect(PanelOrderCatalog.ids(for: .modules).contains(MonitorKind.bluetooth.id))
        #expect(PanelOrderCatalog.supplyIDs.count == 5)
        for scope in scopes {
            let ids = PanelOrderCatalog.ids(for: scope)
            #expect(Set(ids).count == ids.count)
            #expect(Set(PanelOrderCatalog.defaultIDs(for: scope)) == Set(ids))
        }
        #expect(!PanelOrderCatalog.ids(for: .battery(.health)).contains("power-flow"))
        #expect(!PanelOrderCatalog.ids(for: .battery(.flow)).contains("power-flow"))
        #expect(PanelOrderCatalog.stableMetricID(kind: .memory, displayedName: "usage") == "pressure")
        #expect(PanelOrderCatalog.stableMetricID(kind: .storage, displayedName: "used") == "used")
        #expect(PanelOrderCatalog.defaultIDs(for: .metrics(.cpu)).first == "core-split")
    }

    @Test func reconciliationKeepsUserOrderAndUnknownIDs() {
        let result = PanelOrderList.reconciled(
            ["b", "future", "a", "b"],
            defaults: ["a", "new", "b", "last"]
        )
        #expect(result.filter { ["a", "b"].contains($0) } == ["b", "a"])
        #expect(result.contains("future"))
        #expect(result.firstIndex(of: "new")! < result.firstIndex(of: "b")!)
        #expect(result.firstIndex(of: "last")! > result.firstIndex(of: "b")!)
        #expect(Set(result).count == result.count)
    }

    @Test func hiddenItemReturnsToStoredPosition() {
        let full = ["cpu", "network", "memory", "display"]
        #expect(PanelOrderList.visible(full, available: ["cpu", "memory", "display"]) == ["cpu", "memory", "display"])
        #expect(PanelOrderList.visible(full, available: ["network", "cpu", "memory", "display"]) == full)
    }

    @Test func topLevelProjectionIncludesDisplayWithoutChangingSourceModules() {
        let suite = "topLevelProjectionIncludesDisplayWithoutChangingSourceModules"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let source = ["cpu", "gpu", "fan", "memory"]
        let all = source + [PanelOrderCatalog.displayID]
        #expect(settings.movePanelItem(PanelOrderCatalog.displayID, in: .modules,
                                       before: "cpu", visible: all))
        #expect(settings.orderedPanelIDs(for: .modules, available: all).first == PanelOrderCatalog.displayID)
        let appStoreAvailable = all.filter { $0 != "fan" }
        #expect(!settings.orderedPanelIDs(for: .modules, available: appStoreAvailable).contains("fan"))
        #expect(source == ["cpu", "gpu", "fan", "memory"])
        #expect(settings.panelOrder(for: .modules).contains("fan"))
    }

    @Test func temporarilyUnavailableMetricsKeepTheirPlaceAcrossScopes() {
        let suite = "temporarilyUnavailableMetricsKeepTheirPlaceAcrossScopes"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        for scope in [PanelOrderScope.metrics(.network), .battery(.health), .battery(.supply)] {
            let ids = PanelOrderCatalog.defaultIDs(for: scope)
            #expect(ids.count > 1)
            #expect(settings.movePanelItem(ids[1], in: scope, before: ids[0], visible: ids))
            #expect(settings.orderedPanelIDs(for: scope, available: [ids[0]]) == [ids[0]])
            #expect(Array(settings.orderedPanelIDs(for: scope, available: ids).prefix(2)) == [ids[1], ids[0]])
        }
    }

    @Test func movingWithinVisibleItemsPreservesHiddenIDs() {
        let full = ["cpu", "hidden", "gpu", "memory"]
        let moved = PanelOrderList.moved(full, id: "memory", before: "cpu", visible: ["cpu", "gpu", "memory"])
        #expect(moved == ["memory", "cpu", "hidden", "gpu"])
        #expect(PanelOrderList.moved(full, id: "memory", before: "missing", visible: ["cpu", "gpu", "memory"]) == nil)
    }

    @Test func mixedSpansKeepTheirRegisteredWidthAndEmptyHalfSlot() {
        #expect(MetricGridPacking.rows(for: [1, 2, 1]) == [[0], [1], [2]])
        #expect(MetricGridPacking.rows(for: [2, 2, 1, 1]) == [[0], [1], [2, 3]])
        #expect(MetricGridPacking.rows(for: [1, 1, 2, 1]) == [[0, 1], [2], [3]])
        let cpu = PanelOrderCatalog.defaultIDs(for: .metrics(.cpu))
        #expect(cpu.filter { $0 == "core-split" }.count == 1)
        #expect(MetricGridPacking.rows(for: [2, 1, 1]).first == [0])
    }

    @Test func settingsOrderSurvivesRestartAndResetOnlyOneModule() {
        let suite = "settingsOrderSurvivesRestartAndResetOnlyOneModule"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let cpu = PanelOrderScope.metrics(.cpu)
        let gpu = PanelOrderScope.metrics(.gpu)
        let cpuIDs = PanelOrderCatalog.defaultIDs(for: cpu)
        let gpuIDs = PanelOrderCatalog.defaultIDs(for: gpu)
        #expect(settings.movePanelItem(cpuIDs[1], in: cpu, before: cpuIDs[0], visible: cpuIDs))
        #expect(settings.movePanelItem(gpuIDs[1], in: gpu, before: gpuIDs[0], visible: gpuIDs))
        #expect(settings.hasCustomMetricOrder(for: .cpu))
        #expect(settings.hasCustomMetricOrder(for: .gpu))

        let reopened = MonitorSettings(defaults: defaults)
        #expect(reopened.panelOrder(for: cpu).first == cpuIDs[1])
        #expect(reopened.panelOrder(for: gpu).first == gpuIDs[1])
        reopened.restoreDefaultMetricOrder(for: .cpu)
        #expect(reopened.panelOrder(for: cpu) == cpuIDs)
        #expect(!reopened.hasCustomMetricOrder(for: .cpu))
        #expect(reopened.hasCustomMetricOrder(for: .gpu))
        #expect(reopened.panelOrder(for: gpu).first == gpuIDs[1])
    }

    @MainActor
    @Test func captureUsesTheDisplayedItemBounds() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 120),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemBlue.cgColor
        let item = NSView(frame: CGRect(x: 20, y: 30, width: 180, height: 40))
        content.addSubview(item)
        window.contentView = content
        let controller = PanelReorderController()
        controller.registerCapture(scope: .modules, id: "cpu", view: item)
        let snapshot = controller.snapshot(scope: .modules, id: "cpu")
        #expect(snapshot?.size == CGSize(width: 180, height: 40))
        let pixel = (snapshot?.representations.first as? NSBitmapImageRep)?
            .colorAt(x: 90, y: 20)?.usingColorSpace(.deviceRGB)
        #expect((pixel?.alphaComponent ?? 0) > 0.9)
        #expect((pixel?.blueComponent ?? 0) > (pixel?.redComponent ?? 1))
    }

    @MainActor
    @Test func dragCommitsOnlyOnValidReleaseAndCanBeCancelled() {
        let suite = "dragCommitsOnlyOnValidReleaseAndCanBeCancelled"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let ids = [MonitorKind.cpu.id, MonitorKind.gpu.id, MonitorKind.memory.id]
        for (index, id) in ids.enumerated() {
            controller.register(scope: .modules, id: id, title: id,
                                frame: CGRect(x: 0, y: CGFloat(index * 50), width: 200, height: 40))
        }
        controller.begin(scope: .modules, id: ids[0], location: CGPoint(x: 30, y: 20), settings: settings)
        controller.update(location: CGPoint(x: 30, y: 80))
        #expect(controller.projected(ids, scope: .modules) == [ids[1], ids[0], ids[2]])
        controller.cancel()
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) == ids)

        controller.begin(scope: .modules, id: ids[0], location: CGPoint(x: 30, y: 20), settings: settings)
        controller.update(location: CGPoint(x: 30, y: 300))
        controller.finish(settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) == ids)

        controller.begin(scope: .modules, id: ids[0], location: CGPoint(x: 30, y: 20), settings: settings)
        controller.update(location: CGPoint(x: 30, y: 80))
        controller.finish(settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) == [ids[1], ids[0], ids[2]])
    }

    @MainActor
    @Test func expandedContentBetweenHeadersIsNotADropTarget() {
        let suite = "expandedContentBetweenHeadersIsNotADropTarget"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        controller.register(scope: .modules, id: "cpu", title: "cpu",
                            frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        controller.register(scope: .modules, id: "gpu", title: "gpu",
                            frame: CGRect(x: 0, y: 200, width: 200, height: 40))
        controller.begin(scope: .modules, id: "cpu", location: CGPoint(x: 20, y: 20), settings: settings)
        controller.update(location: CGPoint(x: 20, y: 100))
        #expect(controller.session?.valid == false)
        controller.finish(settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ["cpu", "gpu"]) == ["cpu", "gpu"])
    }

    @MainActor
    @Test func edgeScrollAdvancesToTheNextHiddenItem() {
        let suite = "edgeScrollAdvancesToTheNextHiddenItem"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let ids = ["cpu", "gpu", "memory", "storage"]
        for (index, id) in ids.enumerated() {
            controller.register(scope: .modules, id: id,
                                title: id, frame: CGRect(x: 0, y: index * 50, width: 200, height: 40))
        }
        controller.begin(scope: .modules, id: "cpu", location: CGPoint(x: 20, y: 20), settings: settings)
        #expect(controller.edgeScrollTarget(towardBottom: true,
                                            viewport: CGRect(x: 0, y: 0, width: 200, height: 100)) ==
                "panel-order.modules.memory")
        #expect(controller.edgeScrollTarget(towardBottom: false,
                                            viewport: CGRect(x: 0, y: 50, width: 200, height: 100)) ==
                "panel-order.modules.cpu")
    }

    @MainActor
    @Test func stationaryPointerUsesScrolledFramesForNextTargetAndDrop() {
        let suite = "stationaryPointerUsesScrolledFramesForNextTargetAndDrop"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let ids = ["cpu", "gpu", "memory", "storage", "network"]
        for (index, id) in ids.enumerated() {
            controller.register(scope: .modules, id: id, title: id,
                                frame: CGRect(x: 0, y: index * 50, width: 200, height: 40))
        }
        controller.begin(scope: .modules, id: "cpu", location: CGPoint(x: 20, y: 20), settings: settings)
        controller.update(location: CGPoint(x: 20, y: 75))
        #expect(controller.edgeScrollTarget(towardBottom: true,
                                            viewport: CGRect(x: 0, y: 0, width: 200, height: 100)) ==
                "panel-order.modules.memory")

        // 模拟滚动改变所有卡片的窗口坐标；指针保持静止。
        for (index, id) in ids.enumerated() {
            controller.register(scope: .modules, id: id, title: id,
                                frame: CGRect(x: 0, y: index * 50 - 50, width: 200, height: 40))
        }
        #expect(controller.edgeScrollTarget(towardBottom: true,
                                            viewport: CGRect(x: 0, y: 0, width: 200, height: 100)) ==
                "panel-order.modules.storage")
        controller.finish(settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) ==
                ["gpu", "memory", "cpu", "storage", "network"])
    }

    @MainActor
    @Test func expansionGateDoesNotFreezeAnIntermediateHeight() {
        let suite = "expansionGateDoesNotFreezeAnIntermediateHeight"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        controller.register(scope: .modules, id: "cpu", title: "cpu",
                            frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        controller.register(scope: .modules, id: "gpu", title: "gpu",
                            frame: CGRect(x: 0, y: 50, width: 200, height: 40))
        controller.canBegin = { false }
        controller.begin(scope: .modules, id: "cpu", location: CGPoint(x: 20, y: 20), settings: settings)
        #expect(controller.session == nil)
        controller.canBegin = { true }
        controller.begin(scope: .modules, id: "cpu", location: CGPoint(x: 20, y: 20), settings: settings)
        #expect(controller.session?.id == "cpu")
    }

    @MainActor
    @Test func sameRowHalfWidthMetricsUseHorizontalDropPosition() {
        let suite = "sameRowHalfWidthMetricsUseHorizontalDropPosition"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let scope = PanelOrderScope.metrics(.cpu)
        let ids = ["system", "user"]
        #expect(ids.count == 2)
        controller.register(scope: scope, id: ids[0], title: ids[0], span: 1,
                            frame: CGRect(x: 0, y: 0, width: 90, height: 30))
        controller.register(scope: scope, id: ids[1], title: ids[1], span: 1,
                            frame: CGRect(x: 100, y: 0, width: 90, height: 30))
        controller.begin(scope: scope, id: ids[1], location: CGPoint(x: 130, y: 15), settings: settings)
        controller.update(location: CGPoint(x: 20, y: 15))
        #expect(controller.projected(ids, scope: scope) == [ids[1], ids[0]])
        controller.finish(settings: settings)
        #expect(settings.orderedPanelIDs(for: scope, available: ids) == [ids[1], ids[0]])
    }

    @MainActor
    @Test func spatialMenuUsesFourDirectionsAndHidesEdges() {
        let suite = "spatialMenuUsesFourDirectionsAndHidesEdges"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let scope = PanelOrderScope.metrics(.cpu)
        let ids = ["core-split", "system", "user", "idle"]
        controller.register(scope: scope, id: ids[0], title: ids[0], span: 2,
                            frame: CGRect(x: 0, y: 0, width: 190, height: 60))
        controller.register(scope: scope, id: ids[1], title: ids[1], span: 1,
                            frame: CGRect(x: 0, y: 70, width: 90, height: 30))
        controller.register(scope: scope, id: ids[2], title: ids[2], span: 1,
                            frame: CGRect(x: 100, y: 70, width: 90, height: 30))
        controller.register(scope: scope, id: ids[3], title: ids[3], span: 1,
                            frame: CGRect(x: 0, y: 110, width: 90, height: 30))
        #expect(controller.availableDirections(ids[0], scope: scope,
                                               settings: settings) == [.down])
        #expect(controller.availableDirections(ids[1], scope: scope,
                                               settings: settings) == [.up, .down, .right])
        #expect(controller.availableDirections(ids[2], scope: scope,
                                               settings: settings) == [.up, .down, .left])
        #expect(controller.availableDirections(ids[3], scope: scope,
                                               settings: settings) == [.up])

        controller.move(ids[1], scope: scope, direction: .right, settings: settings)
        #expect(settings.orderedPanelIDs(for: scope, available: ids) ==
                [ids[0], ids[2], ids[1], ids[3]])
        controller.move(ids[1], scope: scope, direction: .left, settings: settings)
        #expect(settings.orderedPanelIDs(for: scope, available: ids) == ids)
        controller.move(ids[1], scope: scope, direction: .down, settings: settings)
        #expect(settings.orderedPanelIDs(for: scope, available: ids) ==
                [ids[0], ids[2], ids[3], ids[1]])
        #expect(!controller.availableDirections(ids[1], scope: scope,
                                                settings: settings).contains(.down))
    }

    @MainActor
    @Test func spatialMoveUsesTheSameScopeRules() {
        let suite = "spatialMoveUsesTheSameScopeRules"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let controller = PanelReorderController()
        let ids = [MonitorKind.cpu.id, MonitorKind.gpu.id, MonitorKind.memory.id]
        for (index, id) in ids.enumerated() {
            controller.register(scope: .modules, id: id, title: id,
                                frame: CGRect(x: 0, y: CGFloat(index * 50), width: 200, height: 40))
        }
        controller.move(ids[1], scope: .modules, direction: .up, settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) == [ids[1], ids[0], ids[2]])
        #expect(controller.availableDirections(ids[1], scope: .modules,
                                               settings: settings) == [.down])
        controller.move(ids[1], scope: .modules, direction: .up, settings: settings)
        #expect(settings.orderedPanelIDs(for: .modules, available: ids) == [ids[1], ids[0], ids[2]])
    }

    @Test func batteryPagesAndSupplyKeepSeparateOrders() {
        let suite = "batteryPagesAndSupplyKeepSeparateOrders"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MonitorSettings(defaults: defaults)
        let flow = PanelOrderScope.battery(.flow)
        let health = PanelOrderScope.battery(.health)
        let supply = PanelOrderScope.battery(.supply)
        let flowIDs = PanelOrderCatalog.defaultIDs(for: flow)
        let supplyIDs = PanelOrderCatalog.defaultIDs(for: supply)
        #expect(flowIDs.count > 1)
        #expect(supplyIDs.count > 1)
        #expect(settings.movePanelItem(flowIDs[1], in: flow, before: flowIDs[0], visible: flowIDs))
        #expect(settings.movePanelItem(supplyIDs[1], in: supply, before: supplyIDs[0], visible: supplyIDs))
        let modules = PanelOrderCatalog.defaultIDs(for: .modules)
        #expect(settings.movePanelItem(PanelOrderCatalog.displayID, in: .modules,
                                       before: modules[0], visible: modules))
        #expect(settings.panelOrder(for: health) == PanelOrderCatalog.defaultIDs(for: health))
        #expect(settings.orderedPanelIDs(for: supply, available: [supplyIDs[0], supplyIDs[1]]) ==
                [supplyIDs[1], supplyIDs[0]])
        let visibleBeforeReset = settings.visibleKinds
        let expandedBeforeReset = settings.defaultExpandedKinds
        settings.restoreDefaultMetricOrder(for: .battery)
        #expect(settings.panelOrder(for: flow) == flowIDs)
        #expect(settings.panelOrder(for: supply) == supplyIDs)
        #expect(settings.panelOrder(for: .modules).first == PanelOrderCatalog.displayID)
        #expect(settings.visibleKinds == visibleBeforeReset)
        #expect(settings.defaultExpandedKinds == expandedBeforeReset)
    }
}
