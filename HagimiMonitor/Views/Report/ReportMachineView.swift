import AppKit
import SwiftUI

/// 「本机」硬件全景分类浏览器：展示完整硬件规格档案，支持可滚动分类标签、全局关键词检索及单项/整组复制反馈。
struct ReportMachineView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedCategoryId: String = ""
    @State private var searchText: String = ""
    @State private var copiedFeedbackKey: String?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        let categories = viewModel.snapshot?.hardware?.categories ?? []

        VStack(alignment: .leading, spacing: 16) {
            if categories.isEmpty {
                ReportCardView(
                    title: String(localized: "stats.r.kThisMac", defaultValue: "本机硬件全景规格"),
                    icon: "laptopcomputer"
                ) {
                    ReportEmptyPlaceholder(text: viewModel.isHardwareLoading
                        ? String(localized: "stats.r.loadingHardware", defaultValue: "正在采集硬件全景清单，统计内容已可用")
                        : String(localized: "stats.r.emptyHardware", defaultValue: "正在采集或当前环境限制无法读取硬件全景清单"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 顶部：可横向滚动的分类选择器 + 规格搜索框
                HStack(spacing: 12) {
                    categorySelector(categories: categories)

                    searchField
                }

                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !trimmed.isEmpty {
                    searchResultsView(categories: categories, query: trimmed)
                } else if let category = currentCategory(categories: categories) {
                    categoryDetailsView(category: category)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if selectedCategoryId.isEmpty, let first = categories.first {
                selectedCategoryId = first.id
            }
        }
        .onChange(of: viewModel.isHardwareLoading) { _, _ in
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

    // MARK: - 分类选择栏（遵循 DESIGN.md：标签过长时横向滚动，不能删去分类）

    private func categorySelector(categories: [HardwareCategory]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ReportNavigationPicker(
                title: String(localized: "report.ui.hardwareCategory"),
                selection: Binding(
                    get: { currentCategory(categories: categories)?.id ?? "" },
                    set: {
                        selectedCategoryId = $0
                        searchText = ""
                    }
                ),
                options: categories.map { category in
                    ReportSegmentOption(
                        value: category.id,
                        label: category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(category.nameKey)
                    )
                }
            )
            .fixedSize()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "stats.report.machine.searchPlaceholder", defaultValue: "搜索硬件规格"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .accessibilityLabel(Text(String(localized: "stats.report.machine.searchPlaceholder", defaultValue: "搜索硬件规格")))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 210)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.insetFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 0.75)
        )
    }

    // MARK: - 全局搜索结果

    @ViewBuilder
    private func searchResultsView(categories: [HardwareCategory], query: String) -> some View {
        let matchedCategories: [(category: HardwareCategory, groups: [HardwareFactGroup])] = categories.compactMap { cat in
            let baseGroups = cat.id == "this-mac"
                ? cat.groups.filter { $0.id == "identity" }
                : cat.groups
            let filteredGroups: [HardwareFactGroup] = baseGroups.compactMap { group in
                let groupMatches = group.name.resolve(hwText).lowercased().contains(query)
                let matchingFacts = groupMatches
                    ? group.facts
                    : group.facts.filter { fact in
                        fact.label.resolve(hwText).lowercased().contains(query)
                            || (fact.value?.lowercased().contains(query) ?? false)
                    }
                return matchingFacts.isEmpty ? nil : HardwareFactGroup(id: group.id, name: group.name, facts: matchingFacts)
            }
            return filteredGroups.isEmpty ? nil : (cat, filteredGroups)
        }

        if matchedCategories.isEmpty {
            ReportCardView(
                title: String(localized: "stats.report.machine.searchTitle", defaultValue: "硬件检索结果"),
                icon: "magnifyingglass"
            ) {
                ReportEmptyPlaceholder(text: String(localized: "stats.report.machine.searchEmpty", defaultValue: "未找到匹配的硬件规格条目"))
            }
        } else {
            ForEach(matchedCategories, id: \.category.id) { item in
                let title = item.category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(item.category.nameKey)
                ReportCardView(title: title, icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(item.groups.enumerated()), id: \.offset) { idx, group in
                            hardwareGroup(group, keyPrefix: "search-\(item.category.id)-\(idx)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 分类详情卡片组

    private func categoryDetailsView(category: HardwareCategory) -> some View {
        ReportCardView(
            title: category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(category.nameKey),
            icon: "info.circle"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                let groups = category.id == "this-mac"
                    ? category.groups.filter { $0.id == "identity" }
                    : category.groups
                ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                    hardwareGroup(group, keyPrefix: "\(category.id)-\(idx)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hardwareGroup(_ group: HardwareFactGroup, keyPrefix: String) -> some View {
        let groupFeedbackKey = "group-\(keyPrefix)-\(group.id)"
        let isGroupCopied = copiedFeedbackKey == groupFeedbackKey

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name.resolve(hwText))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    copyGroupFacts(group, feedbackKey: groupFeedbackKey)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isGroupCopied ? "checkmark" : "doc.on.doc")
                        if isGroupCopied {
                            Text(String(localized: "stats.report.copied", defaultValue: "已复制"))
                        } else {
                            Text("report.ui.copyGroup")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(isGroupCopied ? palette.base.severityTint(for: .calm) : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                ForEach(Array(group.facts.enumerated()), id: \.offset) { idx, fact in
                    factRow(fact: fact, feedbackKey: "\(keyPrefix)-\(idx)")
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.insetFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(palette.cardBorder, lineWidth: 0.5)
            }
        }
    }

    // MARK: - 规格项排版

    private func factRow(fact: HardwareFact, feedbackKey: String) -> some View {
        let isCopied = copiedFeedbackKey == feedbackKey

        return HStack(alignment: .top, spacing: 12) {
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
                Button {
                    copyValue(val, feedbackKey: feedbackKey)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: isCopied ? .semibold : .regular))
                        .foregroundStyle(isCopied ? palette.base.severityTint(for: .calm) : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(String(localized: "report.ui.copyValue"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func copyValue(_ value: String, feedbackKey: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        triggerCopyFeedback(feedbackKey)
    }

    private func copyGroupFacts(_ group: HardwareFactGroup, feedbackKey: String) {
        let text = group.facts.map { fact in
            "\(fact.label.resolve(hwText)): \(fact.value ?? "—")"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        triggerCopyFeedback(feedbackKey)
    }

    private func triggerCopyFeedback(_ key: String) {
        copiedFeedbackKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedFeedbackKey == key {
                copiedFeedbackKey = nil
            }
        }
    }
}
