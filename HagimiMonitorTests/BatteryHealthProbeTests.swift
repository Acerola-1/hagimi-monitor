import Foundation
import Testing
@testable import HagimiMonitorDirect

struct BatteryHealthProbeTests {
    private func report(_ maximumCapacity: Any) -> [[String: Any]] {
        [[
            "_name": "spbattery_information",
            "sppower_battery_health_info": [
                "sppower_battery_health_maximum_capacity": maximumCapacity
            ],
            "BatteryData": ["NominalChargeCapacity": 6_125, "DesignCapacity": 6_249, "MaxCapacity": 100]
        ]]
    }

    @Test func systemMaximumCapacityWinsOverNinetyEightPercentCapacityRatio() {
        #expect(BatteryHealthProbe.parse(report("92%")) == 92)
        #expect(BatteryHealthProbe.parse(report("92 %")) == 92)
        #expect(BatteryHealthProbe.parse(report(NSNumber(value: 92))) == 92)
    }

    @Test func missingOrInvalidSystemValueNeverFallsBackToCapacityRatio() {
        for value: Any in ["--", "98 mAh", "98", "98.5%", "101%", "-1%", NSNumber(value: true), NSNumber(value: 98.5)] {
            #expect(BatteryHealthProbe.parse(report(value)) == nil)
        }
        #expect(BatteryHealthProbe.parse([["_name": "spbattery_information", "NominalChargeCapacity": 6_125, "DesignCapacity": 6_249]]) == nil)
        #expect(BatteryHealthProbe.parse([]) == nil)
    }

    @Test func nestedBatteryReportIsAcceptedButOtherPowerSourcesAreNot() {
        #expect(BatteryHealthProbe.parse([["_items": report("92%")]]) == 92)
        var ups = report("98%")
        ups[0]["_name"] = "ups_information"
        #expect(BatteryHealthProbe.parse(ups) == nil)
        #expect(BatteryHealthProbe.parse(ups + report("92%")) == 92)
    }

    @Test func cacheRefreshIsSingleFlightAndDoesNotSmoothChangedSystemValues() {
        var cache = BatteryHealthProbe.Cache()
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(cache.value(at: start) == nil)
        let refresh1 = cache.beginRefresh(at: start)
        #expect(refresh1)
        let refresh2 = !cache.beginRefresh(at: start.addingTimeInterval(30))
        #expect(refresh2)
        cache.finishRefresh(percent: 98, failed: false, at: start)
        let refresh3 = !cache.beginRefresh(at: start.addingTimeInterval(299))
        #expect(refresh3)
        let refresh4 = cache.beginRefresh(at: start.addingTimeInterval(300))
        #expect(refresh4)
        cache.finishRefresh(percent: 92, failed: false, at: start.addingTimeInterval(300))
        #expect(cache.value(at: start.addingTimeInterval(300)) == 92)
    }

    @Test func failedRefreshRetriesWithBoundedOldValue() {
        var cache = BatteryHealthProbe.Cache()
        let start = Date(timeIntervalSince1970: 1_000)
        let refresh5 = cache.beginRefresh(at: start)
        #expect(refresh5)
        cache.finishRefresh(percent: 92, failed: false, at: start)
        let refresh6 = cache.beginRefresh(at: start.addingTimeInterval(300))
        #expect(refresh6)
        cache.finishRefresh(percent: nil, failed: true, at: start.addingTimeInterval(300))
        #expect(cache.value(at: start.addingTimeInterval(359)) == 92)
        let refresh7 = !cache.beginRefresh(at: start.addingTimeInterval(359))
        #expect(refresh7)
        let refresh8 = cache.beginRefresh(at: start.addingTimeInterval(360))
        #expect(refresh8)
        #expect(cache.value(at: start.addingTimeInterval(900)) == nil)
        #expect(cache.value(at: start.addingTimeInterval(-1)) == nil)
    }

    @Test func successfulReportWithoutHealthClearsPreviousValue() {
        var cache = BatteryHealthProbe.Cache()
        let start = Date(timeIntervalSince1970: 1_000)
        let refresh9 = cache.beginRefresh(at: start)
        #expect(refresh9)
        cache.finishRefresh(percent: 92, failed: false, at: start)
        let refresh10 = cache.beginRefresh(at: start.addingTimeInterval(300))
        #expect(refresh10)
        cache.finishRefresh(percent: nil, failed: false, at: start.addingTimeInterval(300))
        #expect(cache.value(at: start.addingTimeInterval(300)) == nil)
    }

    @Test func slowReportDoesNotBlockSamplingOrStartDuplicateReads() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let probe = BatteryHealthProbe(load: {
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return [["_name": "spbattery_information", "sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": "92%"]]]
        })
        defer { release.signal() }
        #expect(probe.percent() == nil)
        #expect(started.wait(timeout: .now() + 1) == .success)
        for _ in 0..<100 {
            #expect(probe.percent() == nil)
        }
        release.signal()
        for _ in 0..<100 {
            if probe.percent() == 92 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(probe.percent() == 92)
        #expect(started.wait(timeout: .now()) == .timedOut)

        let module = BatterySampler(healthProbe: probe).sample(previous: nil)
        if module.metrics.first(where: { $0.name == "type" })?.value == "battery" {
            let health = module.metrics.first(where: { $0.name == "health" })
            #expect(health?.value == "92%")
            #expect(health?.numericValue == 92)
        }
    }
}
