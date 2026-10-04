import AppKit
import Combine
import SwiftUI
import QuartzCore

final class NativePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if NativePanelMotionMode.diagnostics {
            NSLog("[panel-window] width=%.1f height=%.1f", frameRect.width, frameRect.height)
        }
        super.setFrame(frameRect, display: flag)
    }
}

/// 独立 SwiftUI 宿主共享窗口左上角坐标，避免各自的 .global 原点用于排序。
@MainActor enum NativePanelCoordinates {
    static func frame(of view: NSView) -> CGRect? {
        guard let root = view.window?.contentView else { return nil }
        var rect = view.convert(view.bounds, to: root)
        if !root.isFlipped { rect.origin.y = root.bounds.height - rect.maxY }
        return rect
    }
    static func pointer(in view: NSView) -> CGPoint? {
        guard let window = view.window, let root = window.contentView else { return nil }
        var point = root.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if !root.isFlipped { point.y = root.bounds.height - point.y }
        return point
    }
}

private struct NativePanelExpansionKey: EnvironmentKey {
    static var defaultValue: PanelExpansionDriver? { nil }
}
extension EnvironmentValues {
    var nativePanelExpansion: PanelExpansionDriver? {
        get { self[NativePanelExpansionKey.self] }
        set { self[NativePanelExpansionKey.self] = newValue }
    }
    var nativePanelOwnsCardBackdrop: Bool {
        get { self[NativePanelBackdropKey.self] }
        set { self[NativePanelBackdropKey.self] = newValue }
    }
}
private struct NativePanelBackdropKey: EnvironmentKey { static let defaultValue = false }

/// 新宿主只继承公开的产品环境；不把父 ViewGraph 的私有可见性/布局环境复制过去。
private struct NativePanelEnvironmentBridge: ViewModifier {
    let values: EnvironmentValues
    @ViewBuilder func body(content: Content) -> some View {
        let base = content
            .environment(\.locale, values.locale)
            .environment(\.colorScheme, values.colorScheme)
            .environment(\.dynamicTypeSize, values.dynamicTypeSize)
            .environment(\.displayScale, values.displayScale)
            .environment(\.font, values.font)
            .environment(\.panelReorderController, values.panelReorderController)
            .environment(\.panelReorderSettings, values.panelReorderSettings)
            .environment(\.fluidOpenSettings, values.fluidOpenSettings)
            .environment(\.panelMaxContentHeight, values.panelMaxContentHeight)
            .environment(\.nativePanelContentWidth, values.nativePanelContentWidth)
            .environment(\.nativePanelExpansion, values.nativePanelExpansion)
            .environment(\.nativePanelOwnsCardBackdrop, values.nativePanelOwnsCardBackdrop)
        if let expansion = values.nativePanelExpansion { base.environmentObject(expansion) }
        else { base }
    }
}

@MainActor
private func nativeAnimate(_ layer: CALayer, key: String, values: [Any], plan: NativePanelAnimationPlan) {
    guard let last = values.last else { return }
    layer.removeAnimation(forKey: "panel." + key)
    layer.setValue(last, forKeyPath: key)
    guard plan.duration > 0, CACurrentMediaTime() < plan.startTime + plan.duration else { return }
    let animation = CAKeyframeAnimation(keyPath: key)
    animation.values = values
    animation.keyTimes = plan.samples.map { NSNumber(value: ($0.frame.sampleTime - plan.startTime) / plan.duration) }
    animation.duration = plan.duration
    animation.beginTime = layer.convertTime(plan.startTime, from: nil)
    animation.calculationMode = .linear
    layer.add(animation, forKey: "panel." + key)
}

@MainActor
private func nativeFreeze(_ layer: CALayer, keys: [String]) {
    if let presentation = layer.presentation() {
        for key in keys { layer.setValue(presentation.value(forKeyPath: key), forKeyPath: key) }
    }
    layer.removeAllAnimations()
}

class NativePanelFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class NativePanelContentHost: NativePanelFlippedView {
    let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    private(set) var backdrop: NativePanelCardBackdropView?
    let maskShape = CAShapeLayer()
    var visibleHeight: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var allocatedHeight: CGFloat = 0
    var minimumAllocatedHeight: CGFloat = 0
    var appliedGeneration: UInt?
    fileprivate var contentVersion: NativePanelContentVersion?
    fileprivate var contentEnvironment: NativePanelHostEnvironment?
    fileprivate var needsNaturalMeasurement = true
    fileprivate var measuredWidth: CGFloat?
    fileprivate var naturalHeight: CGFloat = 1
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.anchorPoint = .zero
        layer?.mask = maskShape
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        addSubview(hosting)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func measure(width: CGFloat) -> CGFloat {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let previousAllocation = frame.size
        hosting.frame.size.width = width
        hosting.layoutSubtreeIfNeeded()
        let height = max(1, hosting.fittingSize.height)
        allocatedHeight = max(allocatedHeight, height, minimumAllocatedHeight)
        // 分页内容的承载容量与自然高度分离，揭示仍使用真实页面尺寸。
        let contentHeight = minimumAllocatedHeight > 0 ? allocatedHeight : height
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        frame.size = CGSize(width: width, height: allocatedHeight)
        if frame.size != previousAllocation && minimumAllocatedHeight == 0 { appliedGeneration = nil }
        backdrop?.frame = bounds
        maskShape.frame = bounds
        measuredWidth = width
        naturalHeight = height
        needsNaturalMeasurement = false
        return height
    }

    func updateBackdrop(id: String, palette: MonitorPalette, enabled: Bool) {
        guard enabled else {
            backdrop?.removeFromSuperview()
            backdrop = nil
            return
        }
        let view = backdrop ?? NativePanelCardBackdropView()
        if backdrop == nil {
            backdrop = view
            addSubview(view, positioned: .below, relativeTo: hosting)
            view.frame = bounds
        }
        view.update(kind: MonitorKind(rawValue: id), palette: palette)
    }
    func contour(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: rect.width, height: max(0, rect.height))),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let path = (maskShape.presentation() as? CAShapeLayer)?.path ?? maskShape.path
        guard path?.contains(local) == true else { return nil }
        return super.hitTest(point)
    }
}

