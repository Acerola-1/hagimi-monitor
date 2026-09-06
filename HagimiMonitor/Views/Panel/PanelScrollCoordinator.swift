import CoreGraphics
import Foundation

/// 统一滚动协调器：根据已知几何帧计算确定性的自动揭示滚动目标，
/// 并支持用户交互（滚轮/触控板）无缝接管。
struct PanelScrollCoordinator: Sendable {

    /// 根据当前新增展开的卡片集合与视觉顺序，选取唯一的目标卡片 ID。
    static func targetSectionForAutoReveal(
        addedIDs: Set<String>,
        visualOrder: [String]
    ) -> String? {
        // 按当前视觉顺序选择最后一个实际新展开且有内容的分区
        visualOrder.reversed().first(where: { addedIDs.contains($0) })
    }

    /// 根据几何帧与目标卡片，纯函数计算目标滚动偏移。
    static func calculateScrollOffset(
        for targetID: String?,
        frame: PanelFrame
    ) -> CGFloat {
        guard let targetID,
              let cardFrame = frame.sectionFrames[targetID] ?? frame.cardFrames[targetID],
              frame.isCapped,
              frame.viewportHeight > 0 else {
            return 0
        }

        let maxLegalOffset = max(0, frame.bodyDocumentHeight - frame.viewportHeight)
        guard maxLegalOffset > 0 else { return 0 }

        // 目标底缘在合法范围内尽量对齐视口底缘
        let desiredOffset = cardFrame.maxY - frame.viewportHeight
        return max(0, min(desiredOffset, maxLegalOffset))
    }

    /// 用户手动滚动时的偏移夹取与合法化。
    static func clampUserOffset(
        offset: CGFloat,
        frame: PanelFrame
    ) -> CGFloat {
        guard frame.isCapped else { return 0 }
        let maxLegal = max(0, frame.bodyDocumentHeight - frame.viewportHeight)
        return max(0, min(offset, maxLegal))
    }
}
