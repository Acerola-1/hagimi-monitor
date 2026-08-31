import AppKit
import SwiftUI

// MARK: - Liquid Glass Preference Environment

private struct LiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// 当前视图树是否启用 macOS 26 Liquid Glass。默认开启；应用根视图
    /// 使用持久化设置覆盖，预览和独立组件无需额外配置。
    var liquidGlassEnabled: Bool {
        get { self[LiquidGlassEnabledKey.self] }
        set { self[LiquidGlassEnabledKey.self] = newValue }
    }
}

// MARK: - Compatible Glass Container

/// 跨版本兼容的玻璃批处理容器。macOS 26+ 使用系统
/// `GlassEffectContainer` 合并渲染通道；macOS 15 只透传布局。
struct CompatibleGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    var body: some View {
        if #available(macOS 26, *), liquidGlassEnabled {
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

/// macOS 26 的系统 Liquid Glass 风格。整窗 regular glass 提供稳定的可读性
/// 衬底，监控行使用 clear glass 透出层次；macOS 15 所有风格均回退到
/// `NSVisualEffectView(.menu, .withinWindow)`。
enum CompatibleGlassStyle: Equatable {
    /// 静态玻璃，用于设置卡片和非交互表面。
    case liquid
    /// 标准交互玻璃，用于需要更强可读性衬底的控件。
    case liquidInteractive
    /// 静态内层表面，用于指标格、徽章等内容元素。
    case liquidClear
    /// 高通透交互玻璃，用于监控行和可点击的内层表面。
    case liquidClearInteractive

    fileprivate var isInteractive: Bool {
        switch self {
        case .liquidInteractive, .liquidClearInteractive:
            true
        case .liquid, .liquidClear:
            false
        }
    }

    @available(macOS 26, *)
    fileprivate var systemGlass: Glass {
        switch self {
        case .liquid, .liquidInteractive:
            .regular
        case .liquidClear, .liquidClearInteractive:
            .clear
        }
    }
}

// MARK: - Compatible Glass Effect Modifier

/// 监控行的跨版本玻璃效果。行本身可点击展开，因此在 macOS 26+ 使用
/// 原生 regular Liquid Glass，并把模块色作为系统 tint；不叠加自绘黑色
/// 遮罩或折射滤镜。macOS 15 保留原有 `NSVisualEffectView` 回退。
///
/// 15 回退必须使用 `.withinWindow`：面板 resize 时 `.behindWindow` 会逐帧
/// 重采样桌面，重新引入整窗闪烁。
struct CompatibleGlassEffect<GlassShape: Shape, Fill: View>: ViewModifier {
    var shape: GlassShape
    var tint: Color?
    var style: CompatibleGlassStyle
    var fallbackFill: Fill
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    func body(content: Content) -> some View {
        if #available(macOS 26, *), liquidGlassEnabled {
            content
                .glassEffect(liquidGlass, in: shape)
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

/// 内层内容表面保留原有动态填充；只有真正可交互的控件才在 macOS 26+
/// 升级为系统 Liquid Glass。这样指标格、徽章和数据胶囊不会形成嵌套玻璃。
struct CompatibleLiquidSurface<GlassShape: Shape, FallbackFill: View>: ViewModifier {
    var shape: GlassShape
    var tint: Color?
    var style: CompatibleGlassStyle
    var fallbackFill: FallbackFill
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    func body(content: Content) -> some View {
        if #available(macOS 26, *), liquidGlassEnabled, style.isInteractive {
            content
                .glassEffect(liquidGlass, in: shape)
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

/// 设置窗口专用的经典毛玻璃背景。无论系统版本或 Liquid Glass 开关
/// 状态都保持主线 `.menu + .withinWindow` 外观，避免面板效果泄漏到设置页。
private struct CompatibleClassicGlassEffect: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                Color.clear
                    .clipShape(shape)
                    .background {
                        VisualEffectView(material: .menu, blendingMode: .withinWindow)
                            .clipShape(shape)
                    }
            }
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
    /// 设置页使用的主线经典毛玻璃，不参与 Liquid Glass 管线。
    func compatibleClassicGlassEffect(cornerRadius: CGFloat) -> some View {
        modifier(CompatibleClassicGlassEffect(cornerRadius: cornerRadius))
    }

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

    /// 默认保持主线经典毛玻璃按钮；监控面板底部按钮在 26+ 使用系统
    /// regular Liquid Glass，由系统自行保证前景对比度。
    func compatibleButtonStyle(readabilityShade: Bool = false) -> some View {
        modifier(CompatiblePanelButtonStyleModifier(readabilityShade: readabilityShade))
    }

    /// 普通尺寸控件的系统玻璃按钮样式。与面板底部等宽按钮不同，
    /// macOS 15 回退到标准 bordered 样式，不额外改变标签布局。
    func compatibleSystemGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(CompatibleSystemGlassButtonStyleModifier(prominent: prominent))
    }

    /// 链接按钮的 Liquid Glass 升级。26+ 明确使用系统玻璃按钮，15 保留
    /// 原 `.link` 外观，避免为了兼容新系统改变旧系统的链接语义与布局。
    func compatibleGlassLinkButtonStyle() -> some View {
        modifier(CompatibleGlassLinkButtonStyleModifier())
    }
}

// MARK: - Compatible Button Styles

private struct CompatiblePanelButtonStyleModifier: ViewModifier {
    let readabilityShade: Bool
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), liquidGlassEnabled, readabilityShade {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(
                    .roundedRectangle(radius: MonitorConstants.rowCornerRadius)
                )
                .contentShape(panelButtonShape)
        } else {
            content.buttonStyle(PanelMaterialButtonStyle())
        }
    }

