import AppKit
import Combine
import SwiftUI

/// 展开动画的高度跟踪与窗口贴合协调器。
///
/// 内容侧(`CollapsibleDetail`)的布局高度动画完全交给 SwiftUI 自身动画系统
/// (`withAnimation` / `.animation(value:)`):toggle 时 body 只求值一次,帧间插值
/// 由 CoreAnimation 在合成器侧完成,不在主线程逐帧重算——这是与外部 60Hz Timer
/// 驱动 `@Published` 的本质区别(后者每帧整树 body 重算 + 布局,CPU 打满)。
///
/// 本驱动器不再发布逐帧相位,只做两件事:
/// 1. 跟踪各展开区自然高度(CollapsibleDetail 上报),据此预测窗口目标高度;
/// 2. 在 toggle 发生时一次性把目标高度下发给窗口层——animated 则由 CoreAnimation
///    补间窗口 frame,instant 则同步贴合。
///
/// 内容与窗口分走两条同时长同曲线(easeInOut 0.15s)的动画路径:内容由 SwiftUI
/// 动画系统插值,窗口由 CA 插值。两者端点对齐,中间帧曲线相近。
@MainActor
final class PanelExpansionDriver: ObservableObject {
    /// 各展开区当前目标相位(0=收起,1=展开)。非动画期间等于 0 或 1。
    /// 仅用于窗口高度预测,不再驱动布局——布局由 SwiftUI 动画系统接管。
    private(set) var phase: [String: CGFloat] = [:]

    /// 各展开区内容的自然高度(CollapsibleDetail 上报),用于窗口高度预测。
    private var naturalHeights: [String: CGFloat] = [:]
    /// 最近一次实测的内容总高度(面板内容 GeometryReader 上报)。
    private var lastMeasuredContentHeight: CGFloat = 0
    /// 收起态(全部展开区高度为 0)的内容总高度。非动画期间从实测值反推校准。
    private var collapsedBaseHeight: CGFloat = 0
    /// 展开/收起动画截止时刻。动画窗口内跳过基线校准——相位已瞬翻到目标值,
    /// 而实测高度还在 SwiftUI 插值中(滞后),此时反推会解出负数基线,
    /// 收起时预测高度据此算出错误值,窗口被钳到 minPanelHeight。
    private var animationDeadline: Date = .distantPast
    /// 内容总高度上限(菜单栏面板 = 屏幕可用高度,由视图上报;钉住面板为无穷)。
    /// 封顶期间 ScrollView 把实测高度钳在上限,「实测 = 基线 + Σ相位高度」的
    /// 反推等式失真(会解出过小甚至为负的基线,再经 predicted 把窗口带到
    /// 错误高度)——此时跳过校准、保留上次一致值,预测值同样钳在上限内。
    private var contentHeightCap: CGFloat = .infinity

    /// 窗口贴合回调:(目标内容总高度, 是否动画)。
    /// animated=true 时由 CoreAnimation 补间窗口 frame;false 时同步贴合。
    /// nil 时(预览/无窗口宿主)不贴合,不影响动画本身。
    var onWindowResize: ((CGFloat, Bool) -> Void)?

    /// 把一批展开区动画到各自目标相位(0 或 1)。
    /// 相位瞬时设到目标(布局动画由 SwiftUI withAnimation 处理),
    /// 窗口目标高度一次性下发给窗口层做 CA 补间。
    func animate(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        for (key, target) in targets {
            phase[key] = target
        }
        animationDeadline = Date().addingTimeInterval(MonitorConstants.panelExpansionDuration + 0.05)
        onWindowResize?(predictedContentHeight, true)
    }

    /// 瞬时把相位设到目标(无动画)。用于面板隐藏期/初始化阶段同步最终布局状态。
    func setInstantly(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        for (key, target) in targets {
            phase[key] = target
        }
        animationDeadline = .distantPast
        onWindowResize?(predictedContentHeight, false)
    }

    /// 单 key 版 `setInstantly`:同步语义调用方(初始化/隐藏重置)的便捷入口。
    func setInstantly(_ key: String, _ value: CGFloat) {
        setInstantly(targets: [key: value])
    }

    /// 单 key 版 `animate`:toggle 单个展开区的便捷入口。
    func animate(_ key: String, _ target: CGFloat) {
        animate(targets: [key: target])
    }

