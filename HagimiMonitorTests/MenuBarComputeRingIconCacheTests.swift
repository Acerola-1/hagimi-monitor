import Testing
import AppKit
@testable import HagimiMonitorDirect

@Suite("MenuBarComputeRingIcon cache")
struct MenuBarComputeRingIconCacheTests {

    @Test("Same parameters return identical NSImage instance")
    func sameParametersHitCache() {
        let a = MenuBarComputeRingIcon.image(load: 50, darkMode: true)
        let b = MenuBarComputeRingIcon.image(load: 50, darkMode: true)
        #expect(a === b)
    }

    @Test("Loads inside same 1% bucket hit same cache entry")
    func quantizedBucketCollapsesNeighbors() {
        let a = MenuBarComputeRingIcon.image(load: 50.0, darkMode: false)
        let b = MenuBarComputeRingIcon.image(load: 50.4, darkMode: false)
        #expect(a === b)
    }

    @Test("Loads in adjacent 1% buckets get different NSImages")
    func adjacentBucketsMiss() {
        let a = MenuBarComputeRingIcon.image(load: 50.0, darkMode: false)
        let b = MenuBarComputeRingIcon.image(load: 50.9, darkMode: false)
        #expect(a !== b)
    }

    @Test("Loads in different buckets get different NSImages")
    func differentBucketsMiss() {
        let a = MenuBarComputeRingIcon.image(load: 10, darkMode: false)
        let b = MenuBarComputeRingIcon.image(load: 90, darkMode: false)
        #expect(a !== b)
    }

    @Test("darkMode dimension is part of cache key")
    func darkModeIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: false)
        #expect(a !== b)
    }

    @Test("alert badge dimension is part of cache key")
    func alertBadgeIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, showsAlert: false)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: true, showsAlert: true)
        #expect(a !== b)
        // 同参数(含红点开关)仍命中同一实例,维持「同态同对象」的赋值去重前提。
        let c = MenuBarComputeRingIcon.image(load: 30, darkMode: true, showsAlert: true)
        #expect(b === c)
    }

    @Test("Out-of-range loads are clamped to valid buckets")
    func clampingBehavior() {
        let negative = MenuBarComputeRingIcon.image(load: -10, darkMode: false)
        let zero = MenuBarComputeRingIcon.image(load: 0, darkMode: false)
        let over = MenuBarComputeRingIcon.image(load: 200, darkMode: false)
        let hundred = MenuBarComputeRingIcon.image(load: 100, darkMode: false)
        #expect(negative === zero)
        #expect(over === hundred)
    }

    @Test("Alert and HUD badges coexist as distinct cache entries")
    func alertAndHUDBadgesCoexistInCache() {
        let none = MenuBarComputeRingIcon.image(load: 50, darkMode: true)
        let alert = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true)
        let hud = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsHUDBadge: true)
        let both = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true, showsHUDBadge: true)
        #expect(alert !== none)
        #expect(hud !== none)
        #expect(hud !== alert)
        #expect(both !== none)
        #expect(both !== alert)
        #expect(both !== hud)
        #expect(both === MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true, showsHUDBadge: true))
    }

    @Test("increaseContrast dimension is part of cache key")
    func increaseContrastIsKeyed() {
        for dark in [false, true] {
            let normal = MenuBarComputeRingIcon.image(load: 45, darkMode: dark, increaseContrast: false)
            let highContrast = MenuBarComputeRingIcon.image(load: 45, darkMode: dark, increaseContrast: true)
            #expect(normal !== highContrast)
            #expect(highContrast === MenuBarComputeRingIcon.image(load: 45, darkMode: dark, increaseContrast: true))
        }
    }

    @Test("Full load retains open top gap and dual badges render independently")
    func fullLoadGapAndDualBadgePixels() throws {
        MenuBarComputeRingIcon.clearCacheForTesting()
        let fullRing = MenuBarComputeRingIcon.image(load: 100, darkMode: true)
        let fullBitmap = try renderBitmap(fullRing, darkMode: true)

        // 12 点钟起笔处实心高不透明，左侧（约 11 点半）保留仅绘剩余底轨的低不透明缺口。
        let topStartAlpha = fullBitmap.colorAt(x: 21, y: 8)?.alphaComponent ?? 0
        let gapAlpha = fullBitmap.colorAt(x: 17, y: 8)?.alphaComponent ?? 0
        #expect(topStartAlpha > 0.85)
        #expect(gapAlpha > 0.15 && gapAlpha < 0.55)

        let noneBitmap = try renderBitmap(
            MenuBarComputeRingIcon.image(load: 50, darkMode: true),
            darkMode: true
        )
        let bothBitmap = try renderBitmap(
            MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true, showsHUDBadge: true),
            darkMode: true
        )

        #expect(maxAlpha(in: noneBitmap, xRange: 35...40, yRange: 2...7) < 0.05)
        #expect(maxAlpha(in: noneBitmap, xRange: 34...40, yRange: 34...40) < 0.05)

        // 右上角为偏红的告警圆点，右下角为偏紫的 HUD 菱形。
        let topRightAlert = try #require(bothBitmap.colorAt(x: 37, y: 5))
        #expect(topRightAlert.alphaComponent > 0.85)
        #expect(topRightAlert.redComponent > topRightAlert.blueComponent + 0.3)

        let bottomRightHUD = try #require(bothBitmap.colorAt(x: 37, y: 37))
        #expect(bottomRightHUD.alphaComponent > 0.85)
        #expect(bottomRightHUD.blueComponent > 0.65 && bottomRightHUD.redComponent > 0.45)
    }

    private func renderBitmap(_ image: NSImage, darkMode: Bool) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 42,
            pixelsHigh: 42,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(x: 0, y: 0, width: 42, height: 42))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func maxAlpha(in bitmap: NSBitmapImageRep, xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> CGFloat {
        var result: CGFloat = 0
        for y in yRange {
            for x in xRange {
                result = max(result, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return result
    }

    @Test("Recovery colors at the same load use separate cache entries")
    func coreLevelIsKeyed() {
        for dark in [false, true] {
            let normal = MenuBarComputeRingIcon.image(load: 49, darkMode: dark, coreLevel: .normal)
            let busy = MenuBarComputeRingIcon.image(load: 49, darkMode: dark, coreLevel: .busy)
            #expect(normal !== busy)
            #expect(busy === MenuBarComputeRingIcon.image(load: 49, darkMode: dark, coreLevel: .busy))
            let stressed = MenuBarComputeRingIcon.image(load: 77, darkMode: dark, coreLevel: .stressed)
            #expect(stressed !== MenuBarComputeRingIcon.image(load: 77, darkMode: dark, coreLevel: .busy))
        }
    }
}
