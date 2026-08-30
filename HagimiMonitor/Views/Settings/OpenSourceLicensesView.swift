import AppKit
import SwiftUI

/// 第三方开源软件/素材声明列表。由「关于」页的开源软件声明行弹出（`.sheet`）。
///
/// 列出本 App 实际打包/使用的第三方开源组件与素材，含名称、用途、许可证与项目地址。
/// Sparkle 仅在直接分发版链接，故用 `#if DIRECT_DISTRIBUTION` 条件收录。
struct OpenSourceLicensesView: View {
    let onClose: () -> Void

    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let note: String
        let license: String
        let url: URL
    }

    private var entries: [Entry] {
        var list: [Entry] = [
            Entry(
                name: "RunCat",
                note: String(localized: "about.open-source.runcat.note"),
                license: "Apache License 2.0",
                url: URL(string: "https://github.com/Kyome22/RunCatNeo")!
            ),
            Entry(
                name: "KeyboardShortcuts",
                note: String(localized: "about.open-source.keyboardshortcuts.note"),
                license: "MIT License",
                url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!
            ),
        ]
        #if DIRECT_DISTRIBUTION
        list.append(
            Entry(
                name: "Sparkle",
                note: String(localized: "about.open-source.sparkle.note"),
                license: "MIT License",
                url: URL(string: "https://github.com/sparkle-project/Sparkle")!
            )
        )
        #endif
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "about.open-source.title"))
                    .font(.headline)
                Spacer(minLength: 12)
                CompatibleGlassContainer(spacing: 0) {
                    Button(String(localized: "about.open-source.close"), action: onClose)
                        .compatibleSystemGlassButtonStyle()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(for: entry)

                        if index != entries.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 420, height: 300)
    }

    private func row(for entry: Entry) -> some View {
        CompatibleGlassContainer(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.license)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                CompatibleGlassContainer(spacing: 0) {
                    Button {
                        NSWorkspace.shared.open(entry.url)
                    } label: {
                        Label(String(localized: "about.open-source.repo"), systemImage: "arrow.up.right.square")
                    }
                    .compatibleGlassLinkButtonStyle()
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .compatibleLiquidSurface(
                cornerRadius: 10,
                style: .liquidInteractive
            ) {
                Color.clear
            }
        }
    }
}
