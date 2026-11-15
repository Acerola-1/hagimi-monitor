import Testing
@testable import HagimiMonitorDirect

struct PanelKeyboardFocusTests {
    @Test func ringFollowsTheLatestInputDevice() {
        PanelKeyboardFocusRing.notePointer()
        #expect(!PanelKeyboardFocusRing.shouldShow(focused: true))
        #expect(!PanelKeyboardFocusRing.shouldShow(focused: false))

        PanelKeyboardFocusRing.noteKeyDown()
        #expect(PanelKeyboardFocusRing.shouldShow(focused: true))
        #expect(!PanelKeyboardFocusRing.shouldShow(focused: false))

        PanelKeyboardFocusRing.notePointer()
        #expect(!PanelKeyboardFocusRing.shouldShow(focused: true))
    }
}
