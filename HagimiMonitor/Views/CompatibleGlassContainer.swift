import AppKit
import CoreImage
import QuartzCore
import SwiftUI

// MARK: - Compatible Glass Container

/// 跨版本兼容的玻璃批处理容器。macOS 26+ 使用系统
/// `GlassEffectContainer` 合并渲染通道；macOS 15 只透传布局。
struct CompatibleGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            if let spacing {
                GlassEffectContainer(spacing: spacing) {
                    content()
                }
            } else {
                GlassEffectContainer {
                    content()
                }
            }
        } else {
            content()
        }
    }
}

// MARK: - Compatible Glass Style

/// macOS 26 的系统 Liquid Glass 风格。`liquidClear` 使用系统 Clear
/// Liquid Glass，适合需要直接看见背景折射、避免磨砂感的监控面板；macOS 15
/// 所有风格均回退到 `NSVisualEffectView(.menu, .withinWindow)`。
enum CompatibleGlassStyle: Equatable {
    /// 静态玻璃，用于设置卡片和非交互表面。
    case liquid
    /// 交互玻璃，用于可点击的监控行。
    case liquidInteractive
    /// 高通透静态玻璃，用于指标格、徽章等内层表面。
    case liquidClear
    /// 高通透交互玻璃，用于监控行和可点击的内层表面。
    case liquidClearInteractive
    /// 带真实背景位移的高通透玻璃，用于需要凸透镜质感的主要色块。
    case liquidLens
    /// 带真实背景位移和指针反馈的高通透玻璃，用于主要监控行。
    case liquidLensInteractive

    fileprivate var isInteractive: Bool {
        switch self {
        case .liquidInteractive, .liquidClearInteractive, .liquidLensInteractive:
            true
        case .liquid, .liquidClear, .liquidLens:
            false
        }
    }

    fileprivate var usesLensRefraction: Bool {
        switch self {
        case .liquidLens, .liquidLensInteractive:
            true
        case .liquid, .liquidInteractive, .liquidClear, .liquidClearInteractive:
            false
        }
    }

    @available(macOS 26, *)
    fileprivate var systemGlass: Glass {
        switch self {
        case .liquid, .liquidInteractive:
            .regular
        case .liquidClear, .liquidClearInteractive, .liquidLens, .liquidLensInteractive:
            .clear
        }
    }
}

// MARK: - Optical Refraction

/// 系统 `Glass` 只公开 regular / clear 两种材质，没有折射强度旋钮。这里使用
/// macOS 公开的 Core Image 背景滤镜补上真实像素位移，再由 `Glass.clear` 负责
/// 系统高光与交互反馈。滤镜无时间轴，只在玻璃尺寸变化时重配。
private final class LiquidGlassRefractionNSView: NSView {
    enum Profile: Equatable {
        /// 横向胶囊走 Glass Lozenge；较高的展开卡片自动改用柔和凸面折射。
        case surface
        /// 整个面板使用覆盖全窗口的凸面折射。
        case panel
    }

    enum FilterTarget: Equatable {
        /// 折射当前视图后方的同窗内容，供 SwiftUI 色块使用。
        case background
        /// 折射当前视图承载的系统玻璃输出，供最外层窗口使用。
        case content
    }

    var profile: Profile {
        didSet {
            if oldValue != profile {
                invalidateFilterConfiguration()
            }
        }
    }

    var filterTarget: FilterTarget {
        didSet {
            if oldValue != filterTarget {
                invalidateFilterConfiguration()
            }
        }
    }

    private var configuredSize: CGSize = .zero

