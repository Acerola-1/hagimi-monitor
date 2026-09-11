import Foundation
import Testing
@testable import HagimiMonitorDirect

// MARK: - 状态机

@Suite("压力告警状态机")
struct PressureAlertStateMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let sustain: TimeInterval = 60
    private let gap: TimeInterval = 30

    private func feed(
        _ machine: inout PressureAlertStateMachine,
        memory: Int? = 0,
        thermal: Int? = 0,
        at offset: TimeInterval
    ) -> [PressureAlertStateMachine.Alert] {
        machine.ingest(
            memoryLevel: memory,
            thermalLevel: thermal,
            at: t0.addingTimeInterval(offset),
            sustain: sustain,
            breakThreshold: gap
        )
    }

    /// 按生产帧率(每秒一帧)连喂同一组档位,返回期间产生的全部通知。
    private func hold(
        _ machine: inout PressureAlertStateMachine,
        memory: Int? = 0,
        thermal: Int? = 0,
        seconds: ClosedRange<Int>
    ) -> [PressureAlertStateMachine.Alert] {
        var alerts: [PressureAlertStateMachine.Alert] = []
        for second in seconds {
            alerts += feed(&machine, memory: memory, thermal: thermal, at: TimeInterval(second))
        }
        return alerts
    }

    @Test func warningLevelLightsUnreadWithoutNotification() {
        var machine = PressureAlertStateMachine()
        let alerts = feed(&machine, memory: 1, at: 0)
        #expect(alerts.isEmpty)
        #expect(machine.isUnread(.menuBar))
        #expect(machine.isUnread(.statisticsEntry))
    }

    @Test func severeLevelNotifiesOnlyAfterSustainedWindow() {
        var machine = PressureAlertStateMachine()
        // 59 秒内不打扰。
        #expect(hold(&machine, memory: 2, seconds: 0...59).isEmpty)
        // 满 60 秒发一条,同 episode 同档位不再重复。
        let alerts = hold(&machine, memory: 2, seconds: 60...300)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2)])
        #expect(machine.isUnread(.menuBar))
    }

    @Test func recoveryClearsEveryEntryEvenIfNeverViewed() {
        var machine = PressureAlertStateMachine()
        #expect(hold(&machine, memory: 1, seconds: 0...5).isEmpty)
        #expect(machine.isUnread(.menuBar))
        #expect(machine.isUnread(.statisticsEntry))
        _ = hold(&machine, memory: 0, seconds: 6...10)
        #expect(!machine.isUnread(.menuBar))
        #expect(!machine.isUnread(.statisticsEntry))
    }

    @Test func entryReadMarksAreIndependent() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 1, seconds: 0...10)
        #expect(machine.isUnread(.menuBar))
        #expect(machine.isUnread(.statisticsEntry))
        // 点开面板:只清菜单栏那一处,面板统计入口仍亮。
        machine.markRead(.menuBar)
        #expect(!machine.isUnread(.menuBar))
        #expect(machine.isUnread(.statisticsEntry))
        // 同档位持续:已读的入口不重新点亮。
        _ = hold(&machine, memory: 1, seconds: 11...20)
        #expect(!machine.isUnread(.menuBar))
        // 查看统计页:全部入口已读。
        machine.markAllRead()
        #expect(!machine.isUnread(.menuBar))
        #expect(!machine.isUnread(.statisticsEntry))
        // 档位升级:全部入口重新点亮。
        _ = hold(&machine, memory: 2, seconds: 21...21)
        #expect(machine.isUnread(.menuBar))
        #expect(machine.isUnread(.statisticsEntry))
    }

    @Test func thermalFairAloneDoesNotLightTheDot() {
        var machine = PressureAlertStateMachine()
        // 轻微热压力不计为告警(与统计页「压力情况」口径一致)。
        #expect(hold(&machine, thermal: 1, seconds: 0...120).isEmpty)
        #expect(!machine.isUnread(.menuBar))
        // 升到严重档才进入告警;回落到轻微档即结束 episode。
        _ = hold(&machine, thermal: 2, seconds: 121...130)
        #expect(machine.isUnread(.menuBar))
        _ = hold(&machine, thermal: 1, seconds: 131...140)
        #expect(!machine.isUnread(.menuBar))
    }

    @Test func escalationRestartsSustainClockAndNotifiesNewLevel() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 1, seconds: 0...10)
        // 升级到严重档:低级档已持续的时间不继承,从升级时刻重新计时。
        var alerts = hold(&machine, memory: 2, seconds: 11...69)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, memory: 2, seconds: 70...80)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2)])
        // 热临界是独立档位,同样从升级时刻重新计时。
        alerts = hold(&machine, thermal: 3, seconds: 81...140)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, thermal: 3, seconds: 141...150)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .thermal, level: 3)])
    }

    @Test func peakFallsBackBelowSevereDoesNotNotify() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, seconds: 0...0)
        // 严重档只持续几秒就回落到警告档:不补发严重档通知。
        _ = hold(&machine, memory: 1, seconds: 1...120)
        #expect(machine.isUnread(.menuBar))
    }

    @Test func missingObservationKeepsEpisode() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, seconds: 0...0)
        // 数据源短暂缺失(< 断档阈值):不分断 episode,持续计时照走。
        _ = hold(&machine, memory: nil, seconds: 1...5)
        #expect(machine.isUnread(.menuBar))
        let alerts = hold(&machine, memory: 2, seconds: 6...61)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2)])
    }

    @Test func longGapRestartsSustainClockWithoutClearingUnread() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, seconds: 0...0)
        _ = hold(&machine, memory: nil, seconds: 1...5)
        // 断档(睡眠/停摆)后新帧:持续计时重新起算,跨断档不累计。
        var alerts = hold(&machine, memory: 2, seconds: 100...159)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, memory: 2, seconds: 160...170)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2)])
        #expect(machine.isUnread(.menuBar))
    }

    @Test func kindsAreIndependent() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 1, seconds: 0...5)
        _ = hold(&machine, memory: 0, seconds: 6...10)
        #expect(!machine.isUnread(.menuBar))
        _ = hold(&machine, thermal: 2, seconds: 11...20)
        #expect(machine.isUnread(.menuBar))
        let alerts = hold(&machine, memory: nil, thermal: 2, seconds: 21...71)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2)])
    }

    @Test func resetDropsEpisodeAndSustainClock() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, thermal: 2, seconds: 0...10)
        machine.reset()
        #expect(!machine.isUnread(.menuBar))
        #expect(!machine.isUnread(.statisticsEntry))
        // 重置后重新计时:旧 episode 已积累的持续时长不继承。
        var alerts = hold(&machine, memory: 2, seconds: 100...159)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, memory: 2, seconds: 160...170)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2)])
    }
}

