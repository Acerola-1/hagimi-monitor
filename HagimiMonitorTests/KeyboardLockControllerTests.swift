import Foundation
import Testing
@testable import HagimiMonitorDirect

struct KeyboardLockControllerTests {
    @Test func keyboardLockScopeProperties() {
        #expect(KeyboardLockScope.allCases.count == 2)
        #expect(KeyboardLockScope.internalOnly.rawValue == "internalOnly")
        #expect(KeyboardLockScope.all.rawValue == "all")
    }

    /// 自动解锁档位是「防锁了就忘」的兜底,必须有一档默认值、且不含"永不"
    /// (永不等于关掉兜底,锁死后只能靠鼠标自救)。
    @Test func autoUnlockMinuteOptionsAreBounded() {
        #expect(KeyboardLockController.autoUnlockMinuteOptions == [10, 20, 30, 60])
        #expect(KeyboardLockController.defaultAutoUnlockMinutes == 20)
        #expect(KeyboardLockController.autoUnlockMinuteOptions.contains(KeyboardLockController.defaultAutoUnlockMinutes))
    }

    /// 自动解锁时长是唯一持久化的键盘锁定设置:设置页写入、QuickToolsStore
    /// 启动时按同一常量恢复。字面量是落盘格式,不能随重构漂移。
    @Test func settingsAutoUnlockMinutesPersistence() {
        let suite = "settingsAutoUnlockMinutesPersistence"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.keyboardLockAutoUnlockMinutes == 20)

        settings.keyboardLockAutoUnlockMinutes = 30
        #expect(defaults.integer(forKey: QuickToolsStore.autoUnlockMinutesDefaultsKey) == 30)

