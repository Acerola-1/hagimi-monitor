import Testing
@testable import HagimiMonitorDirect

struct PowerTelemetryTests {
    private func counter(_ value: Int64, _ timestamp: UInt64, id: String = "rail", scale: Double = 0.001) -> [PowerEnergyCounter] {
        [PowerEnergyCounter(identity: id, value: value, joulesPerCount: scale, timestamp: timestamp)]
    }

    @Test func healthyIdleAndFrozenZeroHaveDifferentEvidence() {
        var tracker = PowerCounterTracker()
        #expect(tracker.update(counter(100, 1000), at: 0, source: .energyModel).state == .warmingUp)
        #expect(tracker.update(counter(110, 1100), at: 1, source: .energyModel).watts == 0.01)
        let zero = tracker.update(counter(110, 1200), at: 2, source: .energyModel)
        #expect(zero.watts == 0 && zero.intervalStart == 1 && zero.intervalEnd == 2)
        #expect(tracker.update(counter(110, 1200), at: 3, source: .energyModel).state == .unavailable)
        #expect(tracker.update(counter(110, 1200), at: 7, source: .energyModel).state == .frozen)
        #expect(tracker.update(counter(110, 1200), at: 8, source: .energyModel).state == .frozen)
        #expect(tracker.update(counter(9000, 1600), at: 9, source: .energyModel).state == .warmingUp)
        let recovered = tracker.update(counter(9000, 1700), at: 10, source: .energyModel)
        #expect(recovered.watts == 0 && recovered.intervalStart == 9)
    }

