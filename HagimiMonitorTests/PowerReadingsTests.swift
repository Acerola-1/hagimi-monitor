import Foundation
import Testing
@testable import HagimiMonitorDirect

struct PowerReadingsTests {
    private func module(status: String, input: Double? = 13.1, load: Double? = 7,
                        flow: Double? = 6.1, charging: Double? = 6.1,
                        placeholder: Bool = false) -> MonitorModule {
        MonitorModule(kind: .battery, value: 76, summary: "76%", metrics: [
            MonitorMetric(name: "type", value: "battery"),
            MonitorMetric(name: "status", value: status),
            MonitorMetric(name: "power-in", value: wattString(input), numericValue: input),
            MonitorMetric(name: "power", value: wattString(load), numericValue: load),
            MonitorMetric(name: "battery-flow", value: wattString(flow), numericValue: flow),
            MonitorMetric(name: "charging-power", value: wattString(charging), numericValue: charging)
        ], samples: [], isPlaceholder: placeholder)
    }

    @Test func headerKeepsAdapterInputSeparateFromBatteryCharging() {
        let readings = PowerReadings(module: module(status: "charging"))
        #expect(readings.inputText == "13.1 W")
        #expect(readings.loadText == "7.0 W")
        #expect(readings.batteryText == "6.1 W")
        #expect(PowerReadings(module: module(status: "ac-power", flow: nil)).inputText == "13.1 W")
    }

    @Test func unpluggingDoesNotRepurposeTheInputSlotOrConsumeStaleInput() {
        let readings = PowerReadings(module: module(status: "on-battery", flow: -7))
        #expect(readings.inputText == "—")
        #expect(readings.batteryText == "7.0 W")
        #expect(readings.loadText == "7.0 W")
    }

    @Test func unavailableBatteryTelemetryIsNotInventedFromInputMinusLoad() {
        let readings = PowerReadings(module: module(status: "charging", flow: nil, charging: nil))
        #expect(readings.batteryText == "—")
        #expect(PowerReadings(module: module(status: "charging", flow: nil, charging: 5)).batteryText == "5.0 W")
        #expect(PowerReadings(module: module(status: "maintain", flow: nil)).batteryText == "—")
        #expect(PowerReadings(module: module(status: "ac-power")).batteryText == nil)
    }

    @Test func placeholderAndInvalidReadingsStayUnavailable() {
        let missing = PowerReadings(module: module(status: "charging", placeholder: true))
        #expect(missing.inputText == "—")
        #expect(missing.loadText == "—")
        #expect(missing.batteryText == nil)
        let invalid = PowerReadings(module: module(status: "charging", input: -.infinity, load: -7, flow: .nan, charging: 0))
        #expect(invalid.inputText == "—")
        #expect(invalid.loadText == "—")
        #expect(invalid.batteryText == "—")
    }
}
