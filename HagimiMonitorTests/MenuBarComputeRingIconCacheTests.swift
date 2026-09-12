import Testing
import AppKit
@testable import HagimiMonitorDirect

@Suite("MenuBarComputeRingIcon cache")
struct MenuBarComputeRingIconCacheTests {

    @Test("Same parameters return identical NSImage instance")
    func sameParametersHitCache() {
        let a = MenuBarComputeRingIcon.image(load: 50, darkMode: true, loadLevel: .working)
        let b = MenuBarComputeRingIcon.image(load: 50, darkMode: true, loadLevel: .working)
        #expect(a === b)
    }

    @Test("Loads inside same 1% bucket hit same cache entry")
    func quantizedBucketCollapsesNeighbors() {
        let a = MenuBarComputeRingIcon.image(load: 50.0, darkMode: false, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 50.4, darkMode: false, loadLevel: .idle)
        #expect(a === b)
    }

    @Test("Loads in adjacent 1% buckets get different NSImages")
    func adjacentBucketsMiss() {
        let a = MenuBarComputeRingIcon.image(load: 50.0, darkMode: false, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 50.9, darkMode: false, loadLevel: .idle)
        #expect(a !== b)
    }

    @Test("Loads in different buckets get different NSImages")
    func differentBucketsMiss() {
        let a = MenuBarComputeRingIcon.image(load: 10, darkMode: false, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 90, darkMode: false, loadLevel: .idle)
        #expect(a !== b)
    }

    @Test("darkMode dimension is part of cache key")
    func darkModeIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .working)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: false, loadLevel: .working)
        #expect(a !== b)
    }

    @Test("loadLevel dimension is part of cache key")
    func loadLevelIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .stressed)
        #expect(a !== b)
    }

    @Test("alert badge dimension is part of cache key")
    func alertBadgeIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .idle, showsAlert: false)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .idle, showsAlert: true)
        #expect(a !== b)
        // 同参数(含红点开关)仍命中同一实例,维持「同态同对象」的赋值去重前提。
        let c = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .idle, showsAlert: true)
        #expect(b === c)
    }

    @Test("Out-of-range loads are clamped to valid buckets")
    func clampingBehavior() {
        let negative = MenuBarComputeRingIcon.image(load: -10, darkMode: false, loadLevel: .idle)
        let zero = MenuBarComputeRingIcon.image(load: 0, darkMode: false, loadLevel: .idle)
        let over = MenuBarComputeRingIcon.image(load: 200, darkMode: false, loadLevel: .idle)
        let hundred = MenuBarComputeRingIcon.image(load: 100, darkMode: false, loadLevel: .idle)
        #expect(negative === zero)
        #expect(over === hundred)
    }
}
