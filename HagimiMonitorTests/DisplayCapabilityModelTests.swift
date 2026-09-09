import Testing
@testable import HagimiMonitorDirect
import Foundation

/// 能力证据与后端选择测试(6.1/6.5/6.6)。
/// 验收:主码 timeout+备用 unsupported 不导致整体 unsupported;单次丢包保留有效
/// 支持证据;亮度 Gamma 时音量/对比度仍走 DDC;设置按设备隔离并校验范围。
struct DisplayCapabilityModelTests {
    private func token(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    // MARK: - 6.1 逐 VCP 证据不错误合并

    @Test func mainCodeTimeoutBackupUnsupportedKeepsMainEvidence() {
        let store = DisplayCapabilityEvidenceStore()
        let t = token(1)
        // 主码 0x10 曾有有效应答(supported),备用 0x13 明确不支持。
        store.setEvidence(.supported, for: t, control: .brightness, vcp: 0x10)
        store.setEvidence(.unsupported, for: t, control: .brightness, vcp: 0x13)
        // 聚合:有 supported → supported,不被备用码不支持覆盖。
        #expect(store.aggregatedCapability(for: t, control: .brightness, candidateVCPs: [0x10, 0x13]) == .supported)
    }

    @Test func singlePacketLossKeepsValidSupportEvidence() {
        let store = DisplayCapabilityEvidenceStore()
        let t = token(2)
        store.setEvidence(.supported, for: t, control: .volume, vcp: 0x62)
        // 一次通信失败只更新未知,不翻转既有 supported。
        store.setEvidence(.unknown, for: t, control: .volume, vcp: 0x62)
        #expect(store.aggregatedCapability(for: t, control: .volume, candidateVCPs: [0x62]) == .supported)
    }

    @Test func allCandidatesUnsupportedYieldsUnsupported() {
        let store = DisplayCapabilityEvidenceStore()
        let t = token(3)
        store.setEvidence(.unsupported, for: t, control: .brightness, vcp: 0x10)
        store.setEvidence(.unsupported, for: t, control: .brightness, vcp: 0x13)
        #expect(store.aggregatedCapability(for: t, control: .brightness, candidateVCPs: [0x10, 0x13]) == .unsupported)
    }

    @Test func unknownCandidateKeepsUnknown() {
        let store = DisplayCapabilityEvidenceStore()
        let t = token(4)
        store.setEvidence(.unsupported, for: t, control: .contrast, vcp: 0x12)
        // 一个候选无应答(unknown),另一个不支持 → 聚合 unknown(不乐观默认可用)。
        #expect(store.aggregatedCapability(for: t, control: .contrast, candidateVCPs: [0x12, 0x13]) == .unknown)
    }

    // MARK: - 6.5 每属性后端

    @Test func brightnessGammaDoesNotDisableVolumeAndContrast() {
        // 亮度 gamma 模式下,音量/对比度仍走 DDC。
        #expect(BackendSelection.backend(for: .brightness, dimmingMode: .gamma, capability: .unsupported, isBuiltIn: false) == .gamma)
        #expect(BackendSelection.backend(for: .volume, dimmingMode: .gamma, capability: .supported, isBuiltIn: false) == .ddc)
        #expect(BackendSelection.backend(for: .contrast, dimmingMode: .gamma, capability: .supported, isBuiltIn: false) == .ddc)
    }

    @Test func builtInUsesAppleNativeForBrightness() {
        #expect(BackendSelection.backend(for: .brightness, dimmingMode: .hardware, capability: .unknown, isBuiltIn: true) == .appleNative)
    }

    @Test func externalDDCOnlyWhenSupported() {
        #expect(BackendSelection.backend(for: .brightness, dimmingMode: .hardware, capability: .supported, isBuiltIn: false) == .ddc)
        #expect(BackendSelection.backend(for: .brightness, dimmingMode: .hardware, capability: .unsupported, isBuiltIn: false) == .unavailable)
        #expect(BackendSelection.backend(for: .volume, dimmingMode: .hardware, capability: .unsupported, isBuiltIn: false) == .unavailable)
    }

    // MARK: - 6.6 兼容配置隔离与校验

    @Test func rangeOverrideValidation() {
        #expect(DisplayCompatibilityConfig.validate(rangeOverride: 1))
        #expect(DisplayCompatibilityConfig.validate(rangeOverride: 255))
        #expect(DisplayCompatibilityConfig.validate(rangeOverride: 65_535))
        #expect(!DisplayCompatibilityConfig.validate(rangeOverride: 0), "零 max 覆盖被拒绝")
        #expect(DisplayCompatibilityConfig.validate(rangeOverride: nil))
    }

    @Test func configIsolatedPerDevice() {
        var a = DisplayCompatibilityConfig()
        a.brightnessMode = .software
        a.readPolicy = .off
        var b = DisplayCompatibilityConfig()
        b.brightnessMode = .auto
        #expect(a != b, "设置按设备隔离,修改 A 不影响 B")
        #expect(b.brightnessMode == .auto)
        #expect(b.readPolicy == .auto)
    }
}
