import AppKit
import SwiftUI

/// 「本机」硬件全景分类浏览器：展示从 system_profiler 与底层采集的完整硬件规格档案，支持按类切换、灵活排版与单项/整组复制。
struct ReportMachineView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedCategoryId: String = ""

    var body: some View {
        let categories = viewModel.snapshot?.hardware?.categories ?? []

        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            if categories.isEmpty {
                ReportCardView(
                    title: String(localized: "stats.r.kThisMac", defaultValue: "本机硬件全景规格"),
                    icon: "laptopcomputer"
                ) {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyHardware", defaultValue: "正在采集或当前环境限制无法读取硬件全景清单"))
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // 分类横向滚动标签栏
                    categorySelector(categories: categories)

                    // 当前选中分类的具体规格卡片组
                    if let category = currentCategory(categories: categories) {
                        categoryDetailsView(category: category)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if selectedCategoryId.isEmpty, let first = categories.first {
                selectedCategoryId = first.id
            }
        }
    }

    private func currentCategory(categories: [HardwareCategory]) -> HardwareCategory? {
        if let found = categories.first(where: { $0.id == selectedCategoryId }) {
            return found
        }
        return categories.first
    }

    // MARK: - 分类选择栏

    private func categorySelector(categories: [HardwareCategory]) -> some View {
        ScrollView(.horizontal) {
            ReportNavigationPicker(
                title: String(localized: "report.ui.hardwareCategory"),
                selection: Binding(
                    get: { currentCategory(categories: categories)?.id ?? "" },
                    set: { selectedCategoryId = $0 }
                )
            ) {
                ForEach(categories) { category in
                    Text(category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(category.nameKey)).tag(category.id)
                }
            }
            .fixedSize()
            .padding(.vertical, 4)
        }
    }

    // MARK: - 分类详情卡片组

    private func categoryDetailsView(category: HardwareCategory) -> some View {
        ReportCardView(
            title: category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(category.nameKey),
            icon: "info.circle"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if category.id == "this-mac" {
                    ForEach(category.groups.filter { $0.id == "identity" }, id: \.id) { group in
                        hardwareGroup(group)
                    }
                    DisclosureGroup(String(localized: "report.ui.advancedHardware")) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(category.groups.filter { $0.id != "identity" }, id: \.id) { group in
                                hardwareGroup(group)
                            }
                        }.padding(.top, 12)
                    }
                } else {
                    ForEach(Array(category.groups.enumerated()), id: \.offset) { _, group in
                        hardwareGroup(group)
                    }
                }
            }
        }
    }

    private func hardwareGroup(_ group: HardwareFactGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name.resolve(hwText))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // 复制整组规格按钮
                Button(action: { copyGroupFacts(group) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("report.ui.copyGroup")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                ForEach(Array(group.facts.enumerated()), id: \.offset) { _, fact in
                    factRow(fact: fact)
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
            }
        }
    }

    // MARK: - 规格项排版 (R23: 弹性宽度与自动换行，避免截断)

    private func factRow(fact: HardwareFact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(fact.label.resolve(hwText))
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, maxWidth: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.value ?? "—")
                .font(.body.weight(.medium))
                .foregroundStyle(fact.value != nil ? .primary : .tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if let val = fact.value {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(val, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "report.ui.copyValue"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func copyGroupFacts(_ group: HardwareFactGroup) {
        let text = group.facts.map { fact in
            "\(fact.label.resolve(hwText)): \(fact.value ?? "—")"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
