import Foundation
import Testing
@testable import HagimiMonitorDirect

struct PanelScrollTests {


    @Test func targetSectionSelectsLastInVisualOrder() {
        let visualOrder = ["cpu", "gpu", "memory", "storage", "fan"]
        let added: Set<String> = ["gpu", "storage", "cpu"]

        // 视觉顺序中最后一个是 storage
        let target = PanelScrollCoordinator.targetSectionForAutoReveal(
            addedIDs: added,
            visualOrder: visualOrder
        )
        #expect(target == "storage")
    }

    @Test func uncappedPanelAlwaysKeepsZeroScrollOffset() {
        let frame = PanelFrame(
            revision: 1,
            frameID: 1,
            sampleTime: 0,
            cardFrames: [
                "cpu": CGRect(x: 0, y: 0, width: 328, height: 100),
                "gpu": CGRect(x: 0, y: 106, width: 328, height: 100)
            ],
            childFrames: [:],
            revealHeights: ["cpu": 66, "gpu": 66],
            bodyDocumentHeight: 206,
            viewportHeight: 206, // 未封顶
            isCapped: false,
            scrollOffset: 0,
            windowContentSize: CGSize(width: 340, height: 260)
        )

        let offset = PanelScrollCoordinator.calculateScrollOffset(for: "gpu", frame: frame)
        #expect(offset == 0.0)
    }

    @Test func cappedPanelAlignsTargetBottomEdgeWithinLegalRange() {
        // 视口被封顶在 150，文档高度为 300
        // card "gpu" 从 106 到 250 (maxY = 250)
        let frame = PanelFrame(
            revision: 1,
            frameID: 1,
            sampleTime: 0,
            cardFrames: [
                "cpu": CGRect(x: 0, y: 0, width: 328, height: 100),
                "gpu": CGRect(x: 0, y: 106, width: 328, height: 144)
            ],
            childFrames: [:],
            revealHeights: ["cpu": 66, "gpu": 110],
            bodyDocumentHeight: 300,
            viewportHeight: 150,
            isCapped: true,
            scrollOffset: 0,
            windowContentSize: CGSize(width: 340, height: 200)
        )

        let offset = PanelScrollCoordinator.calculateScrollOffset(for: "gpu", frame: frame)
        // desired = cardFrame.maxY(250) - viewportHeight(150) = 100
        // maxLegal = 300 - 150 = 150
        // min(100, 150) = 100
        #expect(offset == 100.0)
    }

    @Test func userScrollOffsetClampsToLegalBoundaries() {
        let frame = PanelFrame(
            revision: 1,
            frameID: 1,
            sampleTime: 0,
            cardFrames: [:],
            childFrames: [:],
            revealHeights: [:],
            bodyDocumentHeight: 400,
            viewportHeight: 250,
            isCapped: true,
            scrollOffset: 0,
            windowContentSize: CGSize(width: 340, height: 300)
        )

        // 负偏移 clamp 到 0
        #expect(PanelScrollCoordinator.clampUserOffset(offset: -20, frame: frame) == 0.0)
        // 超大偏移 clamp 到 maxLegal (400 - 250 = 150)
        #expect(PanelScrollCoordinator.clampUserOffset(offset: 200, frame: frame) == 150.0)
        // 合法偏移保持原样
        #expect(PanelScrollCoordinator.clampUserOffset(offset: 80, frame: frame) == 80.0)
    }
}
