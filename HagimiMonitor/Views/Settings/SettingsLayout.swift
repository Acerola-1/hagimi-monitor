import AppKit
import SwiftUI

/// 设置页统一滚动容器:内容不足一屏时撑满可视区(配合页内 `Spacer`
/// 实现"关于"页底部署名沉底),超过一屏时正常滚动,任意窗口高度下不裁切内容。
struct SettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .controlSize(.small)
                .padding(.top, 22)
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }
}

struct SettingsGroup<Content: View, TitleAccessory: View>: View {
    var title: String?
    /// 标题行右侧挂件(如快捷操作按钮);无标题时不展示。
    var titleAccessory: TitleAccessory?
    let content: Content

    init(_ title: String? = nil,
         @ViewBuilder titleAccessory: () -> TitleAccessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleAccessory = titleAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 2)
                    Spacer(minLength: 0)
                    if let titleAccessory {
                        titleAccessory
                    }
                }
            }

            if #available(macOS 26, *) {
                CompatibleGlassContainer {
                    VStack(spacing: 0) {
                        content
                    }
                    .compatibleGlassEffect(cornerRadius: 13)
                }
            } else {
                VStack(spacing: 0) {
                    content
                }
                .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

extension SettingsGroup where TitleAccessory == EmptyView {
    /// 无标题挂件的便捷入口,保持旧调用写法不变。
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, titleAccessory: { EmptyView() }, content: content)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, subtitle == nil ? 10 : 11)
        .frame(minHeight: subtitle == nil ? 44 : 58)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.48))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

struct SettingsTip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "info.circle")
                .font(.caption2.weight(.medium))
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }
}

struct SettingsIconHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let footnote: String
    let imageName: String
    let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        footnote: String = "",
        imageName: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footnote = footnote
        self.imageName = imageName
        self.accessory = accessory()
    }

    var body: some View {
        let header = HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            accessory
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)

        if #available(macOS 26, *) {
            CompatibleGlassContainer {
                header
                    .compatibleGlassEffect(cornerRadius: 12)
            }
        } else {
            header
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
