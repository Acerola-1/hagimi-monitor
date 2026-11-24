import SwiftUI

/// 分段选项的数据描述：明确值与展示文案，避免系统 Picker 在切换时发生宽度重算与液态玻璃形变。
struct ReportSegmentOption<Selection: Hashable>: Identifiable {
    let value: Selection
    let label: String

    var id: Selection { value }
}

/// 经典毛玻璃风格横向分段控件。
///
/// 相比系统 macOS 27 `.tabs` + `.glassEffect`：
/// - 严格贴合应用经典的柔和半透明视觉，不出现膨胀的液态玻璃胶囊；
/// - 每个分段用隐形 `.semibold` 占位锁定固有宽度，选中切换时仅移动底层高亮滑块，
///   彻底杜绝切换选项时的横向长度形变与相邻控件位移；
/// - 支持 `onReselect`（例如在已处于「自定义」日期时再次点击「自定义」直接弹出日历）。
struct ReportNavigationPicker<Selection: Hashable>: View {
    enum Size {
        case compact
        case regular

        var fontSize: CGFloat {
            switch self {
            case .compact: return 11.5
            case .regular: return 12
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 9
            case .regular: return 11
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 4
            case .regular: return 5
            }
        }

        var outerCornerRadius: CGFloat {
            switch self {
            case .compact: return 7.5
            case .regular: return 8.5
            }
        }

        var thumbCornerRadius: CGFloat {
            switch self {
            case .compact: return 5.5
            case .regular: return 6.5
            }
        }
    }

    let title: String
    @Binding var selection: Selection
    let options: [ReportSegmentOption<Selection>]
    var size: Size = .regular
    var onReselect: ((Selection) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var thumbNamespace
    @State private var hoveredValue: Selection?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segmentButton(for: option)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: size.outerCornerRadius, style: .continuous)
                .fill(trackFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.outerCornerRadius, style: .continuous)
                .strokeBorder(trackBorder, lineWidth: 0.6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func segmentButton(for option: ReportSegmentOption<Selection>) -> some View {
        let isSelected = selection == option.value
        let isHovered = hoveredValue == option.value

        return Button {
            if isSelected {
                onReselect?(option.value)
            } else {
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    selection = option.value
                }
            }
        } label: {
            ZStack {
                // 以 semibold 隐形副本锁定宽度，确保选中/未选中切换时文字宽度零变化
                Text(option.label)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()

                Text(option.label)
                    .font(.system(size: size.fontSize, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.85) : Color.secondary))
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: size.thumbCornerRadius, style: .continuous)
                        .fill(thumbFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: size.thumbCornerRadius, style: .continuous)
                                .strokeBorder(thumbBorder, lineWidth: 0.5)
                        )
                        .shadow(color: thumbShadow, radius: 1.5, x: 0, y: 0.75)
                        .matchedGeometryEffect(id: "report-segment-thumb", in: thumbNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: size.thumbCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.045))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: size.thumbCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredValue = option.value
            } else if hoveredValue == option.value {
                hoveredValue = nil
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 经典明暗外观色彩令牌

    private var trackFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.black.opacity(0.055)
    }

    private var trackBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.08)
    }

    private var thumbFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.17)
            : Color.white.opacity(0.96)
    }

    private var thumbBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.06)
    }

    private var thumbShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color.black.opacity(0.09)
    }
}
