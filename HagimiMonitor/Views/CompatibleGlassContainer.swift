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

/// 跨版本兼容的 `.glassEffect` 替代。macOS 26+ 使用原生 `.glassEffect`，
/// macOS 15 使用 `NSVisualEffectView` 背景实现近似效果。
struct CompatibleGlassEffect: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
        }
    }
}

// MARK: - Compatible Glass Effect ID Modifier

/// 跨版本兼容的 `.glassEffectID` 替代。macOS 26+ 使用原生 API，
/// macOS 15 上为空操作（NSVisualEffectView 无等价概念）。
struct CompatibleGlassEffectID: ViewModifier {
    var id: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffectID(id, in: namespace)
        } else {
            content
        }
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