    private var panelButtonShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: MonitorConstants.rowCornerRadius,
            style: .continuous
        )
    }
}

private struct CompatibleSystemGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), liquidGlassEnabled {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct CompatibleGlassLinkButtonStyleModifier: ViewModifier {
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), liquidGlassEnabled {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.link)
        }
    }
}

// MARK: - NSPanel Glass Host

/// 为自建 NSPanel 创建系统玻璃宿主。26+ 使用 regular Liquid Glass：面板包含
/// 大量文字，regular 会主动调节亮度与模糊以维持可读性。15 保留
/// `.popover + .behindWindow` 背景。
@MainActor
enum CompatiblePanelGlassHost {
    /// 略微透出桌面背景，保留 regular glass 的可读性调节，避免整窗材质显得厚重。
    private static let backgroundGlassAlpha: CGFloat = 0.92

    static func make(
        contentView: NSView,
        cornerRadius: CGFloat,
        liquidGlassEnabled: Bool
    ) -> NSView {
        CompatiblePanelGlassHostView(
            contentView: contentView,
            cornerRadius: cornerRadius,
            liquidGlassEnabled: liquidGlassEnabled,
            backgroundGlassAlpha: backgroundGlassAlpha
        )
    }

    static func update(_ host: NSView?, liquidGlassEnabled: Bool) {
        (host as? CompatiblePanelGlassHostView)?.setLiquidGlassEnabled(liquidGlassEnabled)
    }
}

/// 背景材质和 SwiftUI 前景分层承载，使开关变化时只替换背景层，前景视图、
/// 展开状态及窗口尺寸均保持不变。
@MainActor
private final class CompatiblePanelGlassHostView: NSView {
    private let foregroundContentView: NSView
    private let panelCornerRadius: CGFloat
    private let backgroundGlassAlpha: CGFloat
    private var backdropView: NSView?
    private var backdropConstraints: [NSLayoutConstraint] = []
    private var liquidGlassEnabled: Bool

    init(
        contentView: NSView,
        cornerRadius: CGFloat,
        liquidGlassEnabled: Bool,
        backgroundGlassAlpha: CGFloat
    ) {
        foregroundContentView = contentView
        panelCornerRadius = cornerRadius
        self.liquidGlassEnabled = liquidGlassEnabled
        self.backgroundGlassAlpha = backgroundGlassAlpha
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installBackdrop()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLiquidGlassEnabled(_ enabled: Bool) {
        guard liquidGlassEnabled != enabled else { return }
        liquidGlassEnabled = enabled
        installBackdrop()
    }

    private func installBackdrop() {
        NSLayoutConstraint.deactivate(backdropConstraints)
        backdropConstraints.removeAll()
        backdropView?.removeFromSuperview()

        let backdrop: NSView
        if #available(macOS 26, *), liquidGlassEnabled {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = panelCornerRadius
            backdrop = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .popover
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            backdrop = visualEffect
        }

        // 新旧系统共用同一背景透明度，切换 Liquid Glass 时视觉密度保持一致。
        backdrop.alphaValue = backgroundGlassAlpha
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = panelCornerRadius
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop, positioned: .below, relativeTo: foregroundContentView)
        backdropConstraints = [
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(backdropConstraints)
        backdropView = backdrop
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
