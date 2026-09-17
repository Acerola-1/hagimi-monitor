import AppKit
import Foundation
import ImageIO

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
nonisolated enum ProcessIconCache {
    /// 展示尺寸(pt)。面板内所有进程图标均以 16pt 显示。
    private static let side: CGFloat = 16
    /// 位图倍率:@2x 足够在 Retina 上清晰,又把单张位图控制在 ~4KB。
    private static let scale: CGFloat = 2

    /// NSCache 自身在 Foundation 中具备全线程安全保证（内部有锁保护其并发存取）。
    /// 安全不变式：委托 NSCache 自身的线程安全机制，向外部提供线程安全读写。
    nonisolated private final class ThreadSafeIconCache: @unchecked Sendable {
        private let cache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 64
            return cache
        }()

        func object(forKey key: NSString) -> NSImage? {
            cache.object(forKey: key)
        }

        func setObject(_ obj: NSImage, forKey key: NSString) {
            cache.setObject(obj, forKey: key)
        }
    }

    private static let cache = ThreadSafeIconCache()

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

    /// 把 NSImage 重绘为 sidePixels 见方并编码为 PNG Data。
    static func fullSizePNG(forImage source: NSImage, sidePixels: Int) -> Data? {
        var proposedRect = NSRect(x: 0, y: 0, width: source.size.width, height: source.size.height)

        guard let cgSource = source.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        ), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: sidePixels,
                  height: sidePixels,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgSource, in: CGRect(x: 0, y: 0, width: sidePixels, height: sidePixels))
        guard let scaled = context.makeImage() else { return nil }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// 取进程的全分辨率 bundle 图标,重绘为 sidePixels 见方并编码为 PNG。
    /// 一次性调用、不缓存:供统计存储等需要持久化高清位图的消费方使用--
    /// `icon(forPID:path:)` 返回的是 32px 降采样产物,放大到 128px 会永久糊化。
    /// 走 CoreGraphics + ImageIO,可在后台线程安全调用;进程已退出等取不到
    /// 源图时返回 nil,调用方下轮采样再试。
    static func fullSizePNG(forPID pid: pid_t, sidePixels: Int) -> Data? {
        guard let source = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        return fullSizePNG(forImage: source, sidePixels: sidePixels)
    }

    /// 取指定 Bundle Identifier 对应应用的高清图标并重绘为 PNG。
    static func fullSizePNG(forBundleIdentifier bundleID: String, sidePixels: Int) -> Data? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon {
            return fullSizePNG(forImage: icon, sidePixels: sidePixels)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return fullSizePNG(forImage: icon, sidePixels: sidePixels)
        }
        return nil
    }
}
