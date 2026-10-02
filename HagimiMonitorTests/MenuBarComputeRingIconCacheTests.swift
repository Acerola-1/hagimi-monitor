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

    @Test("Alert priority removes the redundant HUD cache dimension")
    func alertDominatesHUDCacheState() {
        let alert = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true)
        let both = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsAlert: true, showsHUDBadge: true)
        #expect(alert === both)
        let hud = MenuBarComputeRingIcon.image(load: 50, darkMode: true, showsHUDBadge: true)
        #expect(hud !== alert)
    }
}
