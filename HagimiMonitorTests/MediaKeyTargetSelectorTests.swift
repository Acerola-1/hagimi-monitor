import Testing
@testable import HagimiMonitorDirect
import CoreGraphics
import Foundation

/// 媒体键目标选择测试(9.1/9.3/9.4)。
/// 验收:双屏音频 A/鼠标 B 时选 A;未知映射不猜测;系统可控输出交还系统;
/// 亮度保留鼠标/单屏策略;静音恢复优先级(进程内→持久化→兜底)。
struct MediaKeyTargetSelectorTests {
    private let identityA = DisplayIdentity(vendorID: 0x1111, productID: 0x2222, serialNumber: "A", edidUUID: nil, isBuiltIn: false)
    private let identityB = DisplayIdentity(vendorID: 0x3333, productID: 0x4444, serialNumber: "B", edidUUID: nil, isBuiltIn: false)

    // MARK: - 9.1 音量目标

    /// 音频输出在屏 A(不可控),鼠标在屏 B:音量键调屏 A。
    @Test func volumeTargetsAudioDisplayNotMouse() {
        let audio = AudioOutputDescription(deviceUID: "uid-A", name: "显示器喇叭", transportType: "HDMI", isControllable: false)
        let displays: [(DisplayIdentity, CGDirectDisplayID, Bool)] = [
            (identityA, 1, true),
            (identityB, 2, true),
        ]
        let target = MediaKeyTargetSelector.volumeTarget(
            audioOutput: audio,
            boundIdentity: nil,
            boundDisplayID: nil,
            displays: displays.map { ($0.0, $0.1, $0.2) }
        )
        #expect(target == nil, "无唯一映射且无绑定:不猜测,交还系统")
    }

    /// 显式绑定:音频 UID→身份 A,选择屏 A。
    @Test func volumeTargetUsesExplicitBinding() {
        let audio = AudioOutputDescription(deviceUID: "uid-A", name: "屏A喇叭", transportType: "HDMI", isControllable: false)
        let displays: [(DisplayIdentity, CGDirectDisplayID, Bool)] = [
            (identityA, 1, true),
            (identityB, 2, true),
        ]
        let target = MediaKeyTargetSelector.volumeTarget(
            audioOutput: audio,
            boundIdentity: identityA,
            boundDisplayID: 1,
            displays: displays.map { ($0.0, $0.1, $0.2) }
        )
        #expect(target == 1, "显式绑定应选绑定屏 A")
    }

    /// 唯一支持音量的外接屏:兜底选中。
    @Test func volumeTargetFallsBackToSingleVolumeDisplay() {
        let audio = AudioOutputDescription(deviceUID: "uid-X", name: "未知", transportType: "USB", isControllable: false)
        let displays: [(DisplayIdentity, CGDirectDisplayID, Bool)] = [
            (identityA, 1, true),
            (identityB, 2, false), // B 不支持音量
        ]
        let target = MediaKeyTargetSelector.volumeTarget(
            audioOutput: audio,
            boundIdentity: nil,
            boundDisplayID: nil,
            displays: displays.map { ($0.0, $0.1, $0.2) }
        )
        #expect(target == 1, "唯一音量屏应被选中")
    }

    /// 系统可控输出(AirPods/内建扬声器)交还系统。
    @Test func controllableOutputHandedBackToSystem() {
        let audio = AudioOutputDescription(deviceUID: "airpods", name: "AirPods", transportType: "Bluetooth", isControllable: true)
        let displays: [(DisplayIdentity, CGDirectDisplayID, Bool)] = [(identityA, 1, true)]
        let target = MediaKeyTargetSelector.volumeTarget(
            audioOutput: audio,
            boundIdentity: nil,
            boundDisplayID: nil,
            displays: displays.map { ($0.0, $0.1, $0.2) }
        )
        #expect(target == nil, "系统可控输出交还系统")
    }

    // MARK: - 9.3 亮度策略保留

    @Test func brightnessUsesMouseExternalDisplay() {
        let displays: [(CGDirectDisplayID, Bool, Bool)] = [
            (0, true, false), // 内建屏
            (1, false, true), // 外接可控 A
            (2, false, true), // 外接可控 B
        ]
        let target = MediaKeyTargetSelector.brightnessTarget(
            mouseDisplayID: 2,
            displays: displays
        )
        #expect(target == 2, "鼠标所在外接屏优先")
    }