/// 完整自然尺寸的宿主列表，位置和外壳揭示由共享轨迹提交。
private class NativePanelNodeGroup: NativePanelFlippedView, NativePanelLayerRenderer {
    let motion: SingleHostMotionCoordinator
    let owner: String
    var ids: [String] = []
    var nodes: [String: NativePanelContentHost] = [:]
    var group: PanelChildGroup
    var isTopLevel: Bool
    var registration: UUID?
    var naturalHeight: CGFloat = 1
    var width: CGFloat = 1
    var updateTicket: UInt = 0
    var isMounted = true
    private var measurementScheduled = false
    var preferenceValues: [String: [String: CGSize]] = [:]
    var preferenceGroups: [String: [String: PanelChildGroup]] = [:]
    init(motion: SingleHostMotionCoordinator, owner: String, group: PanelChildGroup, topLevel: Bool) {
        self.motion = motion; self.owner = owner; self.group = group; self.isTopLevel = topLevel
        super.init(frame: .zero)
        wantsLayer = true
        registration = motion.nativeLayer.register(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(ids: [String], content: [AnyView], environment: EnvironmentValues, width: CGFloat,
                versions: [NativePanelContentVersion?] = []) {
        updateTicket &+= 1
        let ticket = updateTicket
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isMounted, ticket == self.updateTicket else { return }
            self.updateContents(ids: ids, content: content, environment: environment, width: width, versions: versions)
        }
    }

    private func updateContents(ids: [String], content: [AnyView], environment: EnvironmentValues, width: CGFloat,
                                versions: [NativePanelContentVersion?]) {
        self.ids = ids; self.width = width
        for id in Set(nodes.keys).subtracting(ids) {
            nodes.removeValue(forKey: id)?.removeFromSuperview()
            preferenceValues.removeValue(forKey: id); preferenceGroups.removeValue(forKey: id)
        }
        for (index, id) in ids.enumerated() {
            guard index < content.count else { continue }
            let node = nodes[id] ?? NativePanelContentHost()
            if nodes[id] == nil { nodes[id] = node; addSubview(node) }
            if isTopLevel && id == MonitorKind.battery.id {
                // 电源页面高度可反复变化，按当前屏幕容量预留一次，换页不重分配承载层。
                let cap = environment.panelMaxContentHeight
                node.minimumAllocatedHeight = max(0, cap.isFinite ? cap
                    : motion.submissionAdapter?.currentScreen()?.visibleFrame.height ?? 0)
            }
            node.cornerRadius = isTopLevel && id != "__footer__" ? MonitorConstants.rowCornerRadius : 0
            var env = environment
            // 子宿主继承扣除本层内衬后的宽度，避免控件更新与 sizeThatFits 往返改宽。
            env.nativePanelContentWidth = max(1, width - group.leading - group.trailing)
            env.nativePanelOwnsCardBackdrop = isTopLevel && id != "__footer__"
            node.updateBackdrop(id: id, palette: MonitorPalette(
                preference: environment.panelReorderSettings?.colorSchemePreference ?? .balanced,
                colorScheme: environment.colorScheme), enabled: env.nativePanelOwnsCardBackdrop)
            let version = index < versions.count ? versions[index] : nil
            let hostEnvironment = NativePanelHostEnvironment(env)
            // 只对有完整值语义的内容去重；未登记的嵌套内容继续正常提交。
            if let version, let previous = node.contentVersion,
               previous == version, node.contentEnvironment == hostEnvironment { continue }
            node.contentVersion = version
            node.contentEnvironment = hostEnvironment
            node.needsNaturalMeasurement = true
            let view = content[index]
                .modifier(NativePanelEnvironmentBridge(values: env))
                // 自然高度回报前仍承载旧尺寸，内容始终从顶部排版。
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onPreferenceChange(PanelNaturalMeasurements.self) { [weak self] values in
                    Task { @MainActor in self?.receive(id: id, values: values) }
                }
                .onPreferenceChange(PanelChildGroups.self) { [weak self] groups in
                    Task { @MainActor in self?.receive(id: id, groups: groups) }
                }
            node.hosting.rootView = AnyView(view)
        }
        measureContents()
        report()
        if let plan = motion.nativeLayer.plan { applyNativePlan(plan) }
    }

    func receive(id: String, values: [String: CGSize]) {
        guard isMounted, nodes[id] != nil else { return }
        guard preferenceValues[id] != values else { return }
        preferenceValues[id] = values
        nodes[id]?.needsNaturalMeasurement = true
        scheduleMeasurement()
    }
    func receive(id: String, groups: [String: PanelChildGroup]) {
        guard isMounted, nodes[id] != nil else { return }
        guard preferenceGroups[id] != groups else { return }
        preferenceGroups[id] = groups
        report()
    }
    func scheduleMeasurement() {
        guard isMounted, !measurementScheduled else { return }
        measurementScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementScheduled = false
            guard self.isMounted else { return }
            self.measureContents()
            self.report()
        }
    }
    func report() {
        guard isMounted else { return }
        var values = preferenceValues.values.reduce(into: [String: CGSize]()) { $0.merge($1) { _, new in new } }
        if let footer = nodes["__footer__"] {
            values["__footer__"] = CGSize(width: width, height: footer.frame.height)
        }
        let groups = preferenceGroups.values.reduce(into: [String: PanelChildGroup]()) { $0.merge($1) { _, new in new } }
        motion.nativeLayer.report(owner: owner, values: values, groups: groups)
    }
    func measureContents() {
        guard isMounted else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let previousSize = intrinsicContentSize
        var y = group.top
        for (index, id) in ids.enumerated() {
            guard let node = nodes[id] else { continue }
            if index > 0 { y += group.spacing }
            let contentWidth = max(1, width - group.leading - group.trailing)
            let h: CGFloat
            if node.needsNaturalMeasurement || node.measuredWidth != contentWidth {
                if NativePanelMotionMode.diagnostics { PanelLayoutCounters.shared.measure("native-host:" + id) }
                h = node.measure(width: contentWidth)
            } else { h = node.naturalHeight }
            if motion.nativeLayer.snapshot == nil { node.frame.origin = CGPoint(x: group.leading, y: y) }
            y += h
        }
        naturalHeight = max(1, y + group.bottom)
        frame.size = CGSize(width: width, height: max(frame.height, naturalHeight))
        if intrinsicContentSize != previousSize { invalidateIntrinsicContentSize() }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: width, height: naturalHeight) }

    func applyNativePlan(_ plan: NativePanelAnimationPlan) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (id, node) in nodes {
            guard node.appliedGeneration != plan.generation else { continue }
            let frames = plan.samples.compactMap { isTopLevel ? $0.frame.cardFrames[id] : $0.frame.childFrames[id] }
            guard frames.count == plan.samples.count, let final = frames.last, let layer = node.layer else { continue }
            node.appliedGeneration = plan.generation
            node.frame.origin = final.origin
            nativeAnimate(layer, key: "position.x", values: frames.map { $0.minX }, plan: plan)
            nativeAnimate(layer, key: "position.y", values: frames.map { $0.minY }, plan: plan)
            nativeAnimate(node.maskShape, key: "path", values: frames.map { node.contour($0) }, plan: plan)
            node.visibleHeight = final.height
        }
        CATransaction.commit()
    }
    func stopNativeMotion() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for node in nodes.values {
            node.appliedGeneration = nil
            if let layer = node.layer {
                node.frame.origin = layer.presentation()?.position ?? layer.position
                layer.removeAllAnimations()
            }
            nativeFreeze(node.maskShape, keys: ["path"])
        }
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard let sample = motion.nativeLayer.sample(at: CACurrentMediaTime()) else { return super.hitTest(point) }
        for id in ids.reversed() {
            guard let node = nodes[id], var rect = isTopLevel ? sample.frame.cardFrames[id] : sample.frame.childFrames[id] else { continue }
            rect.origin = node.layer?.presentation()?.position ?? rect.origin
            guard rect.contains(local) else { continue }
            let mapped = CGPoint(x: node.frame.minX + local.x - rect.minX, y: node.frame.minY + local.y - rect.minY)
            if let view = node.hitTest(mapped) { return view }
        }
        return nil
    }
}

