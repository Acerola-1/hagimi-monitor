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
        // 回落余量使同一负载桶可能呈现不同中心颜色，档位参与缓存键。
        // 保留最近负载区间及两种外观，避免升降过程中反复淘汰、重绘。
        cache.countLimit = 300
        return cache
    }()

    private static func loadBucket(for load: Double) -> Int {
        Int(min(100.0, max(0.0, load)).rounded())
    }

    private static func cacheKey(
        loadBucket: Int,
        coreLevel: MenuBarCoreLevel,
        darkMode: Bool,
        increaseContrast: Bool,
        showsAlert: Bool,
        showsHUDBadge: Bool
    ) -> NSNumber {
        // 告警红点（右上）与 HUD 紫菱（右下）可同时存在，按 2 位标志组合编码。
        let badge = (showsAlert ? 1 : 0) | (showsHUDBadge ? 2 : 0)
        let appearanceSlot = (darkMode ? 1 : 0) + (increaseContrast ? 2 : 0)
        return NSNumber(value: ((loadBucket * 3 + coreLevel.rawValue) * 4 + appearanceSlot) * 4 + badge)
    }

    static func image(
        load: Double,
        darkMode: Bool,
        coreLevel: MenuBarCoreLevel? = nil,
        showsAlert: Bool = false,
        showsHUDBadge: Bool = false,
        increaseContrast: Bool = false
    ) -> NSImage {
        let loadBucket = loadBucket(for: load)
        let canonicalLoad = Double(loadBucket)
        let resolvedCoreLevel = coreLevel ?? MenuBarCoreLevel.normal.updated(for: canonicalLoad)
        let key = cacheKey(
            loadBucket: loadBucket,
            coreLevel: resolvedCoreLevel,
            darkMode: darkMode,
            increaseContrast: increaseContrast,
            showsAlert: showsAlert,
            showsHUDBadge: showsHUDBadge
        )
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

            let appearance = NSAppearance.currentDrawing()
            let matchedAppearance = appearance.bestMatch(from: NSAppearance.supportedAppearances)
            let isDark = matchedAppearance.map(NSAppearance.isDark(appearanceName:)) ?? darkMode
            let isHighContrast = increaseContrast
                || (matchedAppearance.map(NSAppearance.isHighContrast(appearanceName:)) ?? false)

            let style = MenuBarComputeRingImageStyle(
                load: canonicalLoad,
                darkMode: isDark,
                coreLevel: resolvedCoreLevel,
                increaseContrast: isHighContrast
            )
            drawRing(style: style, center: NSPoint(x: rect.midX, y: rect.midY))
            if showsAlert {
                MenuBarAlertBadge.draw(in: rect, darkMode: isDark)
            }
            if showsHUDBadge {
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
        let endAngle = 90 - CGFloat(style.progress * 360)

        // 底轨与活跃弧共用同心同半径，且仅绘制未覆盖的剩余弧段，
        // 避免半透明活跃弧叠加全圆底轨导致中轴发虚或出现内外双层边缘。
        drawArc(
            in: ringRect,
            startAngle: endAngle,
            endAngle: -270,
            lineWidth: style.trackWidth,
            lineCapStyle: .butt,
            color: style.trackColor
        )

        drawArc(
            in: ringRect,
            startAngle: 90,
            endAngle: endAngle,
            lineWidth: style.lineWidth,
            lineCapStyle: .round,
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

    private static func drawArc(
        in rect: NSRect,
        startAngle: CGFloat,
        endAngle: CGFloat,
        lineWidth: CGFloat,
        lineCapStyle: NSBezierPath.LineCapStyle,
        color: NSColor
    ) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = lineCapStyle
        color.setStroke()
        path.stroke()
    }
}

private struct MenuBarComputeRingImageStyle {
    let load: Double
    let darkMode: Bool
    let coreLevel: MenuBarCoreLevel
    let increaseContrast: Bool

    private var normalizedLoad: Double {
        min(1, max(0, load / 100))
    }

    /// 补偿 `.round` 圆头端帽的半线宽延伸，控制 0% 克制起步并确保 100% 保留顶部微缺口。
    var progress: Double {
        min(0.89, max(0.06, 0.06 + normalizedLoad * 0.83))
    }

    var tint: NSColor {
        let alpha = increaseContrast ? 1.0 : (0.90 + normalizedLoad * 0.10)
        return ink.withAlphaComponent(alpha)
    }

    var trackColor: NSColor {
        let alpha: Double = increaseContrast
            ? (darkMode ? 0.56 : 0.50)
            : (darkMode ? 0.34 : 0.28)
        return ink.withAlphaComponent(alpha)
    }

    var coreColor: NSColor {
        // 核心点实色填充，避免下方隔离背板透色使其发灰。
        coreLevel.color(darkMode: darkMode)
    }

    var lineWidth: CGFloat {
        CGFloat(2.0 + normalizedLoad * 0.25)
    }

    var ringSize: CGFloat {
        13.0
    }

    var coreSize: CGFloat {
        CGFloat(3.4 + normalizedLoad * 0.9)
    }

    var coreBackplateSize: CGFloat {
        coreSize + 1.5
    }

    var trackWidth: CGFloat {
        increaseContrast ? 1.5 : 1.35
    }

    var coreBackplateColor: NSColor {
        darkMode
            ? NSColor.black.withAlphaComponent(increaseContrast ? 0.72 : 0.52)
            : NSColor.white.withAlphaComponent(increaseContrast ? 0.88 : 0.68)
    }

    private var ink: NSColor {
        darkMode ? .white : .black
    }
}

nonisolated enum MenuBarComputeLoadLevel: Sendable {
    case idle
    case working
    case busy
    case stressed

    func coreColor(darkMode: Bool) -> NSColor {
        switch self {
        case .idle, .working:
            return darkMode
                ? NSColor(srgbRed: 0.26, green: 0.90, blue: 0.56, alpha: 1)
                : NSColor(srgbRed: 0.04, green: 0.58, blue: 0.34, alpha: 1)
        case .busy:
            return darkMode
                ? NSColor(srgbRed: 1.00, green: 0.74, blue: 0.28, alpha: 1)
                : NSColor(srgbRed: 0.82, green: 0.46, blue: 0.04, alpha: 1)
        case .stressed:
            return darkMode
                ? NSColor(srgbRed: 1.00, green: 0.36, blue: 0.32, alpha: 1)
                : NSColor(srgbRed: 0.80, green: 0.14, blue: 0.12, alpha: 1)
        }
    }
}

/// 中心点使用三个固定语义色；下降留出余量，避免临界负载反复换色。
nonisolated enum MenuBarCoreLevel: Int, Equatable, Sendable {
    case normal
    case busy
    case stressed

    func updated(for load: Double) -> Self {
        let busyThreshold = MonitorConstants.menuBarLoadLevelBoundaries[1]
        let stressedThreshold = MonitorConstants.menuBarLoadLevelBoundaries[2]
        let recoveryMargin = MonitorConstants.menuBarCoreRecoveryMargin
        if load >= stressedThreshold { return .stressed }
        if self == .stressed && load > stressedThreshold - recoveryMargin { return .stressed }
        if load >= busyThreshold { return .busy }
        if self != .normal && load > busyThreshold - recoveryMargin { return .busy }
        return .normal
    }

    func color(darkMode: Bool) -> NSColor {
        switch self {
        case .normal: return MenuBarComputeLoadLevel.working.coreColor(darkMode: darkMode)
        case .busy: return MenuBarComputeLoadLevel.busy.coreColor(darkMode: darkMode)
        case .stressed: return MenuBarComputeLoadLevel.stressed.coreColor(darkMode: darkMode)
        }
    }
}