    @Test func brightnessOnBuiltInDisplayHandsBackToSystem() {
        let displays: [(CGDirectDisplayID, Bool, Bool)] = [
            (0, true, false),
            (1, false, true), // 唯一外接可控
        ]
        let target = MediaKeyTargetSelector.brightnessTarget(
            mouseDisplayID: 0, // 鼠标在内建屏
            displays: displays
        )
        #expect(target == nil, "鼠标在内建屏时应交还系统")
    }

    @Test func brightnessUnknownWithSingleExternalFallsBackToExternal() {
        let displays: [(CGDirectDisplayID, Bool, Bool)] = [
            (0, true, false),
            (1, false, true), // 唯一外接可控
        ]
        let target = MediaKeyTargetSelector.brightnessTarget(
            mouseDisplayID: nil,
            displays: displays
        )
        #expect(target == 1, "无法取得鼠标所在屏幕时保留单外接屏兜底")
    }

    @Test func brightnessUnknownWithMultipleExternalsHandsBack() {
        let displays: [(CGDirectDisplayID, Bool, Bool)] = [
            (0, true, false),
            (1, false, true),
            (2, false, true),
        ]
        let target = MediaKeyTargetSelector.brightnessTarget(
            mouseDisplayID: 0, // 鼠标在内建屏
            displays: displays
        )
        #expect(target == nil, "多台无法确定交还系统")
    }

    // MARK: - 9.3 shouldAccept

    @Test func shouldAcceptRequiresTargetAndBaseline() {
        #expect(MediaKeyTargetSelector.shouldAccept(key: .volume, target: nil, hasBaseline: true) == false)
        #expect(MediaKeyTargetSelector.shouldAccept(key: .volume, target: 1, hasBaseline: false) == false)
        #expect(MediaKeyTargetSelector.shouldAccept(key: .volume, target: 1, hasBaseline: true) == true)
        // 静音不需要基线。
        #expect(MediaKeyTargetSelector.shouldAccept(key: .mute, target: 1, hasBaseline: false) == true)
    }

    // MARK: - 9.4 静音恢复优先级

    /// 历史 70、实读 25:静音时捕获 25,解除恢复 25(不恢复陈旧 70)。
    @Test func unmuteRestoresCapturedCurrentOverStalePersisted() {
        let captured = VolumeRestoreResolver.captureBeforeMute(current: 25, recentInProcess: 70)
        let restored = VolumeRestoreResolver.resolve(recentInProcess: captured, persisted: 70)
        #expect(restored == 25, "静音前实读 25 应覆盖陈旧持久化 70")
    }

    /// 重启后:无进程内最近,有持久化 70 → 恢复 70。
    @Test func unmuteAfterRestartRestoresPersisted() {
        let restored = VolumeRestoreResolver.resolve(recentInProcess: nil, persisted: 70)
        #expect(restored == 70)
    }

    /// 无历史无持久化 → 兜底 1/16 满量程。
    @Test func unmuteWithNoHistoryUsesFallback() {
        let restored = VolumeRestoreResolver.resolve(recentInProcess: nil, persisted: nil)
        #expect(restored == VolumeRestoreResolver.fallbackValue)
    }

    /// 静音 repeat:进程内最近保留,不因重复静音丢失恢复值。
    @Test func muteRepeatKeepsRecentValue() {
        var recent: Double? = 60
        recent = VolumeRestoreResolver.captureBeforeMute(current: 0, recentInProcess: recent)
        recent = VolumeRestoreResolver.captureBeforeMute(current: 0, recentInProcess: recent)
        #expect(recent == 60, "重复静音不覆盖非零恢复值")
    }

    /// 细步进:恢复值尊重捕获值(不被步进量化)。
    @Test func fineStepRestorePreservesCapturedValue() {
        let captured = VolumeRestoreResolver.captureBeforeMute(current: 37.5, recentInProcess: nil)
        #expect(VolumeRestoreResolver.resolve(recentInProcess: captured, persisted: nil) == 37.5)
    }
}
