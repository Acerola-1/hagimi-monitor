import AppKit
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct CPUCoreHoverTests {
    @Test func repeatedHoverTracksWrappedRowsAndClearsOnDetach() {
        let region = CoreRingHoverRegion.TrackingView(frame: CGRect(x: 0, y: 0, width: 64, height: 54))
        region.coreIDs = [8, 2, 5]
        var reported: [Int?] = []
        region.onHover = { reported.append($0) }
        let window = NSWindow(contentRect: region.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = region
        region.layoutSubtreeIfNeeded()
        region.updateHover(at: CGPoint(x: 17, y: 15))
        region.updateHover(at: CGPoint(x: 32, y: 15))
        region.updateHover(at: CGPoint(x: 17, y: 15))
        region.updateHover(at: CGPoint(x: 47, y: 15))
        region.updateHover(at: CGPoint(x: 17, y: 39))
        region.updateHover(at: CGPoint(x: 32, y: 39))
        window.contentView = nil
        #expect(reported.suffix(7) == [8, nil, 8, 2, nil, 5, nil])
    }
}
