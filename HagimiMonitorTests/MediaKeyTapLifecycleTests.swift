import Testing
@testable import HagimiMonitorDirect

/// 媒体键 tap 生命周期的不变量:配置未变绝不重启 head-insert tap。
/// 回归背景:该 tap 曾挂在每 5s 一次的显示刷新收尾上无条件重建,重建窗口内
/// 可能扰动系统事件/焦点状态;鼠标事件是否被直接吞掉不能仅由该事件掩码证明。
struct MediaKeyTapLifecycleTests {
    private let volumeKeys: Set<MediaKey> = [.volumeUp, .volumeDown]

    @Test func keepsTapWhenDesiredKeysUnchanged() {
        #expect(
            MediaKeyTapLifecycle.action(desired: volumeKeys, active: volumeKeys) == .keep
        )
    }

    @Test func repeatedIdenticalRefreshNeverRestartsTap() {
        // 模拟 5s 轮询反复下发同一集合:除第一次外都应保持不动。
        var active: Set<MediaKey>?
        var actions: [MediaKeyTapLifecycle.Action] = []
        for _ in 0 ..< 12 {
            let action = MediaKeyTapLifecycle.action(desired: volumeKeys, active: active)
            actions.append(action)
            if case .start(let keys) = action { active = keys }
        }
        #expect(actions.first == .start(volumeKeys))
        #expect(actions.dropFirst().allSatisfy { $0 == .keep })
    }

    @Test func startsWhenKeysChange() {
        #expect(
            MediaKeyTapLifecycle.action(desired: [.brightnessUp], active: volumeKeys)
                == .start([.brightnessUp])
        )
    }

    @Test func stopsWhenNothingWanted() {
        #expect(MediaKeyTapLifecycle.action(desired: [], active: volumeKeys) == .stop)
    }

    @Test func keepsInactiveStateWhenNoTapIsInstalled() {
        #expect(MediaKeyTapLifecycle.action(desired: [], active: nil) == .keep)
    }

    @Test func startsWhenNoTapIsInstalled() {
        #expect(
            MediaKeyTapLifecycle.action(desired: volumeKeys, active: nil) == .start(volumeKeys)
        )
    }
}
