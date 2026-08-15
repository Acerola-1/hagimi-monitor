import AppKit
import Foundation

/// 进程图标降采样缓存。
///
/// `NSWorkspace.shared.icon(forFile:)` 与 `NSRunningApplication.icon` 返回的 App 图标
/// 通常带有 512/1024px 的大 representation:只缩小逻辑尺寸而不重绘,底层大位图仍随
/// `NSImage` 常驻。面板展开时 4 个进程列表最多同时持有 20 张这类「大图底」图标,
/// 且每 5 秒采样重建全新实例,旧图要等下一轮 SwiftUI diff 才释放,造成内存高水位
/// 与分配抖动。
///
/// 本缓存把源图一次性重绘为固定 16pt(@2x = 32px)的小位图,单张约 32×32×4 ≈ 4KB,
/// 并按可执行文件路径缓存,命中后直接复用——既压掉常驻内存,也免去每 5 秒重复光栅化。
///
/// 线程安全:使用 `CGImage` + `CGContext` 完成缩放(不触碰 `NSGraphicsContext.current`
/// 或 `lockFocus`),可在后台采样队列安全调用,与既有 `enrich*` 的后台线程约定一致。
enum ProcessIconCache {
    /// 展示尺寸(pt)。面板内所有进程图标均以 16pt 显示。
    private static let side: CGFloat = 16
    /// 位图倍率:@2x 足够在 Retina 上清晰,又把单张位图控制在 ~4KB。
    private static let scale: CGFloat = 2

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // 面板 4 个列表各最多 5 行,去重后同时可见的不同进程远不足 64;留足余量覆盖
        // 采样间进程增减,又不会让历史项无限常驻。
        cache.countLimit = 64
        return cache
    }()

    /// 取一张已降采样的小图标。可在任意线程调用;取不到图标时返回 nil,视图侧回退到占位图标。
    /// - Parameters:
    ///   - pid: 进程(宿主 App)pid,用于 `NSRunningApplication` 优先取 bundle 图标。
    ///   - path: 可执行文件路径,作为缓存键与 `NSWorkspace` 取图回退。
    static func icon(forPID pid: pid_t, path: String) -> NSImage? {
        // 缓存键优先用路径(同一 App 多实例共享一张);路径为空回退到 pid。
        let key = (path.isEmpty ? "pid:\(pid)" : path) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let source: NSImage?
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            source = icon
        } else if !path.isEmpty {
            source = NSWorkspace.shared.icon(forFile: path)
        } else {
            source = nil
        }

        guard let source else { return nil }

        // 降采样失败时回退到源图(不缓存),保证功能不受影响。
        guard let downscaled = downscaled(source) else {
            return source
        }

        cache.setObject(downscaled, forKey: key)
        return downscaled
    }

    /// 把源图重绘到固定 16pt(@2x)小位图。走 CoreGraphics,线程安全。
    private static func downscaled(_ source: NSImage) -> NSImage? {
        let pixels = Int(side * scale)
        var proposedRect = NSRect(x: 0, y: 0, width: side, height: side)

        guard let cgSource = source.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        ) else {
            return nil
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixels,
                  height: pixels,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgSource, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

        guard let scaled = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: scaled, size: NSSize(width: side, height: side))
    }
}
