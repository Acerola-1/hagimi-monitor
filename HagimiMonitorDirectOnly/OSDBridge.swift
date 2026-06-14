import CoreGraphics
import Foundation
import OSLog

private let osdLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "OSD")

/// OSD 图标常量。取值对齐 macOS OSD.framework 与 MonitorControl `OSDUtils.OSDImage`。
enum OSDImage: Int64 {
    case brightness = 1
    case speaker = 3
    case speakerMuted = 4
}

/// 包裹 macOS 私有 `OSD.framework` 的 OSDManager,显示原生亮度/音量提示框。
///
/// 仅在 Direct build 下编译;失败(私有 API 不可用、framework 缺失)时静默
/// 打日志,不阻塞主功能。参考 MonitorControl `OSDUtils.showOsd`。
final class OSDBridge {
    /// 系统原生 OSD 的进度格总数。对齐 MonitorControl `chicletCount = 16`
    /// 与 macOS 内建亮度/音量 OSD 的视觉;使用 100 会得到过细的进度条。
    private static let chicletCount = 16

    private static let osdManagerClass: AnyClass? = NSClassFromString("OSDManager")

    /// 显示 OSD 提示框。
    /// - Parameters:
    ///   - image: 图标种类(亮度/音量/静音)
    ///   - displayID: OSD 应跟随的显示器
    ///   - percent: 0...100,会换算为已填充的进度格
    func show(
        _ image: OSDImage,
        displayID: CGDirectDisplayID,
        percent: Double
    ) {
        guard let cls = Self.osdManagerClass as? NSObject.Type,
              let manager = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue()
        else {
            osdLog.warning("OSDManager class unavailable")
            return
        }

        let total = Self.chicletCount
        let clamped = min(100, max(0, percent))
        let filled = Int((clamped / 100.0 * Double(total)).rounded())

        if let typedManager = manager as? OSDManager {
            typedManager.showImage(
                image.rawValue,
                onDisplayID: displayID,
                priority: 0x1F4,
                msecUntilFade: 1000,
                filledChiclets: UInt32(filled),
                totalChiclets: UInt32(total),
                locked: false
            )
        }
    }
}
