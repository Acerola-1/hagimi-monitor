import CoreGraphics
import Foundation

/// 展开分区的稳定标识符。
enum PanelSectionKind: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case storage
    case fan
    case network
    case battery
    case display

    var id: String { rawValue }
}

/// 几何环境签名，用于检测环境失效。
struct GeometryEnvironmentToken: Equatable, Sendable {
    var width: CGFloat
    var localeIdentifier: String
    var dynamicTypeSize: String
    var backingScale: CGFloat
    var structureSignature: String
}

/// 单个分区的自然尺寸与层级信息。
struct SectionNaturalSize: Equatable, Sendable {
    var id: String
    var parentID: String?
    var headerHeight: CGFloat
    var detailHeight: CGFloat
    var isAvailable: Bool = true
    var collapsedDetailHeight: CGFloat = 0

    var totalNaturalHeight: CGFloat {
        headerHeight + (isAvailable ? detailHeight : 0)
    }
}

/// 子列表在父明细中的内衬与节奏；宽度逐层从父级扣除。
struct PanelChildGroup: Equatable, Sendable {
    var ids: [String]
    var leading: CGFloat = 28
    var trailing: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var spacing: CGFloat = 6
}

/// 某一版本的完整面板几何快照（只读）。
struct GeometrySnapshot: Equatable, Sendable {
    var revision: UInt
    var environment: GeometryEnvironmentToken
    var panelWidth: CGFloat
    var panelHeaderHeight: CGFloat
    var footerHeight: CGFloat
    var contentHeightCap: CGFloat

    /// 顶级卡片稳定 ID 顺序。
    var orderedTopLevelIDs: [String]
    /// 所有已登记分区（含子分区）。
    var sections: [String: SectionNaturalSize]
    /// 父分区 ID -> 子分区 ID 列表。
    var childrenByParent: [String: [String]]
    var childGroups: [String: PanelChildGroup] = [:]

    func childGroup(_ id: String) -> PanelChildGroup {
        childGroups[id] ?? PanelChildGroup(ids: childrenByParent[id] ?? [])
    }

    func width(for id: String) -> CGFloat {
        var width = cardWidth
        var current = id
        var visited: Set<String> = []
        while let parent = sections[current]?.parentID, visited.insert(current).inserted {
            let group = childGroup(parent)
            width = max(0, width - group.leading - group.trailing)
            current = parent
        }
        return width
    }

    var visualOrder: [String] {
        var result: [String] = []
        var visited: Set<String> = []
        func append(_ id: String) {
            guard visited.insert(id).inserted else { return }
            result.append(id)
            for child in childrenByParent[id] ?? [] { append(child) }
        }
        for id in orderedTopLevelIDs { append(id) }
        return result
    }

    var cardWidth: CGFloat {
        max(0, panelWidth - 12)
    }

    var availableViewportCap: CGFloat {
        max(0, contentHeightCap - (8 + panelHeaderHeight + 4 + 6))
    }
}

/// 某单一运动采样时刻由纯几何求解派生的布局帧。
struct PanelFrame: Equatable, Sendable {
    var revision: UInt
    var frameID: UInt
    var sampleTime: CFTimeInterval

    /// 顶级卡片在主体坐标系中的 CGRect。
    var cardFrames: [String: CGRect]
    /// 子分区在父明细坐标系中的 CGRect。
    var childFrames: [String: CGRect]
    /// 各分区的实际揭示高度。
    var revealHeights: [String: CGFloat]
    /// 主体完整文档高度（含卡片、卡片间距、底部按钮）。
    var bodyDocumentHeight: CGFloat
    /// 视口高度（受屏幕上限封顶）。
    var viewportHeight: CGFloat
    var isCapped: Bool
    /// 自动或手动滚动偏移。
    var scrollOffset: CGFloat
    /// 真实窗口内容尺寸。
    var windowContentSize: CGSize
    var detailContentHeights: [String: CGFloat] = [:]
    /// 所有可见层级在主体中的位置，供嵌套档案自动揭示使用。
    var sectionFrames: [String: CGRect] = [:]
}
