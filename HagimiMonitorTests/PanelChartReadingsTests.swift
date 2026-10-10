import Foundation
import Testing
@testable import HagimiMonitorDirect

struct PanelChartReadingsTests {
    @Test func memoryChoiceSelectsItsOwnHistory() {
        var module = MonitorModule(kind: .memory, value: 90, summary: "90%", metrics: [], samples: [80, 90])
        module.pressureSamples = [8, 10]
        #expect(PanelChartReadings.memorySamples(module, pressureMode: false) == [80, 90])
        #expect(PanelChartReadings.memorySamples(module, pressureMode: true) == [8, 10])
        module.pressureSamples = []
        #expect(PanelChartReadings.memorySamples(module, pressureMode: true).isEmpty)
        #expect(PanelChartReadings.memorySamples(module, pressureMode: false) == [80, 90])
        module.isPlaceholder = true
        #expect(PanelChartReadings.memorySamples(module, pressureMode: false).isEmpty)
        #expect(PanelChartReadings.memorySamples(module, pressureMode: true).isEmpty)
    }

    @Test func steadyHighAndLowHaveDistinctFixedLevels() {
        let scale = PanelChartScale()
        #expect(scale.fraction(90) == 0.9)
        #expect(scale.fraction(10) == 0.1)
        #expect(scale.fraction(0) == 0)
        #expect(scale.fraction(.nan) == nil)
        #expect(scale.fraction(.infinity) == nil)
        #expect(PanelChartScale(upper: 0).fraction(10) == nil)
    }

    @Test func runningAtHardwareMinimumIsDifferentFromStopped() throws {
        let running = FanInfo(id: 0, name: "Fan", currentRPM: 2300, minRPM: 2300, maxRPM: 6500)
        let scale = try #require(PanelChartReadings.fanScale([running]))
        #expect(scale.fraction(0) == 0)
        #expect(try #require(scale.fraction(Double(running.currentRPM))) > 0.3)
        let stopped = FanInfo(id: 0, name: "Fan", currentRPM: 0, minRPM: 2300, maxRPM: 6500)
        var module = MonitorModule(kind: .fan, value: 0, summary: "—", metrics: [], samples: [0])
        module.fans = [stopped]
        #expect(PanelChartReadings.fanSummary(module) == "0 RPM")
        module.isPlaceholder = true
        #expect(PanelChartReadings.fanSummary(module) == "—")
        #expect(PanelChartReadings.fanScale([]) == nil)
        #expect(PanelChartReadings.fanScale([FanInfo(id: 0, name: "Fan", currentRPM: 2300, minRPM: 0, maxRPM: 0)]) == nil)
    }
}
