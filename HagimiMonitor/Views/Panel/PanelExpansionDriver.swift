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
/// 窗口与内容同相的关键:内容高度的**可见**插值由 CoreAnimation 在合成器侧
/// 完成,布局模型在 toggle 时一次性落到终值,尺寸上报因此直接给出终高、没有
/// 逐帧中间值。窗口层拿到终高后以与内容**同参数**的阻尼弹簧(见
/// `PanelWindowSpring`)在显示帧时钟上跟随:同参、同起点、中断重定向同样保持
/// 速度,边框与内容全程同相。异参/异时长的一条独立补间(无论 CA 还是瞬时
/// 贴合)都会在中途或收尾暴露可见的分段跳变。
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
    /// 可取消的校准任务:快速连点时每次 toggle 都调度一次校准,
    /// 不取消会导致多个校准堆积、在弹簧尚未衰减时过早捕获中间态。
    private var calibrationWorkItem: DispatchWorkItem?
    /// 内容总高度上限(菜单栏面板 = 屏幕可用高度,由视图上报;钉住面板为无穷)。
    /// 封顶期间 ScrollView 把实测钳在上限,无法反映未封顶真实高度,校准跳过、
    /// 保留增量维护的未封顶预测;下发窗口时才钳制,收起时正确「解封」。
    private var contentHeightCap: CGFloat = .infinity

    /// 窗口贴合回调:(目标内容总高度, 是否动画)。
    /// animated=true(展开/收起):下发预测终高,窗口层以与内容同参数的弹簧跟随;
    /// animated=false(初始化/隐藏重置):窗口层直接贴合。
    /// nil 时(预览/无窗口宿主)不贴合,不影响动画本身。
    var onWindowResize: ((CGFloat, Bool) -> Void)?

    /// 窗口目标高度 = 未封顶预测钳制在上限内。
    private var windowTargetHeight: CGFloat {
        min(max(predictedHeight, 0), contentHeightCap)
    }

    /// 把一批展开区动画到各自目标相位(0 或 1)。
    /// 相位瞬时设到目标(布局动画由 SwiftUI withAnimation 处理),
    /// 窗口目标高度一次性下发给窗口层:窗口以与内容同参数的弹簧跟随。
    func animate(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            for (key, target) in targets {
                NSLog("[autotest] driver.animate key=%@ target=%.0f nat=%.1f pred=%.1f",
                      key, target, naturalHeights[key] ?? -1, predictedHeight)
            }
        }
        applyPhaseDelta(targets)
        animationDeadline = Date().addingTimeInterval(MonitorConstants.panelExpansionSettleTime)
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            NSLog("[autotest] driver.animate -> target=%.1f pred=%.1f cap=%.1f",
                  windowTargetHeight, predictedHeight, contentHeightCap)
        }
        onWindowResize?(windowTargetHeight, true)
        // 取消前一次校准(快速连点时避免多个堆积),弹簧衰减后再做一次终态校准。
        calibrationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.calibrateToMeasured()
        }
        calibrationWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MonitorConstants.panelExpansionSettleTime + 0.05,
            execute: item
        )
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

/// 窗口高度弹簧跟随器:窗口 frame 以与内容侧完全相同的弹簧参数跟随内容高度。
///
/// 内容高度的可见插值由 CoreAnimation 在合成器侧完成,布局模型在 toggle 时
/// 一次性落到终值,尺寸上报直接把终值交给窗口层;此处以同参数
/// (`panelExpansionSpringResponse` / `panelExpansionSpringDamping`)的欠阻尼
/// 弹簧在显示帧时钟上向该终值运动,与内容可见运动同参同起点,全程同相。
/// 位置取闭式解(不做数值积分),帧率无关、无累积误差;重定向时保留当前
/// 位置与速度,与 SwiftUI 弹簧的中断行为同构,快速连点不重启不顿挫。
@MainActor
final class PanelWindowSpring: NSObject {
    private let applyHeight: (CGFloat) -> Void
    private let currentScreen: () -> NSScreen?

