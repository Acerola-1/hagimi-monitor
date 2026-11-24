import AppKit
import SwiftUI

/// 报表模块通用卡片容器。
struct ReportCardView<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var showsHeader: Bool = true
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        showsHeader: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.showsHeader = showsHeader
        self.trailing = trailing
        self.content = content
    }

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        showsHeader: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) where Trailing == EmptyView {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            showsHeader: showsHeader,
            trailing: { EmptyView() },
            content: content
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 12 : 0) {
            if showsHeader {
                HStack(alignment: .center, spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    trailing()
                }
            }

            content()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 0.75)
        }
    }
}
