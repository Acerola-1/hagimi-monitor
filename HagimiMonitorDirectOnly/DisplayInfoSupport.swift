import CoreGraphics
import Foundation

/// B4 显示器信息区的 Direct 专属钩子。
/// 共享视图(DisplayInfoSection)在 `#if DISPLAY_CONTROL` 下调用这里;
/// 亮度走 DisplayServices 私有接口,DDC 判定复用 DisplayClassifier——
/// 两者都不进 App Store target。

/// 内建屏当前亮度(0-100)。读取失败/非内建屏返 nil。
func displayInfoBrightnessPercent(_ displayID: CGDirectDisplayID) -> Int? {
    var brightness: Float = -1
    guard DisplayServicesGetBrightness(displayID, &brightness) == 0, brightness >= 0 else {
        return nil
    }
    return Int((Double(brightness) * 100).rounded())
}

/// 该显示器是否可走 DDC 控制(第三方外接显示器)。
/// Apple 原生外接(Studio Display 等)走原生亮度通道而非 DDC,此处只认 externalDDC 类。
func displayInfoSupportsDDC(_ displayID: CGDirectDisplayID) -> Bool {
    DisplayClassifier().classify(displayID: displayID) == .externalDDC
}