private struct NativePanelGroupRepresentable: NSViewRepresentable {
    let motion: SingleHostMotionCoordinator
    let owner: String
    let ids: [String]
    let views: [AnyView]
    let group: PanelChildGroup
    func makeNSView(context: Context) -> NativePanelNodeGroup {
        NativePanelNodeGroup(motion: motion, owner: owner, group: group, topLevel: false)
    }
    func updateNSView(_ view: NativePanelNodeGroup, context: Context) {
        view.group = group
        let width = motion.nativeLayer.snapshot?.width(for: owner) ?? max(1, context.environment.nativePanelContentWidth)
        view.update(ids: ids, content: views, environment: context.environment, width: width)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativePanelNodeGroup, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.width
        if nsView.width != width {
            nsView.width = width
            nsView.scheduleMeasurement()
        }
        return CGSize(width: width, height: nsView.naturalHeight)
    }
    static func dismantleNSView(_ view: NativePanelNodeGroup, coordinator: ()) {
        view.isMounted = false; view.updateTicket &+= 1
        view.stopNativeMotion()
        if let key = view.registration { view.motion.nativeLayer.unregister(key, owner: view.owner) }
    }
}

private struct NativePanelContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = MonitorConstants.panelIdealWidth - 12
}
extension EnvironmentValues {
    var nativePanelContentWidth: CGFloat {
        get { self[NativePanelContentWidthKey.self] }
        set { self[NativePanelContentWidthKey.self] = newValue }
    }
}

struct NativePanelContentItem: Identifiable {
    let id: String
    let content: AnyView
    let version: NativePanelContentVersion?

    init(id: String, content: AnyView) {
        self.id = id
        self.content = content
        version = nil
    }

    init<Content: View & Equatable>(id: String, content: Content) {
        self.id = id
        self.content = AnyView(content.equatable())
        version = NativePanelContentVersion(content)
    }
}

/// 保留组件已有的值比较合同；闭包与局部状态仍由稳定 ID 的宿主拥有。
struct NativePanelContentVersion: Equatable {
    private let value: Any
    private let equals: (Any) -> Bool

    init<Value: Equatable>(_ value: Value) {
        self.value = value
        equals = { ($0 as? Value).map { value == $0 } ?? false }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.equals(rhs.value) }
}

/// 与独立宿主实际继承的排版和产品环境一一对应，环境变化不能被内容去重遮蔽。
fileprivate struct NativePanelHostEnvironment: Equatable {
    let locale: Locale
    let scheme: ColorScheme
    let typeSize: DynamicTypeSize
    let scale: CGFloat
    let font: Font?
    let cap: CGFloat
    let width: CGFloat
    let ownsBackdrop: Bool
    let reorder: ObjectIdentifier?
    let settings: ObjectIdentifier?
    let expansion: ObjectIdentifier?

    init(_ values: EnvironmentValues) {
        locale = values.locale; scheme = values.colorScheme
        typeSize = values.dynamicTypeSize; scale = values.displayScale; font = values.font
        cap = values.panelMaxContentHeight; width = values.nativePanelContentWidth
        ownsBackdrop = values.nativePanelOwnsCardBackdrop
        reorder = values.panelReorderController.map(ObjectIdentifier.init)
        settings = values.panelReorderSettings.map(ObjectIdentifier.init)
        expansion = values.nativePanelExpansion.map(ObjectIdentifier.init)
    }
}