    init(profile: Profile, filterTarget: FilterTarget = .background) {
        self.profile = profile
        self.filterTarget = filterTarget
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        // 极低 alpha 只用于建立背景滤镜的合成覆盖区，肉眼不可见。
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        configureBackgroundFilterIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func invalidateFilterConfiguration() {
        configuredSize = .zero
        needsLayout = true
    }

    private func configureBackgroundFilterIfNeeded() {
        let size = bounds.size
        guard size.width > 1, size.height > 1, size != configuredSize else { return }
        configuredSize = size

        let filter: CIFilter?
        switch profile {
        case .panel:
            filter = bumpFilter(size: size, scale: 0.30)
        case .surface:
            // 收起的监控行/胶囊用真正的长圆玻璃折射；展开后的高卡片如果继续
            // 使用 lozenge 会在中部形成横带，因此改用覆盖全卡片的凸面折射。
            if size.width >= size.height * 1.55, size.height <= 64 {
                filter = lozengeFilter(size: size)
            } else {
                filter = bumpFilter(size: size, scale: 0.20)
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch filterTarget {
        case .background:
            contentFilters = []
            backgroundFilters = filter.map { [$0] } ?? []
        case .content:
            backgroundFilters = []
            contentFilters = filter.map { [$0] } ?? []
        }
        CATransaction.commit()
    }

    private func lozengeFilter(size: CGSize) -> CIFilter? {
        guard let filter = CIFilter(name: "CIGlassLozenge") else { return nil }
        let radius = max(8, size.height * 0.56)
        let left = min(radius, size.width / 2)
        let right = max(left, size.width - radius)
        filter.setValue(CIVector(x: left, y: size.height / 2), forKey: "inputPoint0")
        filter.setValue(CIVector(x: right, y: size.height / 2), forKey: "inputPoint1")
        filter.setValue(radius, forKey: "inputRadius")
        // 1.0 为无折射，1.42 接近实体玻璃且不会把小字背景拉成断层。
        filter.setValue(1.42, forKey: "inputRefraction")
        return filter
    }

    private func bumpFilter(size: CGSize, scale: CGFloat) -> CIFilter? {
        guard let filter = CIFilter(name: "CIBumpDistortion") else { return nil }
        filter.setValue(CIVector(x: size.width / 2, y: size.height / 2), forKey: kCIInputCenterKey)
        filter.setValue(hypot(size.width, size.height) * 0.60, forKey: kCIInputRadiusKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        return filter
    }
}

private struct LiquidGlassRefractionBackdrop: NSViewRepresentable {
    let profile: LiquidGlassRefractionNSView.Profile

    func makeNSView(context: Context) -> LiquidGlassRefractionNSView {
        LiquidGlassRefractionNSView(profile: profile)
    }

    func updateNSView(_ nsView: LiquidGlassRefractionNSView, context: Context) {
        if nsView.profile != profile {
            nsView.profile = profile
        }
        if nsView.filterTarget != .background {
            nsView.filterTarget = .background
        }
    }
}

/// 参考系统控制中心的边缘焦散：真实位移由 Core Image 完成，本层只补足玻璃
/// 周缘方向性高光/暗边，让圆角看起来有厚度而不是一层透明填色。
private struct LiquidGlassOpticalRim<GlassShape: Shape>: View {
    let shape: GlassShape

    var body: some View {
        shape
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: .white.opacity(0.62), location: 0.00),
                        .init(color: .white.opacity(0.10), location: 0.22),
                        .init(color: .black.opacity(0.16), location: 0.48),
                        .init(color: .white.opacity(0.34), location: 0.76),
                        .init(color: .white.opacity(0.62), location: 1.00)
                    ],
                    center: .center,
                    startAngle: .degrees(-35),
                    endAngle: .degrees(325)
                ),
                lineWidth: 1
            )
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}

// MARK: - Compatible Glass Effect Modifier

/// 跨版本玻璃效果。macOS 26+ 使用原生 `.glassEffect`；macOS 15
/// 保留旧的 `NSVisualEffectView` 回退。`fallbackFill` 只在 15 上渲染，
/// 因此 26 上不会在 Liquid Glass 之上叠加自绘渐变材质。
///
/// 15 回退必须使用 `.withinWindow`：面板 resize 时 `.behindWindow` 会逐帧
/// 重采样桌面，重新引入整窗闪烁。
struct CompatibleGlassEffect<GlassShape: Shape, Fill: View>: ViewModifier {
    var shape: GlassShape
    var tint: Color?
    var style: CompatibleGlassStyle
    var fallbackFill: Fill

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background {
                    if style.usesLensRefraction {
                        LiquidGlassRefractionBackdrop(profile: .surface)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                    }
                }
                .glassEffect(liquidGlass, in: shape)
                .overlay {
                    if style.usesLensRefraction {
                        LiquidGlassOpticalRim(shape: shape)
                    }
                }
        } else {
            content
                .background {
                    fallbackFill
                        .clipShape(shape)
                        .background {
                            VisualEffectView(material: .menu, blendingMode: .withinWindow)
                                .clipShape(shape)
                        }
                }
        }
    }

    /// 只把颜色 tint 交给系统玻璃管线，折射、高光和指针反馈均由系统绘制。
    @available(macOS 26, *)
    private var liquidGlass: Glass {
        var glass = style.systemGlass
        if let tint {
            glass = glass.tint(tint)
        }
        if style.isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}