    @Test func shortTimestampStallDoesNotAttributeCatchUpToLastPoll() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(100, 1000), at: 0, source: .energyModel)
        #expect(tracker.update(counter(110, 1100), at: 1, source: .energyModel).watts == 0.01)
        for time in 2...4 {
            #expect(tracker.update(counter(110, 1100), at: Double(time), source: .energyModel).state == .unavailable)
        }
        #expect(tracker.update(counter(9000, 2000), at: 5, source: .energyModel).watts == nil)
        #expect(tracker.update(counter(9010, 2100), at: 6, source: .energyModel).watts == 0.01)
    }

    @Test func startupFrozenAndMissingReportsDoNotProduceZero() {
        var tracker = PowerCounterTracker()
        #expect(tracker.update(counter(100, 1000), at: 0, source: .energyModel).state == .warmingUp)
        #expect(tracker.update(counter(100, 1000), at: 1, source: .energyModel).state == .warmingUp)
        #expect(tracker.update(counter(100, 1000), at: 5, source: .energyModel).state == .frozen)
        #expect(tracker.update(nil, at: 6, source: .energyModel).state == .unavailable)
        #expect(tracker.update(counter(8000, 1800), at: 7, source: .energyModel).watts == nil)
        #expect(tracker.update(counter(8000, 1900), at: 8, source: .energyModel).watts == 0)
    }

    @Test func clpcNeedsPositiveEvidenceThenAcceptsIdleZero() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(0, 1000), at: 0, source: .clpc, requiresPositiveEvidence: true)
        #expect(tracker.update(counter(0, 1100), at: 1, source: .clpc, requiresPositiveEvidence: true).watts == nil)
        #expect(tracker.update(counter(0, 1500), at: 5, source: .clpc, requiresPositiveEvidence: true).state == .unverified)
        #expect(!tracker.canSelect)
        #expect(tracker.update(counter(10, 1600), at: 6, source: .clpc, requiresPositiveEvidence: true).watts == 0.01)
        #expect(!tracker.canSelect)
        #expect(tracker.update(counter(10, 1700), at: 7, source: .clpc, requiresPositiveEvidence: true).watts == 0)
        #expect(tracker.canSelect)
        tracker.rebaseForSelection()
        #expect(tracker.update(counter(10, 1800), at: 8, source: .clpc, requiresPositiveEvidence: true).watts == 0)
        #expect(tracker.update(counter(10, 1900, id: "new-generation"), at: 9, source: .clpc, requiresPositiveEvidence: true).state == .warmingUp)
        #expect(!tracker.hasPositiveEvidence)
    }

    @Test func resetScaleMembershipAndLongGapsRebuildBaseline() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(100, 1000), at: 0, source: .energyModel)
        #expect(tracker.update(counter(10, 1100), at: 1, source: .energyModel).watts == nil)
        #expect(tracker.update(counter(20, 1200), at: 2, source: .energyModel).state == .warmingUp)
        #expect(tracker.update(counter(30, 1300), at: 3, source: .energyModel).watts == 0.01)
        #expect(tracker.update(counter(40, 1400, scale: 1e-6), at: 4, source: .energyModel).state == .warmingUp)
        #expect(tracker.update(counter(10000, 3000), at: 40, source: .energyModel).watts == nil)
        #expect(tracker.update(counter(10010, 3100), at: 41, source: .energyModel).watts == 0.01)
        #expect(tracker.update(counter(10020, 3100), at: 42, source: .energyModel).state == .unavailable)
        #expect(tracker.update(counter(-1, 3200), at: 43, source: .energyModel).watts == nil)
        #expect(tracker.update(counter(10030, 0), at: 44, source: .energyModel).watts == nil)
    }

    @Test func multiRailDeltasPreservePrecisionAndRequireAllMembers() {
        var tracker = PowerCounterTracker()
        let initial = counter(Int64.max - 100, 1000, id: "a", scale: 1e-9)
            + counter(100, 1000, id: "b", scale: 1e-3)
        _ = tracker.update(initial, at: 0, source: .energyModel)
        let next = counter(Int64.max - 90, 1100, id: "a", scale: 1e-9)
            + counter(102, 1100, id: "b", scale: 1e-3)
        #expect(tracker.update(next.reversed(), at: 1, source: .energyModel).watts == 0.00200001)
        #expect(tracker.update(counter(103, 1200, id: "b"), at: 2, source: .energyModel).state == .warmingUp)
    }

    @Test func displayIntervalHoldsOriginalEndpointsAndExpires() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(100, 1000), at: 0, source: .display, screen: .active)
        #expect(tracker.update(counter(1100, 1100), at: 1, source: .display, screen: .active).watts == nil)
        let interval = tracker.update(counter(1100, 1200), at: 2, source: .display, screen: .active)
        #expect(interval.watts == 0.5 && interval.interval == 2)
        let held = tracker.update(counter(1100, 1300), at: 3, source: .display, screen: .active)
        #expect(held == interval)
        #expect(tracker.update(counter(1100, 1500), at: 5, source: .display, screen: .active).watts == 0.5)
        #expect(tracker.update(counter(1100, 1600), at: 6, source: .display, screen: .active).watts == nil)
        #expect(tracker.update(counter(1100, 1700), at: 7, source: .display, screen: .active).watts == nil)
        #expect(tracker.update(counter(20000, 1800), at: 8, source: .display, screen: .active).watts == nil)
        _ = tracker.update(counter(21000, 1900), at: 9, source: .display, screen: .active)
        #expect(tracker.update(counter(22000, 2000), at: 10, source: .display, screen: .active).watts == 1)
    }

    @Test func screenZeroRequiresInactiveAndAdvancingSource() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(100, 1000), at: 0, source: .display, screen: .inactive)
        _ = tracker.update(counter(100, 1100), at: 1, source: .display, screen: .inactive)
        #expect(tracker.update(counter(100, 1200), at: 2, source: .display, screen: .inactive).watts == 0)
        #expect(tracker.update(counter(100, 1300), at: 3, source: .display, screen: .unknown).watts == nil)
        #expect(tracker.update(counter(100, 1400), at: 4, source: .display, screen: .absent).state == .unsupported)
        tracker.reset()
        _ = tracker.update(counter(100, 1000), at: 0, source: .display, screen: .inactive)
        #expect(tracker.update(counter(100, 1000), at: 5, source: .display, screen: .inactive).state == .frozen)
    }

    @Test func expiredDisplayTimestampMustKeepAdvancingToAvoidFreeze() {
        var tracker = PowerCounterTracker()
        _ = tracker.update(counter(100, 1000), at: 0, source: .display, screen: .active)
        _ = tracker.update(counter(100, 1500), at: 5, source: .display, screen: .active)
        #expect(tracker.update(counter(100, 1600), at: 6, source: .display, screen: .active).state == .unavailable)
        #expect(tracker.update(counter(100, 1600), at: 11, source: .display, screen: .active).state == .frozen)
        #expect(tracker.update(counter(20000, 1700), at: 12, source: .display, screen: .active).watts == nil)
    }

    @Test func sourceSelectionWarmsSwitchAndDoesNotFlap() {
        func reading(_ state: PowerReading.State, _ source: PowerReading.Source) -> PowerReading {
            PowerReading(watts: 1, state: state, source: source, intervalStart: 0, intervalEnd: 1)
        }
        var selector = PowerSourceSelector()
        let missing = reading(.unavailable, .clpc)
        let legacy = reading(.valid, .energyModel)
        #expect(selector.choose(preferred: missing, preferredReady: false, fallback: legacy, fallbackReady: true, at: 0).changed)
        #expect(selector.selected == .fallback)
        #expect(selector.choose(preferred: reading(.valid, .clpc), preferredReady: true, fallback: legacy, fallbackReady: true, at: 1).changed)
        #expect(selector.selected == .preferred)
        #expect(!selector.choose(preferred: missing, preferredReady: false, fallback: legacy, fallbackReady: true, at: 2).changed)
        #expect(selector.choose(preferred: missing, preferredReady: false, fallback: legacy, fallbackReady: true, at: 6).changed)
        #expect(selector.selected == .fallback)
    }

    @Test func subscriptionFailureBacksOffAndRestartsGeneration() {
        var recovery = PowerSubscriptionRecovery<Int>()
        var attempts = 0
        func fail() -> Int? { attempts += 1; return nil }
        let _: Int? = recovery.sample(at: 0, create: fail, read: { $0 })
        let _: Int? = recovery.sample(at: 0.5, create: fail, read: { $0 })
        #expect(attempts == 1)
        let _: Int? = recovery.sample(at: 1, create: fail, read: { $0 })
        #expect(attempts == 2)
        let sample = recovery.sample(at: 3, create: { 7 }, read: { $0 })
        #expect(sample == 7 && recovery.generation == 1)
        for t in 4...6 {
            let _: Int? = recovery.sample(at: Double(t), create: { 7 }, read: { _ in nil })
        }
        #expect(recovery.handle == nil)
        #expect(recovery.sample(at: 7, create: { 8 }, read: { $0 }) == 8)
        #expect(recovery.generation == 2)
    }

    @Test func selectedIdentityChangeRequiresReadmission() {
        func reading(_ identity: String) -> PowerReading {
            PowerReading(watts: 1, state: .valid, source: .clpc, identity: identity,
                         intervalStart: 0, intervalEnd: 1)
        }
        var selector = PowerSourceSelector()
        let missing = PowerReading.missing(.unavailable, source: .energyModel, at: 0)
        #expect(selector.choose(preferred: reading("generation-1"), preferredReady: true,
            fallback: missing, fallbackReady: false, at: 0).changed)
        let reset = selector.choose(preferred: reading("generation-2"), preferredReady: false,
            fallback: missing, fallbackReady: false, at: 1)
        #expect(reset.selection == nil && reset.changed)
        #expect(selector.choose(preferred: reading("generation-2"), preferredReady: true,
            fallback: missing, fallbackReady: false, at: 2).changed)
        #expect(selector.selected == .preferred)
    }

    @Test func completeEnergyUnitsAndInvalidValues() {
        #expect(PowerEnergyUnit.joulesPerCount(0x0300007f00000000) == 1)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300000000000000) == 1)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300007c00000000) == 0.001)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300007900000000) == 1e-6)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300007600000000) == 1e-9)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300827f00000002) == 16)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300007f80000002) == 0.5)
        #expect(PowerEnergyUnit.joulesPerCount(0) == nil)
        #expect(PowerEnergyUnit.joulesPerCount(0x0300000080000000) == nil)
        #expect(PowerEnergyUnit.joulesPerCount(0x0301007f00000000) == nil)
    }

    @Test func untimedClpcRequiresContinuousGrowthAndNeverInventsIdleZero() {
        var tracker = PowerCounterTracker()
        func read(_ value: Int64, at time: Double) -> PowerReading {
            tracker.update(counter(value, 0), at: time, source: .clpc,
                requiresPositiveEvidence: true, allowsUntimedGrowth: true)
        }
        #expect(read(100, at: 0).state == .warmingUp)
        #expect(read(110, at: 1).watts == 0.01)
        #expect(read(120, at: 2).watts == 0.01)
        #expect(tracker.canSelect)
        #expect(read(120, at: 3).state == .unavailable)
        #expect(read(120, at: 8).watts == nil)
        #expect(read(9000, at: 9).state == .warmingUp)
        #expect(read(9010, at: 10).watts == 0.01)
        var idle = PowerCounterTracker()
        _ = idle.update(counter(0, 0), at: 0, source: .clpc, requiresPositiveEvidence: true, allowsUntimedGrowth: true)
        #expect(idle.update(counter(0, 0), at: 5, source: .clpc, requiresPositiveEvidence: true,
                            allowsUntimedGrowth: true).state == .unverified)
        #expect(!idle.canSelect)
    }
}
