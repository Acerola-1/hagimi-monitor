import AppKit
import Foundation

enum MenuBarComputeRingIcon {
    /// 图标画布 21pt:原 18pt 图标区域居中,四周各留 1.5pt,让告警红点落在环外
    /// 而不是压在环线上;环与轨道的几何不变,只多了这圈留白。
    private static let iconSize: CGFloat = 21

    /// 内部锁，确保并发请求同一个 bucket 时只绘制一次并安全缓存
    private static let lock = NSLock()
    private static let cache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        // 颜色由同一负载桶派生，不再把原始等级另列为缓存维度。
        // 保留最近负载区间及两种外观，避免升降过程中反复淘汰、重绘。
        cache.countLimit = 300
        return cache
    }()

    private static func loadBucket(for load: Double) -> Int {
        Int(min(100.0, max(0.0, load)).rounded())
    }

    private static func cacheKey(loadBucket: Int, darkMode: Bool, showsAlert: Bool, showsHUDBadge: Bool) -> NSNumber {
        // 告警优先于 HUD，两者同时开启与仅有告警是同一图像。
        let badge = showsAlert ? 1 : (showsHUDBadge ? 2 : 0)
        return NSNumber(value: (loadBucket * 2 + (darkMode ? 1 : 0)) * 3 + badge)
    }

    static func image(load: Double, darkMode: Bool, showsAlert: Bool = false, showsHUDBadge: Bool = false) -> NSImage {
        let loadBucket = loadBucket(for: load)
        let canonicalLoad = Double(loadBucket)
        let key = cacheKey(loadBucket: loadBucket, darkMode: darkMode, showsAlert: showsAlert, showsHUDBadge: showsHUDBadge)
        lock.lock()
        if let cached = cache.object(forKey: key) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = NSImage(size: NSSize(width: Self.iconSize, height: Self.iconSize), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.clear.setFill()
            rect.fill()

            let isDark: Bool
            let appearance = NSAppearance.currentDrawing()
            if let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantDark, .vibrantLight]) {
                isDark = match == .darkAqua || match == .vibrantDark
            } else {
                isDark = darkMode
            }

            let style = MenuBarComputeRingImageStyle(load: canonicalLoad, darkMode: isDark)
            drawRing(style: style, center: NSPoint(x: rect.midX, y: rect.midY))
            if showsAlert {
                MenuBarAlertBadge.draw(in: rect, darkMode: isDark)
            } else if showsHUDBadge {
                MenuBarHUDBadge.draw(in: rect, darkMode: isDark)
            }
            return true
        }
        image.isTemplate = false

        lock.lock()
        if let existing = cache.object(forKey: key) {
            lock.unlock()
            return existing
        }
        cache.setObject(image, forKey: key)
        lock.unlock()
        return image
    }

    #if DEBUG
    static func clearCacheForTesting() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }
    #endif

    private static func drawRing(style: MenuBarComputeRingImageStyle, center: NSPoint) {
        let ringRect = NSRect(
            x: center.x - style.ringSize / 2,
            y: center.y - style.ringSize / 2,
            width: style.ringSize,
            height: style.ringSize
        )

        style.trackColor.setStroke()
        // 底环与弧线、核心同圆心:画布扩容后不能再按固定内衬定位,否则会与弧线错开。
        let trackRect = NSRect(
            x: center.x - style.trackSize / 2,
            y: center.y - style.trackSize / 2,
            width: style.trackSize,
            height: style.trackSize
        )
        let track = NSBezierPath(ovalIn: trackRect)
        track.lineWidth = style.trackWidth
        track.stroke()

        drawArc(
            in: ringRect,
            progress: style.progress,
            lineWidth: style.lineWidth,
            color: style.tint
        )

        style.coreBackplateColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - style.coreBackplateSize / 2,
                y: center.y - style.coreBackplateSize / 2,
                width: style.coreBackplateSize,
                height: style.coreBackplateSize
            )
        ).fill()

        style.coreColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - style.coreSize / 2,
                y: center.y - style.coreSize / 2,
                width: style.coreSize,
                height: style.coreSize
            )
        ).fill()
    }

    private static func drawArc(in rect: NSRect, progress: Double, lineWidth: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: 90,
            endAngle: 90 - CGFloat(progress * 360),
            clockwise: true
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

private struct MenuBarComputeRingImageStyle {
    let load: Double
    let darkMode: Bool

    private var normalizedLoad: Double {
        min(1, max(0, load / 100))
    }

    var progress: Double {
        min(0.98, max(0.08, 0.12 + normalizedLoad * 0.86))
    }

    var tint: NSColor {
        let alpha = 0.72 + normalizedLoad * 0.24
        return ink.withAlphaComponent(alpha)
    }

    var trackColor: NSColor {
        ink.withAlphaComponent(darkMode ? 0.34 : 0.28)
    }

    var coreColor: NSColor {
        MenuBarComputeLoadLevel.ringColor(for: load, darkMode: darkMode)
            .withAlphaComponent((darkMode ? 0.76 : 0.88) + normalizedLoad * 0.10)
    }

    var lineWidth: CGFloat {
        CGFloat(1.9 + normalizedLoad * 0.55)
    }

    var ringSize: CGFloat {
        13.0
    }

    var coreSize: CGFloat {
        CGFloat(3.0 + normalizedLoad * 1.9)
    }

    var coreBackplateSize: CGFloat {
        coreSize + 1.8
    }

    var trackSize: CGFloat {
        13.2
    }

    var trackWidth: CGFloat {
        1.35
    }

    var coreBackplateColor: NSColor {
        darkMode
            ? NSColor.black.withAlphaComponent(0.48)
            : NSColor.white.withAlphaComponent(0.76)
    }

    private var ink: NSColor {
        darkMode ? .white : .black
    }
}

enum MenuBarComputeLoadLevel: Sendable {
    case idle
    case working
    case busy
    case stressed
    private static let ringLevels: [Self] = [.idle, .working, .busy, .stressed]

    /// 渐变仅影响负载环；模块和告警仍使用真实采样等级的离散语义。
    static func ringColor(for load: Double, darkMode: Bool) -> NSColor {
        let halfWidth = MonitorConstants.menuBarLoadColorBlendHalfWidth
        for (index, boundary) in MonitorConstants.menuBarLoadLevelBoundaries.enumerated() {
            if load < boundary - halfWidth { return ringLevels[index].coreColor(darkMode: darkMode) }
            if load <= boundary + halfWidth {
                let fraction = min(1, max(0, (load - boundary + halfWidth) / (halfWidth * 2)))
                let eased = fraction * fraction * (3 - 2 * fraction)
                let from = ringLevels[index].coreColor(darkMode: darkMode)
                return from.blended(withFraction: eased, of: ringLevels[index + 1].coreColor(darkMode: darkMode)) ?? from
            }
        }
        return Self.stressed.coreColor(darkMode: darkMode)
    }

    func coreColor(darkMode: Bool) -> NSColor {
        switch self {
        case .idle:
            return darkMode
                ? NSColor(red: 0.34, green: 0.86, blue: 0.66, alpha: 1)
                : NSColor(red: 0.08, green: 0.50, blue: 0.34, alpha: 1)
        case .working:
            return darkMode
                ? NSColor(red: 0.32, green: 0.88, blue: 0.72, alpha: 1)
                : NSColor(red: 0.00, green: 0.55, blue: 0.42, alpha: 1)
        case .busy:
            return darkMode
                ? NSColor(red: 1.00, green: 0.74, blue: 0.32, alpha: 1)
                : NSColor(red: 0.80, green: 0.44, blue: 0.06, alpha: 1)
        case .stressed:
            return darkMode
                ? NSColor(red: 1.00, green: 0.38, blue: 0.34, alpha: 1)
                : NSColor(red: 0.78, green: 0.12, blue: 0.10, alpha: 1)
        }
    }
}