/// 只在 macOS 26+ 把既有前景色块升级成系统 Liquid Glass；macOS 15
/// 精确保留原填充，不额外叠加 `NSVisualEffectView`。适用于指标格、徽章、
/// 提示卡等原本不是毛玻璃的内层表面。
struct CompatibleLiquidSurface<GlassShape: Shape, FallbackFill: View>: ViewModifier {
    var shape: GlassShape
    var tint: Color?
    var style: CompatibleGlassStyle
    var fallbackFill: FallbackFill

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background {
                    if style.usesLensRefraction {
                        LiquidGlassRefractionBackdrop(profile: .surface)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                    }
                }
                .glassEffect(liquidGlass, in: shape)
                .overlay {
                    if style.usesLensRefraction {
                        LiquidGlassOpticalRim(shape: shape)
                    }
                }
        } else {
            content
                .background {
                    fallbackFill.clipShape(shape)
                }
        }
    }

    @available(macOS 26, *)
    private var liquidGlass: Glass {
        var glass = style.systemGlass
        if let tint {
            glass = glass.tint(tint)
        }
        if style.isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - Compatible Glass Effect ID Modifier

/// `.glassEffectID` 的兼容占位。行展开是同一视图的高度生长，
/// 不需要跨视图 morphing；保持透传可避免动画期间多一层几何跟踪。
struct CompatibleGlassEffectID: ViewModifier {
    var id: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
    }
}

// MARK: - View Extensions

extension View {
    /// 统一玻璃效果：26+ 走 Liquid Glass，15 走原有毛玻璃回退。
    func compatibleGlassEffect(
        tint: Color? = nil,
        cornerRadius: CGFloat,
        style: CompatibleGlassStyle = .liquid
    ) -> some View {
        modifier(CompatibleGlassEffect(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            style: style,
            fallbackFill: tint ?? .clear
        ))
    }

    /// 自定义 15 回退填充版。26+ 仅使用 `tint` 参与系统玻璃渲染。
    func compatibleGlassEffect<Fill: View>(
        tint: Color? = nil,
        cornerRadius: CGFloat,
        style: CompatibleGlassStyle = .liquid,
        @ViewBuilder fallbackFill: () -> Fill
    ) -> some View {
        modifier(CompatibleGlassEffect(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            style: style,
            fallbackFill: fallbackFill()
        ))
    }

    /// 任意形状版。用于胶囊、圆形以及系统控件之外的前景玻璃表面。
    func compatibleGlassEffect<GlassShape: Shape>(
        tint: Color? = nil,
        in shape: GlassShape,
        style: CompatibleGlassStyle = .liquid
    ) -> some View {
        modifier(CompatibleGlassEffect(
            shape: shape,
            tint: tint,
            style: style,
            fallbackFill: tint ?? .clear
        ))
    }

    /// 任意形状、自定义 macOS 15 回退填充版。26+ 不渲染回退填充。
    func compatibleGlassEffect<GlassShape: Shape, Fill: View>(
        tint: Color? = nil,
        in shape: GlassShape,
        style: CompatibleGlassStyle = .liquid,
        @ViewBuilder fallbackFill: () -> Fill
    ) -> some View {
        modifier(CompatibleGlassEffect(
            shape: shape,
            tint: tint,
            style: style,
            fallbackFill: fallbackFill()
        ))
    }

