import Testing
@testable import HagimiMonitorDirect

struct MacOS27AdaptationTests {
    @Test func statusItemRoutesLeftAndRightInputByAvailability() {
        #expect(
            FluidPanelStatusItemRoute.route(
                for: .leftMouseDown,
                commandDown: false,
                usesSystemExpandedInterface: true
            ) == .systemExpandedInterface
        )
        #expect(
            FluidPanelStatusItemRoute.route(
                for: .rightMouseDown,
                commandDown: false,
                usesSystemExpandedInterface: true
            ) == .contextMenu
        )
        #expect(
            FluidPanelStatusItemRoute.route(
                for: .leftMouseDown,
                commandDown: false,
                usesSystemExpandedInterface: false
            ) == .legacyToggle
        )
    }

    @Test func commandDragAlwaysReturnsToTheSystem() {
        #expect(
            FluidPanelStatusItemRoute.route(
                for: .leftMouseDown,
                commandDown: true,
                usesSystemExpandedInterface: true
            ) == .commandDrag
        )
        #expect(
            FluidPanelStatusItemRoute.route(
                for: .rightMouseDown,
                commandDown: true,
                usesSystemExpandedInterface: false
            ) == .commandDrag
        )
    }

    @Test func userDismissalCancelsSessionAndSystemEndDoesNot() {
        let userDecision = FluidPanelDismissalDecision.make(
            panelIsVisible: true,
            awaitingGeometry: false,
            dismissalInProgress: false,
            source: .userAction
        )
        #expect(userDecision.shouldBegin)
        #expect(userDecision.shouldCancelExpandedInterfaceSession)
        #expect(!userDecision.closesAwaitingGeometry)

        let systemDecision = FluidPanelDismissalDecision.make(
            panelIsVisible: true,
            awaitingGeometry: false,
            dismissalInProgress: false,
            source: .systemEnd
        )
        #expect(systemDecision.shouldBegin)
        #expect(!systemDecision.shouldCancelExpandedInterfaceSession)
    }

    @Test func dismissalDecisionIsIdempotentDuringAnimationAndClosesPendingGeometry() {
        let reentrantSystemEnd = FluidPanelDismissalDecision.make(
            panelIsVisible: true,
            awaitingGeometry: false,
            dismissalInProgress: true,
            source: .systemEnd
        )
        #expect(!reentrantSystemEnd.shouldBegin)
        #expect(!reentrantSystemEnd.shouldCancelExpandedInterfaceSession)

        let pendingUserDismissal = FluidPanelDismissalDecision.make(
            panelIsVisible: false,
            awaitingGeometry: true,
            dismissalInProgress: false,
            source: .userAction
        )
        #expect(pendingUserDismissal.shouldBegin)
        #expect(pendingUserDismissal.closesAwaitingGeometry)
        #expect(pendingUserDismissal.shouldCancelExpandedInterfaceSession)
    }
}
