import AppKit
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct DisplayControlMenuBarTests {
    @Test func menuBarEntryDefaultsOffAndPersistsIndependentlyOfMainPanel() {
        let suite = "DisplayControlMenuBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        #expect(!settings.displayControlMenuBarEnabled)
        settings.displayControlMenuBarEnabled = true
        settings.displayModuleVisible = false
        let restored = MonitorSettings(defaults: defaults)
        #expect(restored.displayControlMenuBarEnabled)
        #expect(!restored.displayModuleVisible)
        restored.displayControlMenuBarEnabled = false
        #expect(!MonitorSettings(defaults: defaults).displayControlMenuBarEnabled)
    }

    @Test func closingOnePanelDoesNotStopAnotherPanelsPolling() {
        let controller = DisplayControlController()
        let first = UUID(), second = UUID()
        #expect(!controller.isPollingActive)
        controller.setPolling(active: true, owner: first)
        controller.setPolling(active: true, owner: first)
        controller.setPolling(active: true, owner: second)
        controller.setPolling(active: false, owner: first)
        #expect(controller.isPollingActive)
        controller.setPolling(active: false, owner: first)
        #expect(controller.isPollingActive)
        controller.setPolling(active: false, owner: second)
        #expect(!controller.isPollingActive)
    }

    @Test func statusSymbolIsTemplateAndFitsMenuBar() {
        let image = DisplayControlStatusIcon.makeImage()
        #expect(image != nil)
        #expect(image?.isTemplate == true)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.width ?? 100) <= 24)
        #expect((image?.size.height ?? 100) <= 24)
    }
}
