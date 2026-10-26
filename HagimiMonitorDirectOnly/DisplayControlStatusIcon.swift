#if DISPLAY_CONTROL
import AppKit

/// 沿用显示器模块的系统符号：屏幕下方的滑杆表达调节，模板图交给菜单栏适配明暗外观。
@MainActor enum DisplayControlStatusIcon {
    static func makeImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "slider.horizontal.below.rectangle",
                            accessibilityDescription: String(localized: "display.controls.title"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
#endif
