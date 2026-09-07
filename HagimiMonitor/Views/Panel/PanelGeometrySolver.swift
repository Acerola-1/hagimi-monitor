import CoreGraphics
import Foundation

/// 纯几何求解器：根据 GeometrySnapshot 与当前运动相位，集中计算所有尺寸、位置与视口。
/// 无副作用、无 SwiftUI 视图依赖、无状态存储，可在任意线程或测试中独立运行。
enum PanelGeometrySolver {
    static let panelTopMargin: CGFloat = 8
    static let headerToBodySpacing: CGFloat = 4
    static let cardToCardSpacing: CGFloat = 6
    static let childCardSpacing: CGFloat = 6
    static let panelBottomMargin: CGFloat = 6

    /// 求解一次完整布局帧。
    static func solve(
        snapshot: GeometrySnapshot,
        phases: [String: CGFloat],
        frameID: UInt = 0,
        sampleTime: CFTimeInterval = 0,
        scrollOffset: CGFloat = 0
    ) -> PanelFrame {
        var revealHeights: [String: CGFloat] = [:]
        var childFrames: [String: CGRect] = [:]
        var detailContentHeights: [String: CGFloat] = [:]
        var cardFrames: [String: CGRect] = [:]

        // 后序合成使每层只计入孩子已经求出的可见高度。
        var visiting: Set<String> = []
        func resolve(_ id: String, width: CGFloat) -> CGFloat {
            if let reveal = revealHeights[id] { return reveal }
            guard let section = snapshot.sections[id], visiting.insert(id).inserted else { return 0 }
            defer { visiting.remove(id) }
            let group = snapshot.childGroup(id)
            var natural = section.detailHeight + group.top
            var childCount = 0
            for childID in snapshot.childrenByParent[id] ?? [] {
                guard let child = snapshot.sections[childID], child.isAvailable else { continue }
                if childCount > 0 || section.detailHeight > 0 { natural += group.spacing }
                let childWidth = max(0, width - group.leading - group.trailing)
                let height = child.headerHeight + resolve(childID, width: childWidth)
                childFrames[childID] = CGRect(x: group.leading, y: natural, width: childWidth, height: height)
                natural += height
                childCount += 1
            }
            natural += group.bottom
            detailContentHeights[id] = natural
            let base = section.collapsedDetailHeight
            let reveal = section.isAvailable ? max(0, base + (natural - base) * max(0, phases[id] ?? 0)) : 0
            revealHeights[id] = reveal
            return reveal
        }
        for id in snapshot.orderedTopLevelIDs { _ = resolve(id, width: snapshot.cardWidth) }

        // 3. 计算顶级卡片与底部区域在主体坐标系中的绝对位置
        var currentY: CGFloat = 0
        for (index, id) in snapshot.orderedTopLevelIDs.enumerated() {
            guard let section = snapshot.sections[id] else { continue }
            if index > 0 {
                currentY += cardToCardSpacing
            }

            let reveal = revealHeights[id] ?? 0
            let cardHeight = section.headerHeight + reveal
            let frame = CGRect(
                x: 0,
                y: currentY,
                width: snapshot.cardWidth,
                height: cardHeight
            )
            cardFrames[id] = frame
            currentY += cardHeight
        }

        // 底部操作按钮区域（如有）
        if snapshot.footerHeight > 0 {
            if !snapshot.orderedTopLevelIDs.isEmpty {
                currentY += cardToCardSpacing
            }
            let footerFrame = CGRect(
                x: 0,
                y: currentY,
                width: snapshot.cardWidth,
                height: snapshot.footerHeight
            )
            cardFrames["__footer__"] = footerFrame
            currentY += snapshot.footerHeight
        }

        let bodyDocumentHeight = currentY
        let cap = snapshot.availableViewportCap
        let isCapped = bodyDocumentHeight > cap
        let viewportHeight = isCapped ? cap : bodyDocumentHeight

        let totalWindowHeight = panelTopMargin
            + snapshot.panelHeaderHeight
            + headerToBodySpacing
            + viewportHeight
            + panelBottomMargin

        let windowContentSize = CGSize(
            width: snapshot.panelWidth,
            height: totalWindowHeight
        )

        var sectionFrames = cardFrames
        func locateChildren(_ id: String) {
            guard (phases[id] ?? 0) > 0, let parent = sectionFrames[id],
                  let section = snapshot.sections[id] else { return }
            for child in snapshot.childrenByParent[id] ?? [] {
                guard let rect = childFrames[child] else { continue }
                sectionFrames[child] = rect.offsetBy(dx: parent.minX, dy: parent.minY + section.headerHeight)
                locateChildren(child)
            }
        }
        for id in snapshot.orderedTopLevelIDs { locateChildren(id) }
        return PanelFrame(
            revision: snapshot.revision,
            frameID: frameID,
            sampleTime: sampleTime,
            cardFrames: cardFrames,
            childFrames: childFrames,
            revealHeights: revealHeights,
            bodyDocumentHeight: bodyDocumentHeight,
            viewportHeight: viewportHeight,
            isCapped: isCapped,
            scrollOffset: min(max(0, scrollOffset), max(0, bodyDocumentHeight - viewportHeight)),
            windowContentSize: windowContentSize,
            detailContentHeights: detailContentHeights, sectionFrames: sectionFrames
        )
    }
}