    /// CollapsibleDetail 上报其展开内容的自然高度(内容常驻,首次挂载即测量)。
    func reportNaturalHeight(_ key: String, _ height: CGFloat) {
        naturalHeights[key] = height
        recalibrateBaseHeight()
    }

    /// 面板内容 GeometryReader 上报实测总高度(稳态校准用)。
    func reportMeasuredContentHeight(_ height: CGFloat) {
        lastMeasuredContentHeight = height
        recalibrateBaseHeight()
    }

    /// 视图上报内容总高度上限(菜单栏下沿到屏幕底部的可用空间)。
    /// 上限变化(换屏/面板锚点移动)时随测高校报一起刷新即可。
    func reportContentHeightCap(_ cap: CGFloat) {
        contentHeightCap = cap
    }

    /// 非动画期间从实测值反推收起态基线高度。
    private func recalibrateBaseHeight() {
        guard lastMeasuredContentHeight > 0 else { return }
        // 动画窗口内跳过:相位已瞬翻而实测高度仍在插值,反推会解出错误基线。
        guard Date() >= animationDeadline else { return }
        // 封顶中:实测高度被钳在上限,反推不出基线(等式失真),保留上次校准值。
        guard lastMeasuredContentHeight < contentHeightCap - 0.5 else { return }
        let totalExpanded = naturalHeights.reduce(into: 0.0) { acc, kv in
            acc += kv.value * (phase[kv.key] ?? 0)
        }
        collapsedBaseHeight = lastMeasuredContentHeight - totalExpanded
    }

    /// 当前预测的内容总高度 = 收起基线 + 各展开区按相位占用的高度,
    /// 并钳制在内容上限内(封顶时内容实际高度不再随展开增长,窗口不应超出)。
    private var predictedContentHeight: CGFloat {
        let totalExpanded = naturalHeights.reduce(into: 0.0) { acc, kv in
            acc += kv.value * (phase[kv.key] ?? 0)
        }
        return min(max(collapsedBaseHeight + totalExpanded, 0), contentHeightCap)
    }
}

/// 窗口贴合回调:driver 在 toggle 时把目标内容总高度与是否动画下发给窗口层。
/// 仅由有窗口宿主的 controller 注入;预览/无窗口宿主为 nil,driver 不贴合。
private struct PanelWindowResizeHandlerKey: EnvironmentKey {
    static let defaultValue: ((CGFloat, Bool) -> Void)? = nil
}

extension EnvironmentValues {
    var panelWindowResizeHandler: ((CGFloat, Bool) -> Void)? {
        get { self[PanelWindowResizeHandlerKey.self] }
        set { self[PanelWindowResizeHandlerKey.self] = newValue }
    }
}

/// 面板窗口展开/收起动画的一次性 CA 补间执行器。
///
/// Fluid(菜单栏锚定)与 Pinned(固定顶部)两个面板控制器共用同一套
/// 「代际 token + isAnimating 抑制 + 结束对账」防护,消除逐字复制的竞态处理。
/// 定位策略(屏幕钳制/锚定)仍由各控制器自行计算目标 frame,
/// 动画结束后的对账回调由调用方经 `onComplete` 注入。
@MainActor
final class PanelExpansionAnimation {
    private var isAnimating = false
    private var token = 0

    /// 动画进行中:期间 contentSizeDidChange 的逐帧贴合应被抑制,避免与 CA 补间
    /// 叠加冲突并把 CPU 打满。动画结束后由对账回调做最终校准。
    var isAnimatingExpansion: Bool { isAnimating }

    /// 执行一次展开/收起动画。整个动画期间窗口 resize 只发生一次(CA 补间)。
    /// - Parameters:
    ///   - panel: 目标面板窗口
    ///   - frame: 由调用方按各自锚定策略算好的目标 frame
    ///   - onComplete: 动画结束(且代际未过期)后执行的对账回调
    func animate(panel: NSPanel, to frame: CGRect, onComplete: @escaping () -> Void) {
        token += 1
        let current = token
        isAnimating = true
        let context = NSAnimationContext.current
        context.duration = MonitorConstants.panelExpansionDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrame(frame, display: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + MonitorConstants.panelExpansionDuration + 0.02) { [weak self] in
            guard let self, self.token == current else { return }
            self.isAnimating = false
            onComplete()
        }
    }
}
