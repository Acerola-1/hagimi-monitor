import SwiftUI

// MARK: - Compatible Container Background Modifier

/// 跨版本兼容的 `.containerBackground` 替代。
/// macOS 26+ 使用原生 `.containerBackground(.clear, for: .window)`，
/// macOS 15 上为空操作（窗口透明由 `TransparentWindowBackground` 已有组件负责）。
struct CompatibleContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    /// 跨版本兼容的 `.containerBackground(.clear, for: .window)` 替代。
    /// macOS 15 上为空操作，窗口透明由 `TransparentWindowBackground` 负责。
    func compatibleContainerBackground() -> some View {
        modifier(CompatibleContainerBackground())
    }
}
