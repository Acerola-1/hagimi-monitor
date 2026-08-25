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
/// 窗口目标高度用**增量式**预测:维护当前内容总高度(未封顶),toggle 时按
/// 「相位变化 × 该区自然高度」增减。不用「收起基线 + Σ(各区高度 × 相位)」的
/// 绝对式公式——嵌套展开区(显示器档案在分节内)的高度会被外层自然高度重复
/// 包含,且外层上报滞后于 toggle,绝对式在这两种情形下都会解出错误目标
/// (窗口与内容不同步,收尾靠对账瞬间跳回)。增量式只动被 toggle 的 key,
/// 与其他区的上报时机、嵌套层级完全解耦。稳态(非动画、未封顶)用实测值
/// 校准,消除增量累积误差。
///
/// 内容与窗口分走两条同时长同曲线(easeInOut 0.15s)的动画路径:内容由 SwiftUI
/// 动画系统插值,窗口由 CA 插值。两者端点对齐,中间帧曲线相近。
@MainActor
final class PanelExpansionDriver: ObservableObject {
    /// 各展开区当前目标相位(0=收起,1=展开)。非动画期间等于 0 或 1。
    /// 仅用于增量计算,不再驱动布局——布局由 SwiftUI 动画系统接管。
    private(set) var phase: [String: CGFloat] = [:]

    /// 各展开区内容的自然高度(CollapsibleDetail 上报),用于增量计算。
    private var naturalHeights: [String: CGFloat] = [:]
    /// 最近一次实测的内容总高度(面板内容 GeometryReader 上报)。
    private var lastMeasuredContentHeight: CGFloat = 0
    /// 内容总高度的当前预测值(未封顶)。稳态 = 实测;toggle 时按增量维护。
    private var predictedHeight: CGFloat = 0
    /// 展开/收起动画截止时刻。动画窗口内实测处于插值中间态,跳过稳态校准。
    private var animationDeadline: Date = .distantPast
    /// 内容总高度上限(菜单栏面板 = 屏幕可用高度,由视图上报;钉住面板为无穷)。
    /// 封顶期间 ScrollView 把实测钳在上限,无法反映未封顶真实高度,校准跳过、
    /// 保留增量维护的未封顶预测;下发窗口时才钳制,收起时正确「解封」。
    private var contentHeightCap: CGFloat = .infinity

    /// 窗口贴合回调:(目标内容总高度, 是否动画)。
    /// animated=true 时由 CoreAnimation 补间窗口 frame;false 时同步贴合。
    /// nil 时(预览/无窗口宿主)不贴合,不影响动画本身。
    var onWindowResize: ((CGFloat, Bool) -> Void)?

    /// 窗口目标高度 = 未封顶预测钳制在上限内。
    private var windowTargetHeight: CGFloat {
        min(max(predictedHeight, 0), contentHeightCap)
    }

    /// 把一批展开区动画到各自目标相位(0 或 1)。
    /// 相位瞬时设到目标(布局动画由 SwiftUI withAnimation 处理),
    /// 窗口目标高度一次性下发给窗口层做 CA 补间。
    func animate(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            for (key, target) in targets {
                NSLog("[autotest] driver.animate key=%@ target=%.0f nat=%.1f pred=%.1f",
                      key, target, naturalHeights[key] ?? -1, predictedHeight)
            }
        }
        applyPhaseDelta(targets)
        animationDeadline = Date().addingTimeInterval(MonitorConstants.panelExpansionDuration + 0.05)
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            NSLog("[autotest] driver.animate -> target=%.1f pred=%.1f cap=%.1f",
                  windowTargetHeight, predictedHeight, contentHeightCap)
        }
        onWindowResize?(windowTargetHeight, true)
        // 动画最后一帧的实测上报落在截止标记内、校准被跳过,此后不再有上报。
        // 过期后用终态实测补校一次,消除增量的累积误差(自然高度测量偏差等)。
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MonitorConstants.panelExpansionDuration + 0.06
        ) { [weak self] in
            self?.calibrateToMeasured()
        }
    }

    /// 瞬时把相位设到目标(无动画)。用于面板隐藏期/初始化阶段同步最终布局状态。
    func setInstantly(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        applyPhaseDelta(targets)
        animationDeadline = .distantPast
        onWindowResize?(windowTargetHeight, false)
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
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil,
           naturalHeights[key] != height {
            NSLog("[autotest] driver.natural key=%@ old=%.1f new=%.1f",
                  key, naturalHeights[key] ?? -1, height)
        }
        naturalHeights[key] = height
        calibrateToMeasured()
    }

    /// 面板内容 GeometryReader 上报实测总高度(稳态校准用)。
    func reportMeasuredContentHeight(_ height: CGFloat) {
        lastMeasuredContentHeight = height
        calibrateToMeasured()
    }

    /// 视图上报内容总高度上限(菜单栏下沿到屏幕底部的可用空间)。
    /// 上限变化(换屏/面板锚点移动)时随测高校报一起刷新即可。
    func reportContentHeightCap(_ cap: CGFloat) {
        contentHeightCap = cap
    }

    /// 相位增量应用:预测高度按各 key「相位变化 × 自然高度」增减。
    /// 嵌套展开区(显示器档案在分节内)的高度只在此处作为增量出现一次,
    /// 外层自然高度的滞后上报不影响本次预测。
    private func applyPhaseDelta(_ targets: [String: CGFloat]) {
        for (key, target) in targets {
            let old = phase[key] ?? 0
            predictedHeight += (target - old) * (naturalHeights[key] ?? 0)
            phase[key] = target
        }
    }

    /// 稳态校准:预测直接取实测,消除增量累积误差(自然高度测量偏差、
    /// 数据驱动的非动画高度变化等)。跳过两种不可信情形:
    /// 1. 动画窗口内:实测处于插值中间态;
    /// 2. 封顶态:未封顶预测已达上限,内容被 ScrollView 钳制,实测不反映真实
    ///    高度——判定必须看**预测**而非实测,展开动画的尾帧实测可能瞬时低于
    ///    上限(布局未完全钳制),据实测判定会把未封顶预测错误覆盖成中间态值,
    ///    之后所有收起的增量都基于污染基线,窗口收过头再靠对账瞬间弹回。
    private func calibrateToMeasured() {
        guard lastMeasuredContentHeight > 0 else { return }
        guard Date() >= animationDeadline else { return }
        guard predictedHeight < contentHeightCap - 0.5 else { return }
        guard lastMeasuredContentHeight < contentHeightCap - 0.5 else { return }
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil,
           abs(predictedHeight - lastMeasuredContentHeight) > 0.5 {
            NSLog("[autotest] driver.calibrate pred %.1f -> %.1f", predictedHeight, lastMeasuredContentHeight)
        }
        predictedHeight = lastMeasuredContentHeight
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
