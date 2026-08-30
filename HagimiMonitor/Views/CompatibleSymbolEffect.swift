import SwiftUI

// MARK: - Compatible Pulse Effect

/// 跨版本兼容的单次脉冲。macOS 26+ 在 `trigger` 变化时播放一次
/// 原生 `.symbolEffect(.pulse)`；macOS 15 降级为静态。
///
/// 不可在面板可见期间使用 `.repeating` / `repeatForever`：即使只动一个
/// 5pt 圆点，也会让透明毛玻璃窗口持续提交合成帧，阻止 GPU 进入空闲。
struct CompatiblePulseEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .symbolEffect(.pulse, options: .speed(0.8), value: trigger)
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// `trigger` 变化时播放一次脉冲，不持续占用显示刷新时钟。
    func compatiblePulseEffect(trigger: Bool) -> some View {
        modifier(CompatiblePulseEffect(trigger: trigger))
    }
}
