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
        at offset: TimeInterval,
        cooldown: TimeInterval = 0
    ) -> [PressureAlertStateMachine.Alert] {
        machine.ingest(
            memoryLevel: memory,
            thermalLevel: thermal,
            at: t0.addingTimeInterval(offset),
            sustain: sustain,
            breakThreshold: gap,
            cooldown: cooldown
        )
    }

    /// 按生产帧率(每秒一帧)连喂同一组档位,返回期间产生的全部通知。
    private func hold(
        _ machine: inout PressureAlertStateMachine,
        memory: Int? = 0,
        thermal: Int? = 0,
        seconds: ClosedRange<Int>,
        cooldown: TimeInterval = 0
    ) -> [PressureAlertStateMachine.Alert] {
        var alerts: [PressureAlertStateMachine.Alert] = []
        for second in seconds {
            alerts += feed(&machine, memory: memory, thermal: thermal, at: TimeInterval(second), cooldown: cooldown)
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
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
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
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
        // 热临界是独立档位,同样从升级时刻重新计时。
        alerts = hold(&machine, thermal: 3, seconds: 81...140)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, thermal: 3, seconds: 141...150)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .thermal, level: 3, deliveryID: 2)])
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
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
    }

    @Test func longGapRestartsSustainClockWithoutClearingUnread() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, seconds: 0...0)
        _ = hold(&machine, memory: nil, seconds: 1...5)
        // 断档(睡眠/停摆)后新帧:持续计时重新起算,跨断档不累计。
        var alerts = hold(&machine, memory: 2, seconds: 100...159)
        #expect(alerts.isEmpty)
        alerts = hold(&machine, memory: 2, seconds: 160...170)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
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
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])
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
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
    }

    @Test func crossEpisodeCooldownSuppressesImmediateRepeatButFiresAfterExpiry() throws {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60

        let first = hold(&machine, memory: 2, seconds: 0...60, cooldown: cooldown)
        #expect(first == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 1)])
        let firstAlert = try #require(first.first)
        machine.completeNotification(for: firstAlert, delivered: true, at: t0.addingTimeInterval(61))

        // 恢复并在 5 分钟后再次持续严重 60 秒：处于 15 分钟冷却期内，仅亮红点、不发重复通知。
        _ = hold(&machine, memory: 0, seconds: 65...70, cooldown: cooldown)
        let duringCooldown = hold(&machine, memory: 2, seconds: 360...420, cooldown: cooldown)
        #expect(duringCooldown.isEmpty)
        #expect(machine.isUnread(.menuBar))

        // 恢复并跨过 16 分钟后再次持续严重：冷却期已过，恢复通知。
        _ = hold(&machine, memory: 0, seconds: 425...430, cooldown: cooldown)
        let afterCooldown = hold(&machine, memory: 2, seconds: 1020...1080, cooldown: cooldown)
        #expect(afterCooldown == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 2)])
    }

    @Test func sameEpisodeEscalationIsNotBlockedByCooldown() {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60

        let serious = hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown)
        #expect(serious == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])

        // 同 episode 内紧接着升级到临界并持续 60 秒：不得被 15 分钟冷却拦住。
        let escalated = hold(&machine, thermal: 3, seconds: 61...125, cooldown: cooldown)
        #expect(escalated == [PressureAlertStateMachine.Alert(kind: .thermal, level: 3, deliveryID: 2)])
    }

    @Test func resetSingleKindPreservesOtherActiveDimension() {
        var machine = PressureAlertStateMachine()
        _ = hold(&machine, memory: 2, thermal: 2, seconds: 0...30)
        machine.reset(.memory)

        // 热维度未读与计时保留，满 60 秒正常触发；内存被清空后重头计时，不随热一起提前触发。
        let alerts = hold(&machine, memory: 2, thermal: 2, seconds: 31...60)
        #expect(alerts == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])
        #expect(machine.isUnread(.menuBar))

        // 内存从 31s 起重新计时，满 60s（91s）才独立触发。
        #expect(hold(&machine, memory: 2, thermal: 2, seconds: 61...90).isEmpty)
        let memoryAlerts = hold(&machine, memory: 2, thermal: 2, seconds: 91...95)
        #expect(memoryAlerts == [PressureAlertStateMachine.Alert(kind: .memory, level: 2, deliveryID: 2)])
    }

    @Test func thermalDowngradeFromCriticalToSeriousDoesNotNotifyAgain() {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60

        let serious = hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown)
        #expect(serious == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])

        let critical = hold(&machine, thermal: 3, seconds: 61...121, cooldown: cooldown)
        #expect(critical == [PressureAlertStateMachine.Alert(kind: .thermal, level: 3, deliveryID: 2)])

        // 同一 episode 内从临界(3)降回严重(2)，即便持续超过 sustain 也不再重复弹出严重档通知。
        let downgraded = hold(&machine, thermal: 2, seconds: 122...242, cooldown: cooldown)
        #expect(downgraded.isEmpty)
    }

    @Test func rollbackNotificationRestoresLevelAndCooldownWithoutStorm() throws {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60

        // 1. 同 episode 内投递失败回滚：重置持续计时，不在下一秒形成风暴，满新 sustain 后允许重试。
        let first = hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown)
        let firstAlert = try #require(first.first)
        #expect(first == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])
        machine.completeNotification(for: firstAlert, delivered: false, at: t0.addingTimeInterval(61))
        #expect(hold(&machine, thermal: 2, seconds: 62...120, cooldown: cooldown).isEmpty)
        let retried = hold(&machine, thermal: 2, seconds: 121...125, cooldown: cooldown)
        let retriedAlert = try #require(retried.first)
        #expect(retried == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 2)])

        // 2. episode 已恢复后才收到迟到的投递失败回调：同样回滚冷却时间戳，不误伤下一次新 episode。
        _ = hold(&machine, thermal: 0, seconds: 126...130, cooldown: cooldown)
        machine.completeNotification(for: retriedAlert, delivered: false, at: t0.addingTimeInterval(131))
        let nextEpisode = hold(&machine, thermal: 2, seconds: 200...260, cooldown: cooldown)
        #expect(nextEpisode == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 3)])
    }

    @Test func staleRollbackDoesNotUndoNewerSameLevelNotification() throws {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60

        let first = hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown)
        let firstAlert = try #require(first.first)
        #expect(first == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 1)])

        // 恢复并在冷却期过后产生更新的同档(严重)通知。
        _ = hold(&machine, thermal: 0, seconds: 65...70, cooldown: cooldown)
        let second = hold(&machine, thermal: 2, seconds: 1020...1080, cooldown: cooldown)
        let secondAlert = try #require(second.first)
        #expect(second == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 2)])
        #expect(secondAlert.deliveryID != firstAlert.deliveryID)

        // 旧请求 #1 迟到报失败，不得撤销新请求 #2 的已通知档位或冷却记录。
        machine.completeNotification(for: firstAlert, delivered: false, at: t0.addingTimeInterval(1081))
        #expect(hold(&machine, thermal: 2, seconds: 1082...1200, cooldown: cooldown).isEmpty)

        _ = hold(&machine, thermal: 0, seconds: 1201...1205, cooldown: cooldown)
        #expect(hold(&machine, thermal: 2, seconds: 1300...1360, cooldown: cooldown).isEmpty)

        // reset 后重新产生同档通知，reset 前的旧请求同样不得误回滚。
        machine.reset(.thermal)
        let afterReset = hold(&machine, thermal: 2, seconds: 1400...1460, cooldown: cooldown)
        #expect(afterReset == [PressureAlertStateMachine.Alert(kind: .thermal, level: 2, deliveryID: 3)])
        machine.completeNotification(for: secondAlert, delivered: false, at: t0.addingTimeInterval(1461))
        #expect(hold(&machine, thermal: 2, seconds: 1462...1550, cooldown: cooldown).isEmpty)
    }

    @Test(arguments: [true, false])
    func twoFailedOverlappingThermalNotificationsAllowDowngradedRetry(olderFailsFirst: Bool) throws {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60
        let serious = try #require(hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown).first)
        let critical = try #require(hold(&machine, thermal: 3, seconds: 61...121, cooldown: cooldown).first)
        #expect(serious.level == 2)
        #expect(critical.level == 3)

        machine.completeNotification(for: olderFailsFirst ? serious : critical, delivered: false, at: t0.addingTimeInterval(122))
        machine.completeNotification(for: olderFailsFirst ? critical : serious, delivered: false, at: t0.addingTimeInterval(123))
        #expect(hold(&machine, thermal: 2, seconds: 124...182, cooldown: cooldown).isEmpty)
        let retry = hold(&machine, thermal: 2, seconds: 183...190, cooldown: cooldown)
        #expect(retry.map(\.level) == [2])
    }

    @Test(arguments: [2, 3])
    func failedThermalNotificationPreservesTheOtherConfirmedLevel(confirmedLevel: Int) throws {
        var machine = PressureAlertStateMachine()
        let cooldown: TimeInterval = 15 * 60
        let serious = try #require(hold(&machine, thermal: 2, seconds: 0...60, cooldown: cooldown).first)
        let critical = try #require(hold(&machine, thermal: 3, seconds: 61...121, cooldown: cooldown).first)

        machine.completeNotification(
            for: confirmedLevel == 2 ? serious : critical, delivered: true, at: t0.addingTimeInterval(122)
        )
        machine.completeNotification(
            for: confirmedLevel == 2 ? critical : serious, delivered: false, at: t0.addingTimeInterval(123)
        )
        #expect(hold(&machine, thermal: 2, seconds: 124...190, cooldown: cooldown).isEmpty)

        let retriedUpgrades = hold(&machine, thermal: 3, seconds: 191...255, cooldown: cooldown)
        #expect(retriedUpgrades.map(\.level) == (confirmedLevel == 2 ? [3] : []))
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