    private var displayLink: CADisplayLink?
    private(set) var isAnimating = false
    private var target: CGFloat = 0
    private var startPos: CGFloat = 0
    private var startVel: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    /// 弹簧衰减到目标后调用一次(动画正常收尾),供窗口层对账实际内容尺寸。
    private var onSettle: (() -> Void)?

    private static let omega = 2 * Double.pi / MonitorConstants.panelExpansionSpringResponse
    private static let zetaOmega = MonitorConstants.panelExpansionSpringDamping * omega
    private static let dampedOmega = omega * (1 - pow(MonitorConstants.panelExpansionSpringDamping, 2)).squareRoot()

    init(applyHeight: @escaping (CGFloat) -> Void, screen: @escaping () -> NSScreen?) {
        self.applyHeight = applyHeight
        self.currentScreen = screen
    }

    deinit {
        displayLink?.invalidate()
    }

    /// 向新目标启动/续接弹簧。静止时从窗口当前高度出发;动画中重定向则取
    /// 轨迹瞬时位置与速度续接(与内容弹簧的中断重定向同构)。
    /// `onSettle` 在弹簧收敛到目标后调用一次,供窗口层对账实际内容尺寸。
    func retarget(to height: CGFloat, from current: CGFloat, onSettle: (() -> Void)? = nil) {
        let now = CACurrentMediaTime()
        if isAnimating {
            let s = now - startTime
            startPos = position(at: s)
            startVel = velocity(at: s)
        } else {
            startPos = current
            startVel = 0
        }
        target = height
        startTime = now
        self.onSettle = onSettle
        guard abs(startPos - target) > 0.5 else {
            stop()
            applyHeight(target)
            fireSettle()
            return
        }
        isAnimating = true
        ensureDisplayLink()
    }

    /// 停止弹簧并瞬时贴合(初始化/隐藏重置/非动画尺寸变化)。
    func setInstantly(to height: CGFloat) {
        stop()
        applyHeight(height)
    }

    /// 停止弹簧、不再贴合(面板重新呼出前清场,让重定位接管)。
    func cancel() {
        stop()
    }

    private func stop() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        guard let screen = currentScreen() ?? NSScreen.main else {
            stop()
            applyHeight(target)
            fireSettle()
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let s = link.targetTimestamp - startTime
        guard s > 0 else { return }
        let x = position(at: s)
        let v = velocity(at: s)
        if abs(x - target) < 0.25, abs(v) < 2 {
            stop()
            applyHeight(target)
            fireSettle()
            return
        }
        if s > 2 {
            stop()
            applyHeight(target)
            fireSettle()
            return
        }
        applyHeight(x)
    }

    private func fireSettle() {
        let settle = onSettle
        onSettle = nil
        settle?()
    }

    /// 欠阻尼弹簧闭式解:x = T + e^{-ζωs}(A·cos ω_d·s + B·sin ω_d·s)。
    private func position(at s: CFTimeInterval) -> CGFloat {
        let a = startPos - target
        let b = (startVel + Self.zetaOmega * a) / Self.dampedOmega
        let phase = Self.dampedOmega * s
        return target + exp(-Self.zetaOmega * s) * (a * cos(phase) + b * sin(phase))
    }

    private func velocity(at s: CFTimeInterval) -> CGFloat {
        let a = startPos - target
        let b = (startVel + Self.zetaOmega * a) / Self.dampedOmega
        let phase = Self.dampedOmega * s
        let cosP = cos(phase), sinP = sin(phase)
        let decay = exp(-Self.zetaOmega * s)
        return decay * (-Self.zetaOmega * (a * cosP + b * sinP)
                        + (-a * Self.dampedOmega * sinP + b * Self.dampedOmega * cosP))
    }
}