private final class NativePanelRotationHost: NativePanelFlippedView, NativePanelLayerRenderer {
    let motion: SingleHostMotionCoordinator
    let id: String
    let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    var collapsed: Double = 0
    var expanded: Double = 90
    var measuredSize = CGSize(width: 12, height: 12)
    var registration: UUID?
    var updateTicket: UInt = 0
    private var rotationBounds = CGRect.zero
    init(motion: SingleHostMotionCoordinator, id: String) {
        self.motion = motion; self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        hosting.wantsLayer = true; hosting.sizingOptions = [.intrinsicContentSize]
        addSubview(hosting)
        registration = motion.nativeLayer.register(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { measuredSize }
    override func layout() {
        super.layout()
        hosting.frame = bounds
        if rotationBounds != bounds {
            rotationBounds = bounds
            if let plan = motion.nativeLayer.plan { applyNativePlan(plan) }
        }
    }
    func update(content: AnyView, environment: EnvironmentValues, collapsed: Double, expanded: Double) {
        updateTicket &+= 1; let ticket = updateTicket
        DispatchQueue.main.async { [weak self] in
            guard let self, ticket == self.updateTicket else { return }
            self.collapsed = collapsed; self.expanded = expanded
            self.hosting.rootView = AnyView(content.modifier(NativePanelEnvironmentBridge(values: environment)))
            self.hosting.layoutSubtreeIfNeeded()
            self.measuredSize = self.hosting.fittingSize
            self.invalidateIntrinsicContentSize()
            if let plan = self.motion.nativeLayer.plan { self.applyNativePlan(plan) }
        }
    }
    func applyNativePlan(_ plan: NativePanelAnimationPlan) {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // AppKit 的宿主图层锚点在原点；显式绕内容中心转动，避免角标旋出自己的布局框。
        let center = CGPoint(x: bounds.midX - layer.bounds.width * layer.anchorPoint.x,
                             y: bounds.midY - layer.bounds.height * layer.anchorPoint.y)
        nativeAnimate(layer, key: "sublayerTransform", values: plan.samples.map {
            let angle = (collapsed + (expanded - collapsed) * Double($0.phases[id] ?? 0)) * .pi / 180
            var transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            transform.m41 = center.x * (1 - cos(angle)) + center.y * sin(angle)
            transform.m42 = center.y * (1 - cos(angle)) - center.x * sin(angle)
            return NSValue(caTransform3D: transform)
        }, plan: plan)
        CATransaction.commit()
    }
    func stopNativeMotion() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let layer { nativeFreeze(layer, keys: ["sublayerTransform"]) }
        CATransaction.commit()
    }
}

struct NativePanelRotationView: NSViewRepresentable {
    let motion: SingleHostMotionCoordinator
    let id: String
    let collapsed: Double
    let expanded: Double
    let content: AnyView
    func makeNSView(context: Context) -> NSView { NativePanelRotationHost(motion: motion, id: id) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? NativePanelRotationHost)?.update(content: content, environment: context.environment, collapsed: collapsed, expanded: expanded)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        guard let node = view as? NativePanelRotationHost else { return }
        node.updateTicket &+= 1
        if let key = node.registration { node.motion.nativeLayer.unregister(key, owner: "rotation:" + node.id) }
    }
}

struct NativePanelChildren: View {
    let id: String
    let isExpanded: Bool
    let group: PanelChildGroup
    let motion: SingleHostMotionCoordinator
    let items: [NativePanelContentItem]
    var body: some View {
        NativePanelGroupRepresentable(motion: motion, owner: id, ids: items.map(\.id),
            views: items.map(\.content), group: group)
        .background {
            Color.clear.preference(key: PanelChildGroups.self, value: [id: group])
                .preference(key: PanelNaturalMeasurements.self, value: [
                    "detail:" + id: .zero, "available:" + id: CGSize(width: group.ids.isEmpty ? 0 : 1, height: 0)])
        }
        .accessibilityHidden(!isExpanded)
    }
}

private final class NativePanelReplacementView: NativePanelFlippedView, NativePanelLayerRenderer {
    let motion: SingleHostMotionCoordinator
    let id: String
    let collapsed = NSHostingView(rootView: AnyView(EmptyView()))
    let expanded = NSHostingView(rootView: AnyView(EmptyView()))
    var registration: UUID?
    var values: [String: CGSize] = [:]
    var contentWidth: CGFloat = 1
    var naturalHeight: CGFloat = 1
    var updateTicket: UInt = 0
    var isMounted = true
    private var showsArchive = false
    private var appliedGeneration: UInt?
    init(motion: SingleHostMotionCoordinator, id: String) {
        self.motion = motion; self.id = id
        super.init(frame: .zero)
        for host in [collapsed, expanded] {
            host.sizingOptions = [.intrinsicContentSize]; host.wantsLayer = true; addSubview(host)
        }
        registration = motion.nativeLayer.register(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: contentWidth, height: naturalHeight) }
    func update(collapsed content: AnyView, expanded archive: AnyView, isExpanded: Bool,
                environment: EnvironmentValues, width: CGFloat) {
        updateTicket &+= 1
        let ticket = updateTicket
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isMounted, ticket == self.updateTicket else { return }
            self.updateContents(collapsed: content, expanded: archive, isExpanded: isExpanded, environment: environment, width: width)
        }
    }
    private func updateContents(collapsed content: AnyView, expanded archive: AnyView, isExpanded: Bool,
                environment: EnvironmentValues, width: CGFloat) {
        showsArchive = isExpanded
        contentWidth = width
        collapsed.rootView = AnyView(content.modifier(NativePanelEnvironmentBridge(values: environment))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(!isExpanded).accessibilityHidden(isExpanded))
        expanded.rootView = AnyView(archive.modifier(NativePanelEnvironmentBridge(values: environment))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(isExpanded).accessibilityHidden(!isExpanded))
        measure(width: width)
        if let plan = motion.nativeLayer.plan { applyNativePlan(plan) }
    }
    func measure(width: CGFloat) {
        guard isMounted else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let previousSize = intrinsicContentSize
        contentWidth = width
        var sizes: [CGFloat] = []
        for host in [collapsed, expanded] {
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            let height = max(1, host.fittingSize.height)
            host.frame = CGRect(x: 0, y: 0, width: width, height: height)
            sizes.append(height)
        }
        naturalHeight = sizes.max() ?? 1
        frame.size = CGSize(width: width, height: naturalHeight)
        motion.nativeLayer.report(owner: "replacement:" + id, values: [
            "collapsed:" + id: CGSize(width: width, height: sizes[0]),
            "detail:" + id: CGSize(width: width, height: sizes[1])])
        if intrinsicContentSize != previousSize { invalidateIntrinsicContentSize() }
    }
    func applyNativePlan(_ plan: NativePanelAnimationPlan) {
        guard appliedGeneration != plan.generation else { return }
        appliedGeneration = plan.generation
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let phases = plan.samples.map { Double($0.phases[id] ?? 0) }
        nativeAnimate(collapsed.layer!, key: "opacity", values: phases.map { 1 - $0 }, plan: plan)
        nativeAnimate(expanded.layer!, key: "opacity", values: phases, plan: plan)
        CATransaction.commit()
    }
    func stopNativeMotion() {
        appliedGeneration = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let layer = collapsed.layer { nativeFreeze(layer, keys: ["opacity"]) }
        if let layer = expanded.layer { nativeFreeze(layer, keys: ["opacity"]) }
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 两页保留自然尺寸供高度换版；透明的另一页不参与 AppKit 命中。
        let local = convert(point, from: superview)
        let active = showsArchive ? expanded : collapsed
        return active.hitTest(local)
    }
}