        let reloaded = MonitorSettings(defaults: defaults)
        #expect(reloaded.keyboardLockAutoUnlockMinutes == 30)
    }

    /// 非法存量值(如手改 defaults 成 999)回落默认档,不把兜底时长放大。
    @Test func settingsAutoUnlockMinutesFallsBackOnUnknownValue() {
        let suite = "settingsAutoUnlockMinutesFallsBack"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(999, forKey: QuickToolsStore.autoUnlockMinutesDefaultsKey)

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.keyboardLockAutoUnlockMinutes == KeyboardLockController.defaultAutoUnlockMinutes)
    }

    /// 外接键盘拦截范围偏好持久化:默认 false(仅拦截内置键盘),
    /// 设置页开启后落盘,重启与重载后按同一键恢复。
    @Test func settingsBlocksExternalPersistence() {
        let suite = "settingsBlocksExternalPersistence"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.keyboardLockBlocksExternal == false)

        settings.keyboardLockBlocksExternal = true
        #expect(defaults.bool(forKey: QuickToolsStore.blocksExternalDefaultsKey) == true)

        let reloaded = MonitorSettings(defaults: defaults)
        #expect(reloaded.keyboardLockBlocksExternal == true)
    }

    @Test func scanExternalKeyboardsDoesNotCrash() {
        let keyboards = KeyboardLockController.scanExternalKeyboards()
        #expect(keyboards.count >= 0)
    }

    @Test func scanExternalKeyboardsExcludesMice() {
        let keyboards = KeyboardLockController.scanExternalKeyboards()
        for kbd in keyboards {
            #expect(!kbd.lowercased().contains("vxe"))
            #expect(!kbd.lowercased().contains("mouse"))
        }
    }

    /// 兜底时长在落锁时按用户档位确定;未指定时用默认档。
    @Test func controllerAutoUnlockIntervalFollowsRequestedMinutes() {
        let controller = KeyboardLockController()
        #expect(controller.autoUnlockInterval == TimeInterval(KeyboardLockController.defaultAutoUnlockMinutes * 60))
    }

    // MARK: - 「仅内置」事件归因

    /// 测试用归因器:1ms = 1 tick,时间窗断言直接用毫秒数表达。
    private func makeAttribution() -> KeyboardEventAttribution {
        KeyboardEventAttribution(ticksPerMillisecond: 1)
    }

    /// 主 bug 回归:内置键(空格)保持按住期间,HID 侧持续产生外接键活动,
    /// 内置键的自动重复不得因"外接侧有活动/有键按着"被放行。修复前按
    /// 「哪侧有键按下」兜底,该场景会把内置长按的重复混进外接打字流。
    @Test func autorepeatFollowsRecordedVerdictNotDownSets() {
        let a = makeAttribution()
        let space: Int64 = 49

        // 内置空格落下(时间窗归因为内置并记账)。
        a.recordHIDReport(usage: 0x2C, isDown: true, side: .builtIn, now: 1_000)
        #expect(a.decide(kind: .keyDown, keyCode: space, now: 1_100) == .builtIn)

        // 期间外接侧打字(别的键落下),内置空格自动重复到来。
        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_300)
        #expect(a.decide(kind: .keyDown, keyCode: 4, now: 1_350) == .external)

        // 空格的重复:记账是内置,即使外接侧有活动仍在窗内,也必须拦截。
        #expect(a.decide(kind: .keyDown, keyCode: space, isAutorepeat: true, now: 1_400) == .builtIn)
    }

    /// 自动重复跟随记账的正面场景:外接长按的重复放行,哪怕抬起前时间窗
    /// 已陈旧(长按不产生新 HID 报告)。
    @Test func externalAutorepeatSurvivesStaleWindows() {
        let a = makeAttribution()
        let key: Int64 = 4

        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_000)
        #expect(a.decide(kind: .keyDown, keyCode: key, now: 1_050) == .external)

        // 500ms 后无任何 HID 活动(长按中),重复应跟随记账放行。
        #expect(a.decide(kind: .keyDown, keyCode: key, isAutorepeat: true, now: 1_600) == .external)

        // 抬起同理,随后销账:再来的同键重复失去记账,默认拦截。
        #expect(a.decide(kind: .keyUp, keyCode: key, now: 1_700) == .external)
        #expect(a.decide(kind: .keyDown, keyCode: key, isAutorepeat: true, now: 1_750) == .builtIn)
    }

    /// 记账缺失(锁定中途开始/热切换 reset)时,自动重复退回时间窗:
    /// 陈旧证据下判内置拦截,不因另一侧有键按着而放行。
    @Test func autorepeatWithoutVerdictFallsBackToWindow() {
        let a = makeAttribution()
        a.recordHIDReport(usage: 0x2C, isDown: true, side: .builtIn, now: 1_000)
        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_100)
        a.reset()

        // reset 后两侧时间戳归零(远古),两侧都各有键按着:
        // 旧实现按按下集合并列先查外接,会放行;新实现判内置拦截。
        #expect(a.decide(kind: .keyDown, keyCode: 49, isAutorepeat: true, now: 9_999_999) == .builtIn)
    }

    /// 时间窗归因:更近的一侧胜出;同窗打平判外接(存疑时放行代价更小)。
    @Test func timeWindowPrefersCloserSideAndTiesToExternal() {
        let a = makeAttribution()
        // 仅内置活动:拦截。
        a.recordHIDReport(usage: 0x04, isDown: true, side: .builtIn, now: 1_000)
        #expect(a.decide(kind: .keyDown, keyCode: 4, now: 1_050) == .builtIn)

        // 100ms 内两侧都有活动,外接更近:放行。
        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_090)
        #expect(a.decide(kind: .keyDown, keyCode: 11, now: 1_095) == .external)

        // 全新归因器,同刻活动打平:判外接。
        let tied = makeAttribution()
        tied.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_000)
        tied.recordHIDReport(usage: 0x04, isDown: true, side: .builtIn, now: 1_000)
        #expect(tied.decide(kind: .keyDown, keyCode: 4, now: 1_050) == .external)
    }

    /// 无任何证据(如锁定瞬间 tap 先于 HID 收到事件)默认判内置拦截:
    /// 放行即锁定失效,误拦在下一次按键自愈。
    @Test func noEvidenceDefaultsToBuiltIn() {
        let a = makeAttribution()
        #expect(a.decide(kind: .keyDown, keyCode: 4, now: 1_000) == .builtIn)
        #expect(a.decide(kind: .flagsChanged, keyCode: 0, now: 1_000) == .builtIn)
        #expect(a.decide(kind: .systemDefined, keyCode: 0, now: 1_000) == .builtIn)
    }

    /// 抬起无记账时按常规证据归因(外接近窗即放行),并销账不留残留。
    @Test func keyUpWithoutVerdictUsesEvidenceAndClears() {
        let a = makeAttribution()
        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_000)
        // 该键记账已被 reset 清空,但外接窗内活动仍在 → 抬起放行。
        a.reset()
        a.recordHIDReport(usage: 0x2C, isDown: true, side: .external, now: 5_000)
        #expect(a.decide(kind: .keyUp, keyCode: 4, now: 5_050) == .external)
    }

    /// reset 清空全部证据与记账:跨轮的按下态与陈旧结论不可作为下一轮证据。
    @Test func resetClearsVerdictsAndDownSets() {
        let a = makeAttribution()
        a.recordHIDReport(usage: 0x04, isDown: true, side: .external, now: 1_000)
        a.decide(kind: .keyDown, keyCode: 4, now: 1_050)
        a.reset()
        // 记账没了:同样的事件重新走证据链,当前无任何证据 → 内置。
        #expect(a.decide(kind: .keyDown, keyCode: 4, isAutorepeat: true, now: 1_100) == .builtIn)
        // 按下集合也没了:新按下走时间窗,同样判内置。
        #expect(a.decide(kind: .keyDown, keyCode: 11, now: 1_150) == .builtIn)
    }
}
