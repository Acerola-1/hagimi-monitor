import SwiftUI

// MARK: - Compatible Pulse Effect

/// 跨版本兼容的单次脉冲动画。macOS 26+ 使用原生 `.symbolEffect(.pulse, options: .speed(0.8), value: pulseToken)`，
/// macOS 15 保持静态，避免常驻 repeatForever 持续占用刷新时钟。
/// 当 trigger 变为 true（如面板呼出）时触发单次脉冲。
struct CompatiblePulseEffect: ViewModifier {
    var trigger: Bool = true
    @State private var pulseToken = 0

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .symbolEffect(.pulse, options: .speed(0.8), value: pulseToken)
                .onChange(of: trigger) { _, newValue in
                    if newValue {
                        pulseToken &+= 1
                    }
                }
                .onAppear {
                    if trigger {
                        pulseToken &+= 1
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// 跨版本兼容的脉冲动画替代。
    func compatiblePulseEffect(trigger: Bool = true) -> some View {
        modifier(CompatiblePulseEffect(trigger: trigger))
    }
}
