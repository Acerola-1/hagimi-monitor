import Foundation
import Testing
@testable import HagimiMonitorDirect

@Suite("CPU temperature freshness")
struct CPUSamplerTemperatureTests {
    private final class StubTemperatureReader: CPUTemperatureReading, @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Double?]
        private(set) var callCount = 0

        init(_ readings: [Double?]) {
            self.readings = readings
        }

        func cpuTemperature() -> Double? {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            if readings.count > 1 {
                return readings.removeFirst()
            }
            return readings.first ?? nil
        }
    }

    private func temperature(in module: MonitorModule) -> MonitorMetric? {
        module.metrics.first { $0.name == "temperature" }
    }

    @Test("Disabled reads keep display cache but expose no fresh numeric sample")
    func cachedTemperatureIsNotANewObservation() {
        let reader = StubTemperatureReader([42, 43])
        let sampler = CPUSampler(smcReader: reader)

        sampler.setTemperatureReadsEnabled(true)
        let fresh = sampler.sample(previous: nil)
        #expect(reader.callCount == 1)
        #expect(temperature(in: fresh)?.numericValue == 42)

        sampler.setTemperatureReadsEnabled(false)
        let cached = sampler.sample(previous: fresh)
        #expect(reader.callCount == 1, "门控关闭后停止触碰温度键")
        #expect(temperature(in: cached)?.value == "42°C", "展示值沿用上次读数")
        #expect(temperature(in: cached)?.numericValue == nil, "缓存值不累计进统计")

        sampler.setTemperatureReadsEnabled(true)
        let resumed = sampler.sample(previous: cached)
        #expect(reader.callCount == 2)
        #expect(temperature(in: resumed)?.numericValue == 43)
    }

    @Test("Temperature gating leaves CPU usage sampling unchanged")
    func cpuUsageStillSamplesWhenTemperatureIsDisabled() {
        let reader = StubTemperatureReader([nil])
        let sampler = CPUSampler(smcReader: reader)
        sampler.setTemperatureReadsEnabled(false)

        let module = sampler.sample(previous: nil)
        #expect(module.kind == .cpu)
        #expect(module.metrics.contains { $0.name == "process-count" || $0.name == "thermal-pressure" })
        #expect(reader.callCount == 0)
    }
}

@Suite("Public IP query state")
struct PublicIPQueryStateTests {
    @Test("Disable invalidates the old request and re-enable starts a new generation")
    func reopenStartsFreshRequest() {
        var state = PublicIPQueryState()
        let old = state.beginRefresh()
        #expect(old != nil)
        #expect(state.isRefreshing)

        let disabledToken = state.setEnabled(false)
        #expect(disabledToken == nil)
        #expect(!state.isEnabled)
        #expect(!state.isRefreshing)
        let blockedToken = state.beginRefresh()
        #expect(blockedToken == nil, "关闭期间不启动查询")

        let new = state.setEnabled(true)
        #expect(new != nil)
        #expect(new != old)
        #expect(state.isCurrent(new!))
        #expect(!state.isCurrent(old!), "旧请求回调已失效")
        #expect(state.isRefreshing, "重开立即启动一次新查询")
    }

    @Test("A stale completion leaves the new request in-flight state intact")
    func staleCompletionCannotClobberNewRequest() {
        var state = PublicIPQueryState()
        let old = state.beginRefresh()!
        _ = state.setEnabled(false)
        let new = state.setEnabled(true)!

        let staleFinished = state.finish(old)
        #expect(!staleFinished)
        #expect(state.isCurrent(new))
        #expect(state.isRefreshing, "旧回调不清除新一轮在飞状态")
        let newFinished = state.finish(new)
        #expect(newFinished)
        #expect(!state.isRefreshing)
    }

    @Test("Repeated enable calls do not spawn duplicate requests")
    func repeatedEnableIsIdempotent() {
        var state = PublicIPQueryState()
        let first = state.beginRefresh()
        #expect(first != nil)
        let duplicateEnable = state.setEnabled(true)
        #expect(duplicateEnable == nil)
        let duplicateRefresh = state.beginRefresh()
        #expect(duplicateRefresh == nil)
    }
}

@Suite("Bluetooth profiler probe state")
struct ProfilerProbeStateTests {
    @Test("Production enable path obtains the in-flight slot exactly once")
    func enableThenProbeDoesNotSelfLock() {
        var state = ProfilerProbeState()
        let shouldStart = state.setEnabled(true)
        #expect(shouldStart)
        #expect(!state.isInFlight, "setEnabled 只请求启动,不预占在飞槽位")

        let started = state.request(queueIfBusy: true)
        #expect(started)
        #expect(state.isInFlight)
        let timerOverlap = state.request(queueIfBusy: false)
        #expect(!timerOverlap)
        #expect(!state.hasPendingRequest, "周期 tick 撞上在飞画像时跳过补查")
    }