private struct NativePanelReplacementRepresentable: NSViewRepresentable {
    let motion: SingleHostMotionCoordinator
    let id: String
    let isExpanded: Bool
    let collapsed: AnyView
    let expanded: AnyView
    func makeNSView(context: Context) -> NativePanelReplacementView { NativePanelReplacementView(motion: motion, id: id) }
    func updateNSView(_ view: NativePanelReplacementView, context: Context) {
        view.update(collapsed: collapsed, expanded: expanded, isExpanded: isExpanded,
            environment: context.environment, width: context.environment.nativePanelContentWidth)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativePanelReplacementView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.contentWidth
        if width != nsView.contentWidth {
            nsView.contentWidth = width
            DispatchQueue.main.async { [weak nsView] in nsView?.measure(width: width) }
        }
        return CGSize(width: width, height: nsView.naturalHeight)
    }
    static func dismantleNSView(_ view: NativePanelReplacementView, coordinator: ()) {
        view.isMounted = false; view.updateTicket &+= 1
        view.stopNativeMotion()
        if let key = view.registration { view.motion.nativeLayer.unregister(key, owner: "replacement:" + view.id) }
    }
}

struct NativePanelReplacement<Collapsed: View, Expanded: View>: View {
    let id: String
    let isExpanded: Bool
    let motion: SingleHostMotionCoordinator
    let collapsed: Collapsed
    let expanded: Expanded
    var body: some View {
        NativePanelReplacementRepresentable(motion: motion, id: id, isExpanded: isExpanded,
            collapsed: AnyView(collapsed), expanded: AnyView(expanded))
            .background { Color.clear.preference(key: PanelNaturalMeasurements.self,
                value: ["available:" + id: CGSize(width: 1, height: 0)]) }
    }
}

private final class NativePanelClipView: NSClipView {
    weak var nativeMotion: NativePanelLayerMotion?
    var isApplyingNativePlan = false
    override var isFlipped: Bool { true }
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        if !isApplyingNativePlan, let frame = nativeMotion?.sample(at: CACurrentMediaTime())?.frame {
            result.origin.y = PanelScrollCoordinator.clampUserOffset(offset: proposedBounds.origin.y, frame: frame)
        }
        return result
    }
    override func scroll(to newOrigin: NSPoint) {
        var point = newOrigin
        if !isApplyingNativePlan, let frame = nativeMotion?.sample(at: CACurrentMediaTime())?.frame {
            point.y = PanelScrollCoordinator.clampUserOffset(offset: point.y, frame: frame)
        }
        super.scroll(to: point)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let visibleOffset = layer?.presentation()?.bounds.origin.y ?? bounds.origin.y
        return super.hitTest(CGPoint(x: point.x, y: point.y + visibleOffset - bounds.origin.y))
    }
}

private final class NativePanelScrollView: NSScrollView {
    weak var nativeMotion: NativePanelLayerMotion?
    var onOffsetChanged: (() -> Void)?
    private var scrollEndWork: DispatchWorkItem?
    override func scrollWheel(with event: NSEvent) {
        guard let motion = nativeMotion else { super.scrollWheel(with: event); return }
        if !motion.isUserScrolling {
            let offset = contentView.layer?.presentation()?.bounds.origin.y
                ?? motion.sample(at: CACurrentMediaTime())?.frame.scrollOffset ?? contentView.bounds.origin.y
            contentView.layer?.removeAnimation(forKey: "panel.bounds.origin.y")
            contentView.setBoundsOrigin(CGPoint(x: 0, y: offset))
            motion.userScrollBegan(at: offset)
        }
        super.scrollWheel(with: event)
        motion.updateUserScroll(contentView.bounds.origin.y)
        if let frame = motion.sample(at: CACurrentMediaTime())?.frame {
            contentView.scroll(to: CGPoint(x: 0, y: frame.scrollOffset))
        }
        onOffsetChanged?()
        scrollEndWork?.cancel(); scrollEndWork = nil
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            motion.userScrollEnded(at: contentView.bounds.origin.y)
        } else {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.nativeMotion?.userScrollEnded(at: self.contentView.bounds.origin.y)
                self.scrollEndWork = nil
            }
            scrollEndWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
    }
    func stopInteraction() { scrollEndWork?.cancel(); scrollEndWork = nil }
}

/// 容量窗口内部的可见底座，标题、主体与轮廓由同一计划定位。
final class NativePanelSurface: NativePanelFlippedView, NativePanelLayerRenderer {
    let motion: SingleHostMotionCoordinator
    let header = NSHostingView(rootView: AnyView(EmptyView()))
    let footer = NSHostingView(rootView: AnyView(EmptyView()))
    let surface = NativePanelFlippedView()
    let effect = NSVisualEffectView()
    let tint = CALayer()
    let maskShape = CAShapeLayer()
    let outline = CAShapeLayer()
    let contourShadow = CALayer()
    let viewportMask = CAGradientLayer()
    fileprivate let scroll = NativePanelScrollView()
    fileprivate let clip = NativePanelClipView()
    fileprivate let document: NativePanelNodeGroup
    var registration: UUID?
    var localMonitor: Any?
    var globalMonitor: Any?
    var boundaryWork: DispatchWorkItem?
    var edgeScrollWork: DispatchWorkItem?
    weak var reorderController: PanelReorderController?
    var reorderSubscriptions: [AnyCancellable] = []
    var isDragging = false
    var capacity: CGFloat = 800
    var updateTicket: UInt = 0
    let inset = MonitorConstants.panelNativeShadowInset

