import SwiftUI

// MARK: - Compatible Pulse Effect

/// 跨版本兼容的脉冲动画。macOS 26+ 使用原生 `.symbolEffect(.pulse)`，
/// macOS 15 使用 `.opacity` 循环动画模拟脉冲效果。
struct CompatiblePulseEffect: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .symbolEffect(.pulse, options: .repeating.speed(0.8))
        } else {
            content
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
        }
    }
}

// MARK: - Compatible Variable Color Effect

/// 跨版本兼容的 variableColor 动画。macOS 26+ 使用原生 `.symbolEffect(.variableColor.iterative)`，
/// macOS 15 上降级为静态图标（充电时仅改变 opacity 提示状态）。
struct CompatibleVariableColorEffect: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .symbolEffect(.variableColor.iterative, isActive: isActive)
        } else {
            content
                .opacity(isActive ? 1.0 : 0.7)
                .animation(.easeInOut(duration: 0.3), value: isActive)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// 跨版本兼容的脉冲动画替代。
    func compatiblePulseEffect() -> some View {
        modifier(CompatiblePulseEffect())
    }

    /// 跨版本兼容的 variableColor 动画替代。
    /// - Parameter isActive: 是否激活动画（如充电状态）。
    func compatibleVariableColorEffect(isActive: Bool) -> some View {
        modifier(CompatibleVariableColorEffect(isActive: isActive))
    }
}
