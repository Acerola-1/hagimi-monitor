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

// MARK: - View Extensions

extension View {
    /// 跨版本兼容的脉冲动画替代。
    func compatiblePulseEffect() -> some View {
        modifier(CompatiblePulseEffect())
    }
}
