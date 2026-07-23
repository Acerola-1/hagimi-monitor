import AppKit
import Foundation

/// header 小猫客串彩蛋（致敬 RunCat）的帧图提供者。
///
/// 结构对齐 `MenuBarComputeRingIcon`：一个 `enum`，暴露读取当前帧 `NSImage` 的静态方法。
/// 但与负载环不同——猫只有 5 帧、且不按负载分桶着色（模板图交给 AppKit 自动着色），
/// 故无需 `NSCache` 分桶缓存，直接在类型加载时把 5 帧解码成 `NSImage` 常量数组即可。
enum MenuBarCatIcon {
    /// 素材来自 RunCat（Apache 2.0，Kyome22 / Takuto Nakamura），拷贝进本项目 Assets。
    static let frameCount = 5

    /// 菜单栏显示尺寸：素材原图 56×36（视作 2x），故显示点尺寸取 28×18，
    /// 高度与负载环 18pt 一致，保持菜单栏图标视觉高度统一。
    static let displaySize = NSSize(width: 28, height: 18)

    /// 5 帧模板图常量数组。每帧 `isTemplate = true`，交给 AppKit 按当前外观
    /// 自动着色（浅色黑、深色白），无需像负载环那样手动判定明暗。
    static let frames: [NSImage] = (0 ..< frameCount).map { index in
        guard let source = NSImage(named: "cat-frame-\(index)") else {
            // 素材缺失时兜底：返回一张透明占位图，避免强解包崩溃。
            let placeholder = NSImage(size: displaySize)
            placeholder.isTemplate = true
            return placeholder
        }
        // 固定显示尺寸的模板副本。直接改 source.size 会影响资源缓存的共享实例，故新建一张。
        let image = NSImage(size: displaySize, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 返回指定帧的图（越界自动取模，避免调用方越界崩溃）。
    static func image(frame: Int) -> NSImage {
        let safeIndex = ((frame % frameCount) + frameCount) % frameCount
        return frames[safeIndex]
    }
}