    @Test("Opening while an old probe is in flight queues exactly one follow-up")
    func reopenQueuesBehindInFlightProbe() {
        var state = ProfilerProbeState()
        let shouldStart = state.setEnabled(true)
        #expect(shouldStart)
        let started = state.request(queueIfBusy: true)
        #expect(started)
        #expect(state.isInFlight)

        let disabled = state.setEnabled(false)
        #expect(disabled == false)
        #expect(!state.hasPendingRequest)
        let reopened = state.setEnabled(true)
        #expect(reopened == false, "旧画像仍在飞时跳过并发启动")

        #expect(state.hasPendingRequest)
        let queuedAgain = state.request(queueIfBusy: true)
        #expect(queuedAgain == false)
        #expect(state.hasPendingRequest)
        let continued = state.finish()
        #expect(continued, "旧画像结束后立即补查")
        #expect(!state.isInFlight)
        #expect(!state.hasPendingRequest)
    }

    @Test("Disabling drops the pending follow-up but lets the running probe finish")
    func disableDropsPendingFollowUp() {
        var state = ProfilerProbeState()
        let shouldStart = state.setEnabled(true)
        #expect(shouldStart)
        let started = state.request(queueIfBusy: true)
        #expect(started)
        let overlapping = state.request(queueIfBusy: true)
        #expect(overlapping == false)
        #expect(state.hasPendingRequest)

        let disabled = state.setEnabled(false)
        #expect(disabled == false)
        #expect(!state.hasPendingRequest)
        #expect(state.isInFlight)
        let continued = state.finish()
        #expect(!continued, "关闭后旧画像结束不启动补查")
        #expect(!state.isInFlight)
    }

    @Test("Reset invalidates running and pending state for restart")
    func resetClearsEverything() {
        var state = ProfilerProbeState()
        let shouldStart = state.setEnabled(true)
        #expect(shouldStart)
        let started = state.request(queueIfBusy: true)
        #expect(started)
        state.reset()

        #expect(!state.isEnabled)
        #expect(!state.isInFlight)
        #expect(!state.hasPendingRequest)
        let restarted = state.request(queueIfBusy: true)
        #expect(!restarted)
    }
}

@Suite("Game HUD temperature freshness")
struct GameHUDTemperatureFreshnessTests {
    @Test("HUD does not display a cached temperature as a live reading")
    func cachedTemperatureIsMissingInHUD() {
        let cached = MonitorModule(
            kind: .cpu,
            value: 20,
            summary: "",
            metrics: [
                MonitorMetric(name: "temperature", value: "42°C", numericValue: nil),
                MonitorMetric(name: "thermal-pressure", value: "normal", numericValue: 0)
            ],
            samples: []
        )
        let cachedReading = GameHUDSnapshotProvider.readings(
            enabledIDs: [.cpuTemperature], in: [cached]
        ).first { $0.metricID == GameHUDMetricID.cpuTemperature.rawValue }
        #expect(cachedReading?.value == nil, "首帧缓存温度显示缺失")

        var fresh = cached
        fresh.metrics[0] = MonitorMetric(name: "temperature", value: "42°C", numericValue: 42)
        let freshReading = GameHUDSnapshotProvider.readings(
            enabledIDs: [.cpuTemperature], in: [fresh]
        ).first { $0.metricID == GameHUDMetricID.cpuTemperature.rawValue }
        #expect(freshReading?.value?.contains("42°C") == true)
    }
}

@Suite("Menu bar badge presentation")
struct MenuBarBadgePresentationTests {
    @Test("HUD badge is drawn only when alert is absent")
    func alertTakesPriority() {
        let hud = MenuBarBadgePresentation(showsAlert: false, showsHUDBadge: true)
        #expect(hud.needsOverlay)
        #expect(hud.drawsHUD)
        #expect(!hud.drawsAlert)

        let both = MenuBarBadgePresentation(showsAlert: true, showsHUDBadge: true)
        #expect(both.needsOverlay)
        #expect(both.drawsAlert)
        #expect(!both.drawsHUD)

        let none = MenuBarBadgePresentation(showsAlert: false, showsHUDBadge: false)
        #expect(!none.needsOverlay)
    }

    @Test("HUD state participates in the metrics render key")
    func hudStateChangesRenderKey() {
        let items = [MenuBarMetricItem(kind: .cpuUsage, value: "10%")]
        let withoutHUD = MenuBarMetricsRenderKey(
            items: items,
            isDark: false,
            layout: .icon,
            scale: 2,
            badge: .init(showsAlert: false, showsHUDBadge: false)
        )
        let withHUD = MenuBarMetricsRenderKey(
            items: items,
            isDark: false,
            layout: .icon,
            scale: 2,
            badge: .init(showsAlert: false, showsHUDBadge: true)
        )

        #expect(withoutHUD != withHUD, "数值未变时 HUD 起灭仍触发重绘")
    }
}