    init(motion: SingleHostMotionCoordinator) {
        self.motion = motion
        document = NativePanelNodeGroup(motion: motion, owner: "__root__", group: PanelChildGroup(ids: [], leading: 0), topLevel: true)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(contourShadow)
        addSubview(surface)
        surface.wantsLayer = true
        surface.layer?.mask = maskShape
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true
        surface.addSubview(effect)
        effect.layer?.addSublayer(tint)
        header.sizingOptions = [.intrinsicContentSize]
        surface.addSubview(header)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        clip.drawsBackground = false; clip.nativeMotion = motion.nativeLayer; clip.wantsLayer = true
        scroll.contentView = clip; scroll.documentView = document; scroll.nativeMotion = motion.nativeLayer
        scroll.wantsLayer = true; scroll.layer?.mask = viewportMask
        scroll.onOffsetChanged = { [weak self] in self?.updateScrollFade() }
        surface.addSubview(scroll)
        footer.sizingOptions = [.intrinsicContentSize]
        footer.wantsLayer = true
        footer.layer?.anchorPoint = .zero
        surface.addSubview(footer)
        layer?.addSublayer(outline)
        outline.fillColor = NSColor.clear.cgColor
        outline.lineWidth = 0.5
        contourShadow.shadowColor = NSColor.black.cgColor; contourShadow.shadowRadius = 8; contourShadow.shadowOffset = CGSize(width: 0, height: -2)
        registration = motion.nativeLayer.register(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(header content: AnyView, ids: [String], views: [AnyView], environment: EnvironmentValues, cap: CGFloat,
                versions: [NativePanelContentVersion?] = []) {
        updateTicket &+= 1
        let ticket = updateTicket
        DispatchQueue.main.async { [weak self] in
            guard let self, ticket == self.updateTicket else { return }
            self.updateContents(header: content, ids: ids, views: views, environment: environment, cap: cap, versions: versions)
        }
    }
    func contentHost(for id: String) -> NativePanelContentHost? { document.nodes[id] }
    private func updateContents(header content: AnyView, ids: [String], views: [AnyView], environment: EnvironmentValues, cap: CGFloat,
                                versions: [NativePanelContentVersion?]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if reorderController !== environment.panelReorderController {
            reorderSubscriptions.removeAll(); reorderController = environment.panelReorderController
            if let controller = reorderController {
                reorderSubscriptions = [controller.pointer.$location.sink { [weak self] _ in self?.scheduleEdgeScroll() },
                    controller.$session.sink { [weak self] session in
                        if session == nil { self?.stopEdgeScroll() } else { self?.scheduleEdgeScroll() }
                    }]
            }
        }
        capacity = cap
        let width = CGFloat(MonitorConstants.panelIdealWidth)
        frame.size = CGSize(width: width + inset * 2, height: cap + inset * 2)
        surface.frame = CGRect(x: inset, y: inset, width: width, height: cap)
        effect.frame = surface.bounds
        maskShape.frame = surface.bounds
        tint.frame = surface.bounds
        let dark = environment.colorScheme == .dark
        let appearanceName: NSAppearance.Name = dark ? .darkAqua : .aqua
        if effect.appearance?.name != appearanceName { effect.appearance = NSAppearance(named: appearanceName) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.backgroundColor = (dark ? NSColor.black.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.45)).cgColor
        outline.strokeColor = (dark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.25)).cgColor
        contourShadow.shadowOpacity = dark ? 0.4 : 0.22
        contourShadow.frame = surface.frame; outline.frame = surface.frame
        CATransaction.commit()
        header.rootView = AnyView(content.modifier(NativePanelEnvironmentBridge(values: environment)))
        header.frame.size.width = width - 12
        header.layoutSubtreeIfNeeded()
        let h = max(1, header.fittingSize.height)
        header.frame = CGRect(x: 6, y: 8, width: width - 12, height: h)
        motion.nativeLayer.report(owner: "__header__", values: ["__header__": CGSize(width: width - 12, height: h)])
        var env = environment
        env.nativePanelContentWidth = width - 12
        document.update(ids: ids, content: Array(views.prefix(ids.count)), environment: env, width: width - 12, versions: versions)
        if let content = views.dropFirst(ids.count).first {
            footer.rootView = AnyView(content.modifier(NativePanelEnvironmentBridge(values: env)))
            footer.frame.size.width = width - 12
            footer.layoutSubtreeIfNeeded()
            let footerHeight = max(1, footer.fittingSize.height)
            footer.frame = CGRect(x: 6, y: 8 + h + 4, width: width - 12, height: footerHeight)
            motion.nativeLayer.report(owner: "__footer__", values: ["__footer__": CGSize(width: width - 12, height: footerHeight)])
        }
        document.frame.size = CGSize(width: width - 12, height: max(document.frame.height, document.naturalHeight))
        scroll.frame = CGRect(x: 6, y: 8 + h + 4, width: width - 12, height: max(1, cap - (8 + h + 4 + 6 + footer.frame.height + (ids.isEmpty ? 0 : PanelGeometrySolver.cardToCardSpacing))))
        let token = GeometryEnvironmentToken(width: width, localeIdentifier: environment.locale.identifier,
            dynamicTypeSize: String(describing: environment.dynamicTypeSize), backingScale: environment.displayScale, structureSignature: "")
        motion.nativeLayer.configure(ids: ids, cap: cap, environment: token)
        if let plan = motion.nativeLayer.plan { applyNativePlan(plan) }
        installMonitors()
    }
    func contour(height: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: 0, y: 0, width: surface.bounds.width, height: max(1, height)),
            cornerWidth: MonitorConstants.panelCornerRadius, cornerHeight: MonitorConstants.panelCornerRadius, transform: nil)
    }
    func applyNativePlan(_ plan: NativePanelAnimationPlan) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let bodyTop = header.frame.maxY + PanelGeometrySolver.headerToBodySpacing
        if let final = plan.samples.last?.frame.cardFrames["__footer__"] {
            footer.frame.origin = CGPoint(x: 6, y: bodyTop + final.minY)
        }
        nativeAnimate(footer.layer!, key: "position.y", values: plan.samples.map {
            bodyTop + ($0.frame.cardFrames["__footer__"]?.minY ?? 0)
        }, plan: plan)
        let paths = plan.samples.map { contour(height: $0.frame.windowContentSize.height) }
        nativeAnimate(maskShape, key: "path", values: paths, plan: plan)
        nativeAnimate(outline, key: "path", values: paths, plan: plan)
        nativeAnimate(contourShadow, key: "shadowPath", values: paths, plan: plan)
        viewportMask.bounds = CGRect(x: 0, y: 0, width: scroll.bounds.width, height: 1)
        viewportMask.anchorPoint = .zero; viewportMask.position = .zero
        viewportMask.startPoint = CGPoint(x: 0.5, y: 0); viewportMask.endPoint = CGPoint(x: 0.5, y: 1)
        nativeAnimate(viewportMask, key: "bounds.size.height", values: plan.samples.map { $0.frame.viewportHeight }, plan: plan)
        let fade = MonitorConstants.panelScrollFadeLength
        nativeAnimate(viewportMask, key: "locations", values: plan.samples.map {
            let edge = min(0.5, fade / max(1, $0.frame.viewportHeight))
            return [NSNumber(value: 0), NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), NSNumber(value: 1)]
        }, plan: plan)
        let ownedOffset = motion.nativeLayer.hasAutomaticScroll ? nil : motion.nativeLayer.sample(at: CACurrentMediaTime())?.frame.scrollOffset
        nativeAnimate(viewportMask, key: "colors", values: plan.samples.map {
            let offset = ownedOffset ?? $0.frame.scrollOffset
            let remaining = max(0, $0.frame.bodyDocumentHeight - $0.frame.viewportHeight - offset)
            return [NSColor.black.withAlphaComponent(1 - min(1, offset / fade)).cgColor,
                NSColor.black.cgColor, NSColor.black.cgColor,
                NSColor.black.withAlphaComponent(1 - min(1, remaining / fade)).cgColor]
        }, plan: plan)
        if !motion.nativeLayer.isUserScrolling {
            let offset = ownedOffset ?? plan.samples.last?.frame.scrollOffset ?? 0
            clip.isApplyingNativePlan = true
            clip.scroll(to: CGPoint(x: 0, y: offset))
            clip.isApplyingNativePlan = false
            if motion.nativeLayer.hasAutomaticScroll {
                nativeAnimate(clip.layer!, key: "bounds.origin.y", values: plan.samples.map { $0.frame.scrollOffset }, plan: plan)
            } else {
                clip.layer?.removeAnimation(forKey: "panel.bounds.origin.y")
                clip.layer?.bounds.origin.y = offset
            }
        }
        CATransaction.commit()
        updateBoundary()
        scheduleBoundaryCrossing()
    }
    private func updateScrollFade() {
        guard let frame = motion.nativeLayer.sample(at: CACurrentMediaTime())?.frame else { return }
        let fade = MonitorConstants.panelScrollFadeLength
        let remaining = max(0, frame.bodyDocumentHeight - frame.viewportHeight - frame.scrollOffset)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        viewportMask.removeAnimation(forKey: "panel.colors")
        viewportMask.colors = [NSColor.black.withAlphaComponent(1 - min(1, frame.scrollOffset / fade)).cgColor,
            NSColor.black.cgColor, NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(1 - min(1, remaining / fade)).cgColor]
        CATransaction.commit()
    }
    func stopNativeMotion() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let layer = footer.layer { nativeFreeze(layer, keys: ["position.y"]) }
        nativeFreeze(maskShape, keys: ["path"]); nativeFreeze(outline, keys: ["path"])
        nativeFreeze(contourShadow, keys: ["shadowPath"])
        nativeFreeze(viewportMask, keys: ["bounds.size.height", "colors", "locations"])
        if let layer = clip.layer { nativeFreeze(layer, keys: ["bounds.origin.y"]) }
        CATransaction.commit()
        // 隐藏期间鼠标释放不再经过事件监视器，下次显示从新的输入会话开始。
        isDragging = false
        boundaryWork?.cancel(); boundaryWork = nil
        stopEdgeScroll()
        scroll.stopInteraction()
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        window?.acceptsMouseMovedEvents = false
        window?.ignoresMouseEvents = true
    }
    func nativePanelDidShow() { installMonitors(); updateBoundary(); scheduleBoundaryCrossing() }
    private func scheduleEdgeScroll(delay: TimeInterval = 0.05) {
        edgeScrollWork?.cancel(); edgeScrollWork = nil
        guard let controller = reorderController, let session = controller.session,
              let viewport = NativePanelCoordinates.frame(of: scroll), !motion.nativeLayer.isSuspended else { return }
        let pointer = controller.pointer.location
        let start = CGPoint(x: session.sourceFrame.minX + session.grabOffset.x, y: session.sourceFrame.minY + session.grabOffset.y)
        guard hypot(pointer.x - start.x, pointer.y - start.y) > 8 else { return }
        let direction: CGFloat
        if pointer.y > viewport.maxY - 28 { direction = 1 }
        else if pointer.y < viewport.minY + 28 { direction = -1 }
        else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.reorderController?.session != nil,
                  let frame = self.motion.nativeLayer.sample(at: CACurrentMediaTime())?.frame else { return }
            let current = self.clip.layer?.presentation()?.bounds.origin.y ?? self.clip.bounds.origin.y
            let target = PanelScrollCoordinator.clampUserOffset(offset: current + direction * 45, frame: frame)
            guard abs(target - current) > 0.5 else { return }
            self.motion.nativeLayer.userScrollBegan(at: current)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.clip.isApplyingNativePlan = true; self.clip.scroll(to: CGPoint(x: 0, y: target)); self.clip.isApplyingNativePlan = false
            let animation = CABasicAnimation(keyPath: "bounds.origin.y")
            animation.fromValue = current; animation.toValue = target; animation.duration = 0.18
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.clip.layer?.add(animation, forKey: "panel.edge-scroll")
            CATransaction.commit()
            self.motion.nativeLayer.updateUserScroll(target); self.updateScrollFade()
            self.scheduleEdgeScroll(delay: 0.21)
        }
        edgeScrollWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    private func stopEdgeScroll() {
        edgeScrollWork?.cancel(); edgeScrollWork = nil
        guard clip.layer?.animation(forKey: "panel.edge-scroll") != nil else { return }
        let current = clip.layer?.presentation()?.bounds.origin.y ?? clip.bounds.origin.y
        clip.layer?.removeAnimation(forKey: "panel.edge-scroll")
        clip.scroll(to: CGPoint(x: 0, y: current))
        motion.nativeLayer.userScrollEnded(at: current)
    }
    private func installMonitors() {
        guard localMonitor == nil, window?.isVisible == true, !motion.nativeLayer.isSuspended else { return }
        // 同一应用内的移动不会进入 global monitor，必须让容量窗口接收移动事件，
        // 才能在鼠标到达透明区域时于下一次按下前更新窗口边界。
        window?.acceptsMouseMovedEvents = true
        let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp || event.type == .rightMouseUp { self.isDragging = false }
            else if event.window === self.window && (event.type == .leftMouseDown || event.type == .rightMouseDown) {
                self.isDragging = self.containsPointer(at: CACurrentMediaTime())
            }
            self.updateBoundary()
            self.scheduleBoundaryCrossing()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            if event.type == .leftMouseUp || event.type == .rightMouseUp { self?.isDragging = false }
            self?.updateBoundary(); self?.scheduleBoundaryCrossing()
        }
    }
    private var pointerInSurface: CGPoint? {
        guard let window else { return nil }
        let position = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(position, from: nil)
        return CGPoint(x: local.x - inset, y: local.y - inset)
    }
    private func containsPointer(at time: CFTimeInterval) -> Bool {
        guard let point = pointerInSurface, let sample = motion.nativeLayer.sample(at: time) else { return false }
        return NativePanelInputGeometry.contains(point, width: surface.bounds.width,
            height: sample.frame.windowContentSize.height)
    }
    private func updateBoundary() {
        guard let window, window.isVisible else { return }
        let ignores = !isDragging && !containsPointer(at: CACurrentMediaTime())
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }
    /// 静止指针只在轮廓交叉时重新判定，不建立逐帧事件/绘制驱动。
    private func scheduleBoundaryCrossing() {
        boundaryWork?.cancel(); boundaryWork = nil
        guard let plan = motion.nativeLayer.plan, !motion.nativeLayer.isSuspended,
              plan.duration > 0, CACurrentMediaTime() < plan.startTime + plan.duration else { return }
        let now = CACurrentMediaTime()
        guard let point = pointerInSurface else { return }
        let inside = containsPointer(at: now)
        guard let crossing = plan.samples.first(where: {
            $0.frame.sampleTime > now && NativePanelInputGeometry.contains(point,
                width: surface.bounds.width, height: $0.frame.windowContentSize.height) != inside
        }) else { return }
        let item = DispatchWorkItem { [weak self] in self?.updateBoundary(); self?.scheduleBoundaryCrossing() }
        boundaryWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, crossing.frame.sampleTime - now), execute: item)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard let sample = motion.nativeLayer.sample(at: CACurrentMediaTime()),
              contour(height: sample.frame.windowContentSize.height).contains(CGPoint(x: local.x - inset, y: local.y - inset)) else { return nil }
        let surfacePoint = CGPoint(x: local.x - inset, y: local.y - inset)
        let bodyTop = header.frame.maxY + PanelGeometrySolver.headerToBodySpacing
        if let rect = sample.frame.cardFrames["__footer__"] {
            let visibleFooter = rect.offsetBy(dx: 6, dy: bodyTop)
            if visibleFooter.contains(surfacePoint) {
                return footer.hitTest(CGPoint(x: surfacePoint.x,
                    y: surfacePoint.y + footer.frame.minY - visibleFooter.minY))
            }
        }
        if header.frame.contains(surfacePoint) { return header.hitTest(surfacePoint) }
        let viewport = CGRect(x: 6, y: bodyTop, width: scroll.frame.width, height: sample.frame.viewportHeight)
        return viewport.contains(surfacePoint) ? scroll.hitTest(surfacePoint) : self
    }
}

