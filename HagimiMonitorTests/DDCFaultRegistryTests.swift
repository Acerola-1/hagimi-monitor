import Testing
@testable import HagimiMonitor
import CoreGraphics

struct DDCFaultRegistryTests {
    private let key = ControlKey(displayID: 1, control: .brightness)

    @Test func startsEnabled() {
        let r = DDCFaultRegistry()
        #expect(!r.isDisabled(key))
        #expect(!r.shouldUseLongerDelay(key))
    }

    @Test func disablesAfterFiveReadFailures() {
        let r = DDCFaultRegistry()
        for _ in 0..<4 { r.recordReadFailure(key) }
        #expect(!r.isDisabled(key))
        r.recordReadFailure(key)
        #expect(r.isDisabled(key))
    }

    @Test func disablesAfterTenWriteFailures() {
        let r = DDCFaultRegistry()
        for _ in 0..<9 { r.recordWriteFailure(key) }
        #expect(!r.isDisabled(key))
        r.recordWriteFailure(key)
        #expect(r.isDisabled(key))
    }

    @Test func longerDelayKicksInAtThreeReadFailures() {
        let r = DDCFaultRegistry()
        r.recordReadFailure(key)
        r.recordReadFailure(key)
        #expect(!r.shouldUseLongerDelay(key))
        r.recordReadFailure(key)
        #expect(r.shouldUseLongerDelay(key))
    }

    @Test func successDecrementsReadFault() {
        let r = DDCFaultRegistry()
        r.recordReadFailure(key)
        r.recordReadFailure(key)
        r.recordReadSuccess(key)
        #expect(!r.shouldUseLongerDelay(key))
    }

    @Test func resetClearsAllControlsForDisplay() {
        let r = DDCFaultRegistry()
        for _ in 0..<5 { r.recordReadFailure(key) }
        let other = ControlKey(displayID: 2, control: .brightness)
        for _ in 0..<5 { r.recordReadFailure(other) }
        r.reset(displayID: 1)
        #expect(!r.isDisabled(key))
        #expect(r.isDisabled(other))
    }
}