    /// 既有圆角色块的 Liquid Glass 升级版：26+ 原生玻璃，15 原样填充。
    func compatibleLiquidSurface<Fill: View>(
        tint: Color? = nil,
        cornerRadius: CGFloat,
        style: CompatibleGlassStyle = .liquid,
        @ViewBuilder fallbackFill: () -> Fill
    ) -> some View {
        modifier(CompatibleLiquidSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            style: style,
            fallbackFill: fallbackFill()
        ))
    }

    /// 胶囊、圆形等任意形状的 Liquid Glass 升级版：26+ 原生玻璃，15 原样填充。
    func compatibleLiquidSurface<GlassShape: Shape, Fill: View>(
        tint: Color? = nil,
        in shape: GlassShape,
        style: CompatibleGlassStyle = .liquid,
        @ViewBuilder fallbackFill: () -> Fill
    ) -> some View {
        modifier(CompatibleLiquidSurface(
            shape: shape,
            tint: tint,
            style: style,
            fallbackFill: fallbackFill()
        ))
    }

    /// 保留 API 兼容；当前面板不需要玻璃跨视图 morphing。
    func compatibleGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(CompatibleGlassEffectID(id: id, namespace: namespace))
    }

    /// 26+ 使用系统 `.glass` 按钮，15 保留原有毛玻璃按钮。
    @ViewBuilder
    func compatibleButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass(.clear))
        } else {
            self.buttonStyle(PanelMaterialButtonStyle())
        }
    }

    /// 普通尺寸控件的系统玻璃按钮样式。与面板底部等宽按钮不同，
    /// macOS 15 回退到标准 bordered 样式，不额外改变标签布局。
    @ViewBuilder
    func compatibleSystemGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 链接按钮的 Liquid Glass 升级。26+ 明确使用系统玻璃按钮，15 保留
    /// 原 `.link` 外观，避免为了兼容新系统改变旧系统的链接语义与布局。
    @ViewBuilder
    func compatibleGlassLinkButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.link)
        }
    }
}

// MARK: - NSPanel Glass Host

/// 为自建 NSPanel 创建系统玻璃宿主。26+ 先用公开 Core Image 滤镜产生真实背景
/// 位移，再叠系统 Clear Liquid Glass 的高光；前景内容是独立兄弟层，不受背景
/// 透明度影响。15 保留 `.popover + .behindWindow` 背景。
@MainActor
enum CompatiblePanelGlassHost {
    private static let backgroundGlassAlpha: CGFloat = 0.94

    static func make(contentView: NSView, cornerRadius: CGFloat) -> NSView {
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let container: NSView
        if #available(macOS 26, *) {
            let host = NSView()
            host.wantsLayer = true
            host.layer?.cornerRadius = cornerRadius
            host.layer?.masksToBounds = true

            // 让滤镜处理 NSGlassEffectView 已采样到的桌面内容；直接对透明窗口底
            // 使用 backgroundFilters 无法保证跨窗口采样，content filter 则稳定。
            let refraction = LiquidGlassRefractionNSView(profile: .panel, filterTarget: .content)
            refraction.translatesAutoresizingMaskIntoConstraints = false

            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.style = .clear
            glass.cornerRadius = cornerRadius
            glass.alphaValue = backgroundGlassAlpha

            refraction.addSubview(glass)
            host.addSubview(refraction)
            host.addSubview(contentView)
            NSLayoutConstraint.activate([
                refraction.topAnchor.constraint(equalTo: host.topAnchor),
                refraction.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                refraction.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                refraction.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                glass.topAnchor.constraint(equalTo: refraction.topAnchor),
                glass.leadingAnchor.constraint(equalTo: refraction.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: refraction.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: refraction.bottomAnchor),
                contentView.topAnchor.constraint(equalTo: host.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            container = host
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .popover
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = cornerRadius
            visualEffect.layer?.masksToBounds = true
            visualEffect.addSubview(contentView)
            container = visualEffect

            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: container.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }
}

// MARK: - macOS 15 Glass Fallback

/// macOS 15 的毛玻璃按钮回退。
private struct PanelMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous)
        return configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                VisualEffectView(material: .menu, blendingMode: .withinWindow)
                    .clipShape(shape)
            }
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// macOS 15 上用于模拟行卡片玻璃的 AppKit 封装。
private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