// MARK: - 档位提取

@Suite("压力档位提取")
struct PressureLevelExtractionTests {
    private func module(
        _ kind: MonitorKind,
        metrics: [MonitorMetric] = [],
        placeholder: Bool = false
    ) -> MonitorModule {
        var module = MonitorModule(kind: kind, value: 0, summary: "", metrics: metrics, samples: [])
        module.isPlaceholder = placeholder
        return module
    }

    private func levelMetric(_ name: String, _ raw: Double) -> MonitorMetric {
        MonitorMetric(name: name, value: String(Int(raw)), numericValue: raw)
    }

    @Test func extractsBothLevelsFromRealSources() {
        let modules = [
            module(.memory, metrics: [levelMetric("pressure-level", 2)]),
            module(.cpu, metrics: [levelMetric("thermal-pressure", 2)]),
        ]
        let levels = PressureAlertCenter.levels(from: modules)
        #expect(levels.memory == 2)
        #expect(levels.thermal == 2)
    }

    @Test func unknownMemoryLevelCountsAsNoObservation() {
        let modules = [module(.memory, metrics: [levelMetric("pressure-level", 3)])]
        #expect(PressureAlertCenter.levels(from: modules).memory == nil)
    }

    @Test func outOfRangeThermalLevelCountsAsNoObservation() {
        let modules = [module(.cpu, metrics: [levelMetric("thermal-pressure", 9)])]
        #expect(PressureAlertCenter.levels(from: modules).thermal == nil)
    }

    @Test func placeholderModuleIsSkipped() {
        let modules = [
            module(.memory, metrics: [levelMetric("pressure-level", 2)], placeholder: true),
            module(.cpu, metrics: [levelMetric("thermal-pressure", 1)], placeholder: true),
        ]
        let levels = PressureAlertCenter.levels(from: modules)
        #expect(levels.memory == nil)
        #expect(levels.thermal == nil)
    }

    @Test func missingMetricCountsAsNoObservation() {
        let modules = [module(.memory), module(.cpu)]
        let levels = PressureAlertCenter.levels(from: modules)
        #expect(levels.memory == nil)
        #expect(levels.thermal == nil)
    }
}