private struct NativePanelSurfaceRepresentable: NSViewRepresentable {
    let motion: SingleHostMotionCoordinator
    let ids: [String]
    let header: AnyView
    let views: [AnyView]
    let versions: [NativePanelContentVersion?]
    let cap: CGFloat
    func makeNSView(context: Context) -> NativePanelSurface { NativePanelSurface(motion: motion) }
    func updateNSView(_ view: NativePanelSurface, context: Context) {
        view.update(header: header, ids: ids, views: views, environment: context.environment, cap: cap, versions: versions)
    }
    static func dismantleNSView(_ view: NativePanelSurface, coordinator: ()) {
        view.updateTicket &+= 1
        view.document.isMounted = false; view.document.updateTicket &+= 1
        view.stopNativeMotion()
        if let key = view.registration { view.motion.nativeLayer.unregister(key, owner: "__header__") }
        if let key = view.document.registration { view.motion.nativeLayer.unregister(key, owner: "__root__") }
    }
}

struct NativePanelSurfaceView: View {
    let motion: SingleHostMotionCoordinator
    let ids: [String]
    let cap: CGFloat
    let header: AnyView
    let items: [NativePanelContentItem]
    private var boundedCap: CGFloat {
        min(cap, motion.submissionAdapter?.currentScreen()?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height ?? 800) - MonitorConstants.panelNativeShadowInset * 2
    }
    var body: some View {
        NativePanelSurfaceRepresentable(motion: motion, ids: ids, header: header,
            views: items.map(\.content), versions: items.map(\.version), cap: boundedCap)
        .frame(width: MonitorConstants.panelIdealWidth + MonitorConstants.panelNativeShadowInset * 2,
            height: boundedCap + MonitorConstants.panelNativeShadowInset * 2, alignment: .topLeading)
    }
}
