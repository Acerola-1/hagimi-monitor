import AppKit
import SwiftUI

// MARK: - Compatible Glass Container

/// 跨版本兼容的毛玻璃容器。
/// 开启 Liquid Glass 且 macOS 26+ 时使用系统 `GlassEffectContainer`；
/// 关闭或旧系统时直接透传 content，消除容器冗余计算。
struct CompatibleGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    var isLiquidGlassEnabled: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *), isLiquidGlassEnabled {
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

// MARK: - Compatible Panel Glass Host

/// 面板窗口的跨版本底座宿主视图。
/// 严格遵守材质分层纪律：
/// 1. 窗口底座宿主（Window Backdrop）：
///    - 开启 Liquid Glass 且 macOS 26+ 时，使用 `NSGlassEffectView` 提供现代液态通透质感；
///    - 关闭或 macOS 15 时，使用 `NSVisualEffectView(material: .popover, blendingMode: .behindWindow)` 模糊桌面。
/// 2. 内部行卡片（Row Cards）：
///    - 严格保持 `.withinWindow` 毛玻璃，绝不回退或绑定为 `.behindWindow`，杜绝展开 resize 闪烁。
final class CompatiblePanelGlassHost: NSView {
    private var visualEffectView: NSVisualEffectView?
    private var glassEffectView: NSView?
    private let cornerRadius: CGFloat
    private(set) var isLiquidGlassEnabled: Bool = false
    private var hostingView: NSView?

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHostingView(_ hosting: NSView) {
        self.hostingView = hosting
        addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateMaterial(liquidGlassEnabled: Bool) {
        if visualEffectView != nil || glassEffectView != nil {
            guard isLiquidGlassEnabled != liquidGlassEnabled else { return }
        }
        isLiquidGlassEnabled = liquidGlassEnabled

        visualEffectView?.removeFromSuperview()
        visualEffectView = nil
        glassEffectView?.removeFromSuperview()
        glassEffectView = nil

        if #available(macOS 26, *), liquidGlassEnabled {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.wantsLayer = true
            glass.layer?.cornerRadius = cornerRadius
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.translatesAutoresizingMaskIntoConstraints = false
            if let hostingView {
                addSubview(glass, positioned: .below, relativeTo: hostingView)
            } else {
                addSubview(glass)
            }
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.glassEffectView = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .popover
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = cornerRadius
            visualEffect.layer?.cornerCurve = .continuous
            visualEffect.layer?.masksToBounds = true
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            if let hostingView {
                addSubview(visualEffect, positioned: .below, relativeTo: hostingView)
            } else {
                addSubview(visualEffect)
            }
            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.visualEffectView = visualEffect
        }
    }
}

// MARK: - Compatible Glass Effect Modifier

/// 行级毛玻璃效果，macOS 26 与 15 统一实现。
///
/// 设计取舍:液态玻璃(`.glassEffect`)在 26 上对行而言视觉与毛玻璃无异，
/// 却把行绑进 `GlassEffectContainer` 的几何合并逻辑，是展开闪烁的诱因之一。
/// 故行级统一降为 `NSVisualEffectView` 毛玻璃，液态玻璃仅保留在底部按钮
/// (见 `compatibleButtonStyle`)。
///
/// 关键:`blendingMode` 必须用 `.withinWindow`，不能用 `.behindWindow`。
/// `.behindWindow` 采样窗口背后的桌面——`MenuBarExtra(.window)` 展开时会 resize
/// 宿主窗口，每一帧都要重新向 WindowServer 请求背景合成，导致整个面板(含顶部
/// SYSTEM·LIVE)闪烁、像被重新加载。`.withinWindow` 只混合窗口内内容，resize
/// 不再触发桌面重采样，从根上消除闪烁。
struct CompatibleGlassEffect<Fill: View>: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Fill

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                fill
                    .clipShape(shape)
                    .background {
                        VisualEffectView(material: .menu, blendingMode: .withinWindow)
                            .clipShape(shape)
                    }
            }
    }
}

// MARK: - Compatible Glass Effect ID Modifier

/// `.glassEffectID` 的兼容占位。
///
/// 行级已统一为毛玻璃(见 `CompatibleGlassEffect`)，不再参与 `GlassEffectContainer`
/// 的液态玻璃合并，故此 modifier 在所有版本上均为空操作——把 `glassEffectID`
/// 附加在没有 `.glassEffect` 的视图上，26 上会引入无谓的容器几何重算。
/// 调用点保留(含 `namespace` 参数)以维持 API 兼容，行为为透传。
struct CompatibleGlassEffectID: ViewModifier {
    var id: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
    }
}

// MARK: - View Extensions

extension View {
    /// 跨版本兼容的 `.glassEffect` 替代。
    /// - Parameters:
    ///   - tint: 玻璃效果着色
    ///   - cornerRadius: 圆角半径
    func compatibleGlassEffect(tint: Color = .clear, cornerRadius: CGFloat) -> some View {
        modifier(CompatibleGlassEffect(cornerRadius: cornerRadius, fill: tint))
    }

    /// 跨版本兼容的 `.glassEffect` 替代(自定义填充版):填充可以是渐变等任意视图,
    /// 用于活力配色行 tint 的垂直衰减(见 `MonitorPalette.rowGlassFill`)。
    func compatibleGlassEffect(cornerRadius: CGFloat, @ViewBuilder fill: () -> some View) -> some View {
        modifier(CompatibleGlassEffect(cornerRadius: cornerRadius, fill: fill()))
    }

    /// 跨版本兼容的 `.glassEffectID` 替代。
    /// macOS 15 上为空操作。
    func compatibleGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(CompatibleGlassEffectID(id: id, namespace: namespace))
    }

    /// 面板底部按钮样式:统一用毛玻璃材质圆角卡片(`PanelMaterialButtonStyle`)。
    /// 面板整体(含各行)已是 `.menu` 毛玻璃基调,底部按钮若用 26 原生
    /// `.buttonStyle(.glass)` 液态玻璃,深色模式下会偏亮偏透、与周围格格不入,
    /// 故所有版本都统一为与行同款的毛玻璃圆角卡片。
    func compatibleButtonStyle() -> some View {
        self.buttonStyle(PanelMaterialButtonStyle())
    }
}

// MARK: - macOS 15 毛玻璃按钮样式

/// 面板底部按钮样式:毛玻璃材质卡片,与面板各行同款的 `.menu` +
/// `.withinWindow` 毛玻璃与 `rowCornerRadius` 圆角,融为一体、
/// 深浅模式下基调一致。
private struct PanelMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous)
        return configuration.label
            // 内边距与行卡片严格一致(同为 vertical 8):按钮高度与行同高,
            // rowCornerRadius 在矮按钮上会被夹到 height/2 退化成胶囊。
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

// MARK: - NSVisualEffectView Wrapper

/// macOS 15 上用于模拟 Glass 效果的 `NSVisualEffectView` 封装。
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
