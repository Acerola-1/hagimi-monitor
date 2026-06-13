import CoreGraphics
import Foundation
import Testing
@testable import HagimiMonitor

struct MetricFlowPlacerTests {
    private let containerWidth: CGFloat = 200
    private let columnSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 6
    // halfWidth = (200 - 8) / 2 = 96

    @Test func allShortItemsPairUpInTwoColumns() {
        let sizes = [
            CGSize(width: 60, height: 16),
            CGSize(width: 50, height: 16),
            CGSize(width: 70, height: 16),
            CGSize(width: 40, height: 16)
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.count == 4)
        #expect(result.frames[0].origin == CGPoint(x: 0, y: 0))
        #expect(result.frames[0].size.width == 96)
        #expect(result.frames[1].origin == CGPoint(x: 104, y: 0))
        #expect(result.frames[1].size.width == 96)
        #expect(result.frames[2].origin == CGPoint(x: 0, y: 22))
        #expect(result.frames[3].origin == CGPoint(x: 104, y: 22))
        #expect(result.totalSize == CGSize(width: 200, height: 38))
    }

    @Test func longItemTakesFullRowAndCompactsAfter() {
        // 索引 1 是长内容（150 > halfWidth 96）
        let sizes = [
            CGSize(width: 60, height: 16),   // 短，进左半槽
            CGSize(width: 150, height: 18),  // 长，独占整行（先收尾上一行）
            CGSize(width: 70, height: 16),   // 短，进新行左半槽
            CGSize(width: 40, height: 16)    // 短，进同一行右半槽
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        // 第 0 行：索引 0 在左半槽
        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 96, height: 16))
        // 第 1 行：索引 1 独占整行，y = 16 + 6 = 22
        #expect(result.frames[1] == CGRect(x: 0, y: 22, width: 200, height: 18))
        // 第 2 行：索引 2 进左半槽，y = 22 + 18 + 6 = 46
        #expect(result.frames[2] == CGRect(x: 0, y: 46, width: 96, height: 16))
        // 第 2 行：索引 3 进右半槽
        #expect(result.frames[3] == CGRect(x: 104, y: 46, width: 96, height: 16))
        // 总高 = 46 + 16 = 62
        #expect(result.totalSize == CGSize(width: 200, height: 62))
    }

    @Test func trailingOddItemKeepsHalfRow() {
        let sizes = [
            CGSize(width: 60, height: 16),
            CGSize(width: 50, height: 16),
            CGSize(width: 70, height: 18) // 落单
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames[2] == CGRect(x: 0, y: 22, width: 96, height: 18))
        // 落单 cell 仍只占半行
        #expect(result.frames[2].size.width == 96)
        #expect(result.totalSize == CGSize(width: 200, height: 40))
    }

    @Test func emptyInputReturnsZero() {
        let result = MetricFlowPlacer.place(
            sizes: [],
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.isEmpty)
        #expect(result.totalSize == .zero)
    }

    @Test func longItemAtStartTakesFullRow() {
        let sizes = [
            CGSize(width: 180, height: 18),
            CGSize(width: 50, height: 16)
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 200, height: 18))
        #expect(result.frames[1] == CGRect(x: 0, y: 24, width: 96, height: 16))
        #expect(result.totalSize == CGSize(width: 200, height: 40))
    }

    @Test func zeroContainerWidthReturnsEmpty() {
        let result = MetricFlowPlacer.place(
            sizes: [CGSize(width: 60, height: 16)],
            containerWidth: 0,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.first?.size == .zero)
        #expect(result.totalSize == .zero)
    }
}

