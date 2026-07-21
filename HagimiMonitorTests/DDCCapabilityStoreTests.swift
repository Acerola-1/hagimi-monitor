import Testing
@testable import HagimiMonitor
import CoreGraphics

/// 能力模型取代旧的失败计数禁用逻辑。核心不变式:
/// - 从未探测过的控制默认 `.unknown`(乐观:仍显示、仍可写,绝不置灰)。
/// - 只有显示器明确回复"不支持"(结果码 0x01)才映射为 `.unsupported`——唯一置灰的负例。
/// - 瞬时丢包(无有效应答)只落到 `.unknown`,**永不**翻转为 `.unsupported`。
struct DDCCapabilityStoreTests {
    private let key = ControlKey(displayID: 1, control: .brightness)

    @Test func defaultsToUnknown() {
        let store = DDCCapabilityStore()
        #expect(store.capability(key) == .unknown)
    }

    @Test func supportedIsPersisted() {
        let store = DDCCapabilityStore()
        store.set(.supported, for: key)
        #expect(store.capability(key) == .supported)
    }

    @Test func unsupportedIsPersisted() {
        let store = DDCCapabilityStore()
        store.set(.unsupported, for: key)
        #expect(store.capability(key) == .unsupported)
    }

    /// 能力可被重新探测结果覆盖(重配置/唤醒/开面板会重探)。unknown → supported 应生效。
    @Test func capabilityCanBeRefreshed() {
        let store = DDCCapabilityStore()
        store.set(.unknown, for: key)
        store.set(.supported, for: key)
        #expect(store.capability(key) == .supported)
    }

    /// reset 只清除指定显示器的能力,其它显示器不受影响(重配置移除某屏时用)。
    @Test func resetClearsOnlyTargetDisplay() {
        let store = DDCCapabilityStore()
        let other = ControlKey(displayID: 2, control: .brightness)
        store.set(.unsupported, for: key)
        store.set(.unsupported, for: other)
        store.reset(displayID: 1)
        // 被 reset 的显示器回到乐观默认 unknown;另一台保留其能力。
        #expect(store.capability(key) == .unknown)
        #expect(store.capability(other) == .unsupported)
    }

    /// 同一显示器不同控制互相独立:亮度不支持不应影响音量的能力判定。
    @Test func controlsAreIndependentPerDisplay() {
        let store = DDCCapabilityStore()
        let volume = ControlKey(displayID: 1, control: .volume)
        store.set(.unsupported, for: key)
        #expect(store.capability(volume) == .unknown)
    }
}
