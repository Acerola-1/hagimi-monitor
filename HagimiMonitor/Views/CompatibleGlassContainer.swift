import AppKit
import SwiftUI

// MARK: - Compatible Glass Container

/// 跨版本兼容的毛玻璃容器。macOS 26+ 使用原生 `GlassEffectContainer`，
/// macOS 15 使用 `NSVisualEffectView` 实现近似毛玻璃效果。
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
            VStack(spacing: spacing ?? 0) {
                content()
            }
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
struct CompatibleGlassEffect: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(tint)
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
        modifier(CompatibleGlassEffect(tint: tint, cornerRadius: cornerRadius))
    }

    /// 跨版本兼容的 `.glassEffectID` 替代。
    /// macOS 15 上为空操作。
    func compatibleGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(CompatibleGlassEffectID(id: id, namespace: namespace))
    }

    /// 跨版本兼容的 `.buttonStyle(.glass)` 替代。
    /// macOS 26+ 使用原生 Glass 按钮样式，macOS 15 降级为 `.borderedProminent`。
    @ViewBuilder
    func compatibleButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent)
        }
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
