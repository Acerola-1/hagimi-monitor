import AppKit
import Foundation

/// 读取内建显示器的物理刷新率。全部走公开 CG/NSScreen API，双渠道（含沙盒）可用
/// ——与 DisplaySection.collectDisplays 同款数据源，后者已在沙盒版显示器卡片中渲染。
enum DisplayTelemetryReader {
    /// 读取内建显示器当前模式物理刷新率（Hz）。
    static func readBuiltInRefreshRate() -> Double? {
        for screen in NSScreen.screens {
            if let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
               CGDisplayIsBuiltin(id) != 0 {
                if let mode = CGDisplayCopyDisplayMode(id), mode.refreshRate > 0 {
                    return mode.refreshRate
                }
            }
        }
        return nil
    }
}
