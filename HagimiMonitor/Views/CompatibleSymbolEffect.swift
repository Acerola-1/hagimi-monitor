import SwiftUI

// MARK: - Compatible Pulse Effect

/// 跨版本兼容的脉冲动画。macOS 26+ 使用原生 `.symbolEffect(.pulse)`，
/// macOS 15 使用 `.opacity` 循环动画模拟脉冲效果。
/// `isActive` 为 false 时静止不脉冲——面板视图树常驻不销毁,
/// 隐藏期间的持续动画只会白白驱动渲染。
struct CompatiblePulseEffect: ViewModifier {
    var isActive: Bool = true
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .symbolEffect(.pulse, options: .repeating.speed(0.8), isActive: isActive)
        } else if isActive {
            content
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
        } else {
            // 静止分支:与脉冲分支结构不同(身份切换),确保 repeatForever 彻底停止。
            content
                .opacity(1.0)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// 跨版本兼容的脉冲动画替代。
    func compatiblePulseEffect(isActive: Bool = true) -> some View {
        modifier(CompatiblePulseEffect(isActive: isActive))
    }
}
