import AppKit
import Foundation

enum MenuBarComputeRingIcon {
    /// 图标画布 21pt:原 18pt 图标区域居中,四周各留 1.5pt,让告警红点落在环外
    /// 而不是压在环线上;环与轨道的几何不变,只多了这圈留白。
    private static let iconSize: CGFloat = 21

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // 桶组合上限 101(负载)×2(明暗)×4(等级)×2(告警红点)=1616,但菜单栏实际只在
        // 当前负载附近的少数桶间移动。840 会让几乎所有历史桶常驻,且每张被绘制过的缓存图
        // 会各持有一个 AppKit 位图 rep,累积成内存高水位。displayedComputeLoad 由 30fps
        // 平滑定时器驱动,负载爬升/回落时会连续扫过一整段整数桶,limit 太小会导致近期刚
        // 淘汰的桶被立刻重新访问、频繁重绘。300 约等于「整段负载范围 × 明暗两态」
        // (101×2=202,红点开或关各算一套)再留一些余量给相邻等级切换,足以覆盖单次
        // 爬升/回落的连续扫桶,不必到 1616。
        cache.countLimit = 300
        return cache
    }()

    private static func loadBucket(for load: Double) -> Int {
        Int(min(100.0, max(0.0, load)).rounded())
    }

    private static func cacheKey(loadBucket: Int, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel, showsAlert: Bool) -> NSString {
        "\(loadBucket)|\(darkMode ? 1 : 0)|\(loadLevel.cacheIndex)|\(showsAlert ? 1 : 0)" as NSString
    }

    static func image(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel, showsAlert: Bool = false) -> NSImage {
        let loadBucket = loadBucket(for: load)
        let canonicalLoad = Double(loadBucket)
        let key = cacheKey(loadBucket: loadBucket, darkMode: darkMode, loadLevel: loadLevel, showsAlert: showsAlert)
        if let cached = cache.object(forKey: key) {
            return cached
        }

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

            let style = MenuBarComputeRingImageStyle(load: canonicalLoad, darkMode: isDark, loadLevel: loadLevel)
            drawRing(style: style, center: NSPoint(x: rect.midX, y: rect.midY))
            if showsAlert {
                MenuBarAlertBadge.draw(in: rect, darkMode: isDark)
            }
            return true
        }
        image.isTemplate = false

        cache.setObject(image, forKey: key)
        return image
    }

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
    let loadLevel: MenuBarComputeLoadLevel

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
        loadLevel.coreColor(darkMode: darkMode)
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

enum MenuBarComputeLoadLevel {
    case idle
    case working
    case busy
    case stressed

    var cacheIndex: Int {
        switch self {
        case .idle: return 0
        case .working: return 1
        case .busy: return 2
        case .stressed: return 3
        }
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
