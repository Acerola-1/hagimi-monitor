import AppKit
import CoreGraphics
import IOKit
import SwiftUI

/// 单台显示器的信息快照(B4)。
/// 基础四项与档案数据全部来自公开 API + IORegistry 只读属性,双渠道一致。
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let resolution: String
    let refreshRate: String
    /// HDR(EDR)是否支持;按 NSScreen 的 EDR 能力判定,反映显示器
    /// 硬件能力而非当前开关态。nil = 无法判定,展示"--"。
    let hdrSupported: Bool?
    /// 链路最大位深(如 "10 bit"),来自系统驱动 DisplayHints 的 MaxBpc;
    /// 内建屏与未适配的 HDMI 外接读不到,显示 "--"。口径为「链路/面板
    /// 支持的最大每通道位数」:8bit+FRC 面板同样上报 10,与 Dell/Apple
    /// 官网「10.7 亿色 / 1 billion colors」的标称口径一致。
    let colorDepth: String
    /// 档案区:对角英寸尺寸(CGDisplayScreenSize 换算)。
    let sizeInches: Int?
    /// 档案区:像素密度(像素分辨率 ÷ 物理宽度)。
    let ppi: Int?
    /// 档案区:HiDPI 缩放倍率(像素/逻辑分辨率之比,仅 Retina 缩放态有值)。
    let hidpiScale: Int?
    /// 档案区:自适应同步范围(如 "48–120 Hz");优先系统档案的 VRR
    /// 声明,内建屏降级为支持模式的刷新率区间;均不可得为 nil。
    let adaptiveSync: String?
    /// 档案区:色域判定(如 "P3 广色域" / "sRGB"),来自系统解析的
    /// EDID 色彩空间声明;不可得为 nil。
    let gamut: String?
    /// 身份档案:厂商代码(Apple 屏映射为 "Apple")。
    let manufacturer: String?
    /// 身份档案:EDID 16 位产品码(十六进制,如 "A272");
    /// 非标准编码(部分内建屏的长整数)不展示。
    let model: String?
    /// 身份档案:字母数字序列号(EDID 描述符)。
    let serial: String?
    /// 身份档案:制造日期(本地化格式,如 "2025 年第 20 周")。
    let manufactureDate: String?
}

/// 显示器信息区(B4,两渠道通用):行头"N 台 · 外接 M",
/// 展开后按显示器分节展示基础四项,点「详情」再展完整档案。
/// 数据全部来自公开 API + IORegistry 只读属性,沙盒安全。
struct DisplayInfoSection: View {
    let theme: MonitorPanelTheme
    /// 发起某展开区的相位变化(0 或 1)并置位窗口层的采样推迟截止标记。
    /// `animated` 为 false 时无补间直接同步(初始化/隐藏重置等同步语义场景)。
    var animate: (String, Bool, Bool) -> Void

    /// 本节展开区 key(与显示器档案卡的 key 区分)。
    private static let sectionKey = "display-info"

    @State private var isExpanded = false
    @State private var displays: [DisplayInfo] = []

    private var displayTint: Color {
        theme.palette.displayTint
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(displayTint)
                    .frame(width: 18)

                Text(String(localized: "kind.display") + ":")
                    .monitorPanelMetricLabelFont()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(summaryText)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            CollapsibleDetail(expansionKey: Self.sectionKey, isExpanded: isExpanded, contentAvailable: !displays.isEmpty) {
                VStack(spacing: 9) {
                    ForEach(displays) { display in
                        displaySection(display)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !displays.isEmpty else { return }
            if !isExpanded {
                displays = Self.collectDisplays()
            }
            withAnimation(.spring(response: MonitorConstants.panelExpansionSpringResponse,
                                  dampingFraction: MonitorConstants.panelExpansionSpringDamping)) {
                isExpanded.toggle()
            }
            animate(Self.sectionKey, isExpanded, true)
        }
        .compatibleGlassEffect(
            tint: theme.palette.displayGlassTint,
            cornerRadius: MonitorConstants.rowCornerRadius,
            style: .liquidLensInteractive
        ) {
            theme.palette.displayGlassFill
        }
        .onAppear {
            displays = Self.collectDisplays()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            // 仅展开期间跟随插拔/分辨率变化;收起时不刷新,零额外开销。
            if isExpanded {
                displays = Self.collectDisplays()
            }
        }
    }

    private var summaryText: String {
        String(format: String(localized: "panel.displays.count"), displays.count)
    }

    // MARK: 单台显示器分节

    private func displaySection(_ display: DisplayInfo) -> some View {
        DisplayInfoCard(
            display: display,
            palette: theme.palette,
            archiveKey: "display-info-arc-\(display.id)",
            animate: animate
        )
    }

    // MARK: 采集

    /// 采集当前显示器信息快照。Direct 版的 DisplayControlsSection 也复用此采集
    /// (把分辨率/刷新率并进控制区展示),故为 internal 而非 private。
    static func collectDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }

        let screens = NSScreen.screens
        // 链路能力探针与面板档案探针整个采集各只读一次,再与各显示器对配。
        let linkHints = DisplayLinkCapabilities.hints()
        let archives = DisplayAttributesProbe.attributes()
        return ids.map { id in
            // 镜像显示器共享同一 NSScreen 条目,按屏幕号匹配取名称与 EDR 状态。
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let mode = CGDisplayCopyDisplayMode(id)

            let resolution = mode.map { "\($0.pixelWidth)×\($0.pixelHeight)" } ?? "--"
            let refreshRate = mode.map {
                $0.refreshRate > 0 ? "\(Int($0.refreshRate.rounded())) Hz" : "--"
            } ?? "--"

            // HDR 支持判定:NSScreen 的 maximumPotential EDR 分量 > 1 表示具备
            // EDR/HDR 硬件能力(与当前是否处于 HDR 增益态无关)。
            let hdrSupported = screen.map {
                $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.01
            }

            let archive = Self.matchAttributes(
                archives,
                displayName: screen?.localizedName,
                width: mode?.pixelWidth ?? 0,
                height: mode?.pixelHeight ?? 0
            )

            // 物理尺寸/像素密度:CGDisplayScreenSize 为厘米,换算对角英寸与横向 PPI;
            // 虚拟屏/部分投影场景返回零尺寸,此时不展示。
            var sizeInches: Int? = nil
            var ppi: Int? = nil
            let sizeMM = CGDisplayScreenSize(id)
            if sizeMM.width > 100, sizeMM.height > 100 {
                sizeInches = Int((sqrt(sizeMM.width * sizeMM.width + sizeMM.height * sizeMM.height) / 25.4).rounded())
                if let mode {
                    ppi = Int((Double(mode.pixelWidth) / (sizeMM.width / 25.4)).rounded())
                }
            }

            // HiDPI 缩放倍率:像素/逻辑分辨率之比,非缩放态(1:1)不展示。
            var hidpiScale: Int? = nil
            if let mode, mode.width > 0 {
                let scale = Double(mode.pixelWidth) / Double(mode.width)
                if scale > 1.01 {
                    hidpiScale = Int(scale.rounded())
                }
            }

            // 自适应同步:优先系统档案的 VRR 声明(外接屏 EDID 解析结果);
            // 内建屏的档案无此字段,降级为支持模式的刷新率区间(ProMotion 48–120)。
            var adaptiveSync: String? = nil
            if let archive, archive.supportsVariableRefreshRate,
               archive.minRefreshRate > 0, archive.maxRefreshRate > archive.minRefreshRate {
                adaptiveSync = "\(archive.minRefreshRate)–\(archive.maxRefreshRate) Hz"
            } else if let modes = CGDisplayCopyAllDisplayModes(id, ["ShowDuplicates": kCFBooleanTrue] as CFDictionary) as? [CGDisplayMode] {
                let rates = Set(modes.map { Int($0.refreshRate.rounded()) }.filter { $0 > 0 })
                if let low = rates.min(), let high = rates.max(), high > low {
                    adaptiveSync = "\(low)–\(high) Hz"
                }
            }

            var manufactureDate: String? = nil
            if let archive, archive.weekOfManufacture > 0, archive.yearOfManufacture > 0 {
                manufactureDate = String(
                    format: String(localized: "metric-value.display.manufacture-date"),
                    archive.yearOfManufacture, archive.weekOfManufacture
                )
            }

            return DisplayInfo(
                id: id,
                name: screen?.localizedName ?? "Display \(id)",
                isBuiltIn: builtIn,
                resolution: resolution,
                refreshRate: refreshRate,
                hdrSupported: hdrSupported,
                colorDepth: Self.linkColorDepth(
                    hints: linkHints,
                    displayName: screen?.localizedName,
                    width: mode?.pixelWidth ?? 0,
                    height: mode?.pixelHeight ?? 0
                ),
                sizeInches: sizeInches,
                ppi: ppi,
                hidpiScale: hidpiScale,
                adaptiveSync: adaptiveSync,
                gamut: archive?.defaultColorSpaceIsSRGB.map {
                    $0 ? "sRGB" : String(localized: "metric-value.display.gamut.p3")
                },
                manufacturer: Self.manufacturerName(from: archive),
                model: archive.flatMap {
                    (1...0xFFFF).contains($0.productID) ? String(format: "%X", $0.productID) : nil
                },
                serial: archive?.serial,
                manufactureDate: manufactureDate
            )
        }
    }

    /// 链路位深对配:驱动节点给出的 hints(带 ProductName/MaxW/MaxH)与
    /// CG 侧显示器没有公共主键,按「原生分辨率精确匹配」为主、「产品名包含」
    /// 为辅对配;都配不上时,唯一 hints + 唯一外接屏也视为命中(单屏场景)。
    private static func linkColorDepth(
        hints: [DisplayLinkCapabilities.Hint],
        displayName: String?,
        width: Int,
        height: Int
    ) -> String {
        guard !hints.isEmpty else { return "--" }
        let matched = hints.first { $0.maxW == width && $0.maxH == height }
            ?? hints.first {
                !$0.productName.isEmpty && (displayName?.contains($0.productName) ?? false)
            }
        guard let hint = matched else { return "--" }
        return "\(hint.maxBpc) bit"
    }

    /// 面板档案对配:与位深探针同一策略——原生分辨率精确匹配为主,
    /// 产品名包含为辅。档案缺原生分辨率字段时由探针以节点级
    /// DisplayWidth/Height 补齐,保证内建屏也能命中。
    private static func matchAttributes(
        _ archives: [DisplayAttributesProbe.Attributes],
        displayName: String?,
        width: Int,
        height: Int
    ) -> DisplayAttributesProbe.Attributes? {
        guard !archives.isEmpty else { return nil }
        return archives.first { $0.nativeWidth == width && $0.nativeHeight == height }
            ?? archives.first {
                !$0.productName.isEmpty && (displayName?.contains($0.productName) ?? false)
            }
    }

    /// 厂商代码归一:EDID 三字母 PNP 码映射为品牌名(如 DEL → Dell);
    /// Apple 内建屏的厂商码为数字串("00-10-fa"),单独映射;未收录的
    /// 码优先取产品名首词(如 "DELL S2725QC" → "DELL"),兜底保留原码。
    private static let manufacturerNames: [String: String] = [
        "DEL": "Dell", "APP": "Apple", "SAM": "Samsung", "GSM": "LG",
        "ACR": "Acer", "LEN": "Lenovo", "PHL": "Philips", "BNQ": "BenQ",
        "ASU": "ASUS", "VSC": "ViewSonic", "HWP": "HP", "SNY": "Sony",
        "IVM": "iiyama", "MEI": "Panasonic", "EIZ": "EIZO", "MSI": "MSI",
        "CMN": "Innolux", "AUO": "AUO", "SHP": "Sharp", "BOE": "BOE"
    ]

    private static func manufacturerName(from archive: DisplayAttributesProbe.Attributes?) -> String? {
        guard let archive else { return nil }
        if archive.isAppleManufacturer {
            return "Apple"
        }
        if let mapped = manufacturerNames[archive.manufacturerID] {
            return mapped
        }
        let firstWord = archive.productName.split(separator: " ").first.map(String.init)
        return firstWord ?? (archive.manufacturerID.isEmpty ? nil : archive.manufacturerID)
    }
}

/// 单台显示器卡片:分节标题(名称 + 展开角标)+ 基础四项 tile + 可折叠档案区。
/// 与 Direct 控制卡共用同一套信息组件,两渠道信息呈现完全一致。
/// 基础四项与档案区同处 gridRowGap 间距容器,展开后格子间留白统一。
private struct DisplayInfoCard: View {
    let display: DisplayInfo
    let palette: MonitorPalette
    /// 本卡档案展开区 key(按显示器区分,同一面板展开多台不互相牵动)。
    let archiveKey: String
    /// 发起动画的闭包,与 DisplayInfoSection 同一驱动源。
    var animate: (String, Bool, Bool) -> Void

    @State private var archiveExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(display.name)
                    .monitorPanelLabelFont(tracking: 0.8)
                    .foregroundStyle(palette.captionText)
                    .fixedSize()
                Rectangle()
                    .fill(palette.displaySeparator)
                    .frame(height: 1)
                DisplayArchiveToggle(
                    palette: palette,
                    archiveExpanded: archiveExpanded,
                    onToggle: toggleArchive
                )
            }
            .padding(.leading, 28)

            VStack(alignment: .leading, spacing: MetricGridMetrics.gridRowGap) {
                DisplayInfoBaseGrid(display: display, palette: palette)

                CollapsibleDetail(expansionKey: archiveKey, isExpanded: archiveExpanded) {
                    archiveContent
                }
            }
            .padding(.leading, 28)
        }
    }

    /// 档案内容:明细网格 + 底部复制按钮,随折叠整体隐现。
    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: MetricGridMetrics.rowSpacing) {
            DisplayArchiveGrid(display: display, palette: palette)
            DisplayArchiveCopyButton(display: display, palette: palette)
        }
    }

    /// 档案开合与其他展开区同一驱动源:置位窗口层采样推迟截止标记,
    /// 并把本卡档案相位交驱动器补间(0↔1)。
    private func toggleArchive() {
        withAnimation(.spring(response: MonitorConstants.panelExpansionSpringResponse,
                              dampingFraction: MonitorConstants.panelExpansionSpringDamping)) {
            archiveExpanded.toggle()
        }
        animate(archiveKey, archiveExpanded, true)
    }
}

/// 分节标题行的档案展开角标:单一图标按钮,与档案内的复制按钮
/// 空间分离,避免面板窄小处两钮相挨误触。文案走 help 提示。
struct DisplayArchiveToggle: View {
    let palette: MonitorPalette
    let archiveExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            CompatibleGlassContainer(spacing: 0) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(archiveExpanded ? 90 : 0))
                    .foregroundStyle(palette.captionText)
                    .frame(width: 16, height: 16)
                    .compatibleLiquidSurface(
                        tint: palette.displayTint.opacity(0.12),
                        in: Circle(),
                        style: .liquidClearInteractive
                    ) {
                        Color.clear
                    }
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(String(localized: archiveExpanded ? "display.archive.hide" : "display.archive.show"))
    }
}

/// 档案区底部的复制按钮:展开后才出现,把该显示器完整信息写入
/// 剪贴板,短暂对勾反馈。胶囊内衬样式与 stat tile 同源。
struct DisplayArchiveCopyButton: View {
    let display: DisplayInfo
    let palette: MonitorPalette

    @State private var justCopied = false

    var body: some View {
        CompatibleGlassContainer(spacing: 0) {
            HStack {
                Spacer()
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(String(localized: justCopied ? "display.archive.copied" : "display.archive.copy"))
                            .monitorPanelCaptionFont(.caption2)
                    }
                    .foregroundStyle(justCopied ? palette.severityTint(for: .calm) : palette.captionText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .compatibleLiquidSurface(
                        tint: palette.displayTint.opacity(0.10),
                        in: Capsule(),
                        style: .liquidClearInteractive
                    ) {
                        palette.trackFill
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DisplayArchiveText.build(for: display), forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
        }
    }
}

/// 档案明细网格:规格五项 + 身份档案四项,逐格内衬 stat tile 形态,
/// 两渠道共用;缺失项统一展示 "--"。结构性超宽的项(自适应同步/
/// 序列号/制造日期)与值超长的项整行显示,避免半宽格内被省略号截断。
/// 网格用急切求值的 Grid(非 Lazy):折叠态内容被钳在 0 高度内,
/// lazy 容器此时不实体化格子、测高失真,展开会先闪后跳。
struct DisplayArchiveGrid: View {
    let display: DisplayInfo
    let palette: MonitorPalette

    private struct Row: Identifiable {
        let id: String
        let label: String
        let value: String
        let fullRow: Bool
    }

    /// 半宽格内值的宽度预算:超过则升为整行(序列号等长值兼容不同机型)。
    private static let halfRowValueBudget = 10

    var body: some View {
        CompatibleGlassContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: MetricGridMetrics.rowSpacing) {
                grid(for: specRows)
                Text(String(localized: "display.archive.identity"))
                    .monitorPanelCaptionFont(.caption2)
                    .foregroundStyle(palette.captionText)
                    .padding(.top, 1)
                grid(for: identityRows)
            }
        }
    }

    /// 规格项:尺寸/像素密度/缩放/色域两列排布,自适应同步值常带区间
    /// 文本,单独整行展示。
    private var specRows: [Row] {
        var rows: [Row] = []
        if let inches = display.sizeInches {
            rows.append(row(
                "metric.display.size",
                String(format: String(localized: "metric-value.display.size"), inches)
            ))
        }
        if let ppi = display.ppi {
            rows.append(row("metric.display.ppi", "\(ppi) PPI"))
        }
        if let scale = display.hidpiScale {
            rows.append(row("metric.display.hidpi-scale", "\(scale)×"))
        }
        rows.append(row("metric.display.gamut", display.gamut ?? "--"))
        rows.append(row("metric.display.adaptive-sync", display.adaptiveSync ?? "--", structuralFullRow: true))
        return rows
    }

    private var identityRows: [Row] {
        [
            // 品牌名(如 Panasonic)加 en 标签超半格预算,整行展示
            row("metric.display.manufacturer", display.manufacturer ?? "--", structuralFullRow: true),
            row("metric.display.model", display.model ?? "--"),
            row("metric.display.serial", display.serial ?? "--", structuralFullRow: true),
            row("metric.display.manufacture-date", display.manufactureDate ?? "--", structuralFullRow: true)
        ]
    }

    private func row(_ labelKey: String, _ value: String, structuralFullRow: Bool = false) -> Row {
        Row(
            id: labelKey,
            label: String(localized: String.LocalizationValue(labelKey)),
            value: value,
            fullRow: structuralFullRow || value.count > Self.halfRowValueBudget
        )
    }

    /// 两列 Grid:半宽格按原序两两成行,整行格以 gridCellColumns(2) 跨列。
    private func grid(for rows: [Row]) -> some View {
        Grid(
            horizontalSpacing: MetricGridMetrics.columnSpacing,
            verticalSpacing: MetricGridMetrics.gridRowGap
        ) {
            ForEach(Array(rowChunks(rows).enumerated()), id: \.offset) { _, chunk in
                GridRow {
                    ForEach(chunk) { item in
                        DisplayArchiveTile(label: item.label, value: item.value, palette: palette)
                            .gridCellColumns(chunk.count == 1 && item.fullRow ? 2 : 1)
                    }
                }
            }
        }
    }

    /// 分段:连续半宽格两两一组,整行格独立成组,保持原有展示顺序。
    private func rowChunks(_ rows: [Row]) -> [[Row]] {
        var chunks: [[Row]] = []
        var current: [Row] = []
        for item in rows {
            if item.fullRow {
                if !current.isEmpty {
                    chunks.append(current)
                    current = []
                }
                chunks.append([item])
            } else if current.count == 2 {
                chunks.append(current)
                current = [item]
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

/// 基础四项的 stat tile 网格(分辨率/刷新率/HDR/位深),两渠道共用。
/// 分辨率值固定 9 字符,加 en 标签超半格预算,升整行跨列;其余三项
/// 半行两列,位深落单空洞留在行尾。HDR 格展示支持与否(硬件能力口径,
/// 非当前开关态)。
struct DisplayInfoBaseGrid: View {
    let display: DisplayInfo
    let palette: MonitorPalette

    var body: some View {
        CompatibleGlassContainer(spacing: 0) {
            Grid(
                horizontalSpacing: MetricGridMetrics.columnSpacing,
                verticalSpacing: MetricGridMetrics.gridRowGap
            ) {
                GridRow {
                    DisplayArchiveTile(label: String(localized: "metric.display.resolution"), value: display.resolution, palette: palette)
                        .gridCellColumns(2)
                }
                GridRow {
                    DisplayArchiveTile(label: String(localized: "metric.display.refresh-rate"), value: display.refreshRate, palette: palette)
                    DisplayArchiveTile(
                        label: "HDR",
                        value: display.hdrSupported.map {
                            $0
                                ? String(localized: "metric-value.display.hdr.supported")
                                : String(localized: "metric-value.display.hdr.unsupported")
                        } ?? "--",
                        palette: palette
                    )
                }
                GridRow {
                    DisplayArchiveTile(label: String(localized: "metric.display.color-depth"), value: display.colorDepth, palette: palette)
                }
            }
        }
    }
}

/// 档案格子:trackFill 圆角色块内衬,label 左 caption 色 / 值右 mono;
/// "--" 值降为 caption 色,与面板既有降级口径一致。
private struct DisplayArchiveTile: View {
    let label: String
    let value: String
    let palette: MonitorPalette

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(palette.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 6)

            Text(value)
                .monitorPanelMonoFont(.caption2, weight: .semibold)
                .foregroundStyle(value == "--" ? palette.captionText : palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .compatibleLiquidSurface(
            tint: palette.displayTint.opacity(0.08),
            cornerRadius: 9,
            style: .liquidClear
        ) {
            palette.trackFill
        }
    }
}

/// 显示器完整档案复制文本:名称(内建/外接标注)+ 默认四项 + 档案区,
/// 每项一行;档案缺失项不进文本,保持粘贴出去的文本干净。
enum DisplayArchiveText {
    static func build(for info: DisplayInfo) -> String {
        let tag = info.isBuiltIn ? String(localized: "display.built-in") : String(localized: "display.external")
        var lines = ["\(info.name)(\(tag))"]
        lines.append(item("metric.display.resolution", info.resolution))
        lines.append(item("metric.display.refresh-rate", info.refreshRate))
        lines.append(item("HDR", info.hdrSupported.map {
            $0
                ? String(localized: "metric-value.display.hdr.supported")
                : String(localized: "metric-value.display.hdr.unsupported")
        } ?? "--"))
        lines.append(item("metric.display.color-depth", info.colorDepth))
        if let inches = info.sizeInches {
            lines.append(item("metric.display.size", String(format: String(localized: "metric-value.display.size"), inches)))
        }
        if let ppi = info.ppi {
            lines.append(item("metric.display.ppi", "\(ppi) PPI"))
        }
        if let scale = info.hidpiScale {
            lines.append(item("metric.display.hidpi-scale", "\(scale)×"))
        }
        if let sync = info.adaptiveSync {
            lines.append(item("metric.display.adaptive-sync", sync))
        }
        if let gamut = info.gamut {
            lines.append(item("metric.display.gamut", gamut))
        }
        if let manufacturer = info.manufacturer {
            lines.append(item("metric.display.manufacturer", manufacturer))
        }
        if let model = info.model {
            lines.append(item("metric.display.model", model))
        }
        if let serial = info.serial {
            lines.append(item("metric.display.serial", serial))
        }
        if let date = info.manufactureDate {
            lines.append(item("metric.display.manufacture-date", date))
        }
        return lines.joined(separator: "\n")
    }

    private static func item(_ labelKey: String, _ value: String) -> String {
        "\(String(localized: String.LocalizationValue(labelKey))): \(value)"
    }
}

/// 外接屏链路能力探针:读 USB-C DP 链路驱动节点上的 DisplayHints 字典,
/// 取系统自己解析的 MaxBpc(链路最大每通道位数)。实测在本机(Dell 4K
/// USB-C 屏)挂在两类节点上,数据一致,故两处都读再去重。
/// - 不经 IOServiceOpen(与 SMC 的 ioctl 不同),纯注册表属性读取,
///   预期沙盒可用;读不到时静默返回空,面板显示 "--"。
/// - 内建屏无该属性(恒 "--");HDMI 外接屏的驱动节点类名不同,
///   未验证前不盲目枚举,后续接真机 HDMI 屏时再补类名。
enum DisplayLinkCapabilities {
    struct Hint {
        let maxBpc: Int
        let productName: String
        let maxW: Int
        let maxH: Int
    }

    private static let serviceClasses = [
        "AppleATCDPAltModePort",      // USB-C DP AltMode 口
        "AppleDCPDPTXRemotePortUFP",  // DCP DP 发送器远端口
    ]

    static func hints() -> [Hint] {
        var result: [Hint] = []
        for className in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }
            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                guard let dict = IORegistryEntryCreateCFProperty(service, "DisplayHints" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                    let bpc = dict["MaxBpc"] as? Int
                else { continue }
                result.append(Hint(
                    maxBpc: bpc,
                    productName: dict["ProductName"] as? String ?? "",
                    maxW: dict["MaxW"] as? Int ?? 0,
                    maxH: dict["MaxH"] as? Int ?? 0
                ))
            }
        }
        // 同一屏会在两类节点重复上报,按产品名+分辨率去重。
        var seen = Set<String>()
        return result.filter { seen.insert("\($0.productName)|\($0.maxW)x\($0.maxH)|\($0.maxBpc)").inserted }
    }
}

/// 面板属性探针:读 IOMobileFramebufferShim 节点上的 DisplayAttributes
/// (系统已解析好的 EDID 档案:身份/刷新特性/色彩空间声明)。Apple Silicon
/// 上传统 IODisplayConnect 节点已消失,该节点是这类数据的读取来源。
/// 纯注册表属性读取(不走 IOServiceOpen),沙盒可用;读不到静默
/// 返回空,面板展示 "--"。
enum DisplayAttributesProbe {
    struct Attributes {
        let nativeWidth: Int
        let nativeHeight: Int
        let productName: String
        let manufacturerID: String
        let isAppleManufacturer: Bool
        let productID: Int
        let serial: String?
        let weekOfManufacture: Int
        let yearOfManufacture: Int
        let supportsVariableRefreshRate: Bool
        let minRefreshRate: Int
        let maxRefreshRate: Int
        let defaultColorSpaceIsSRGB: Bool?
    }

    static func attributes() -> [Attributes] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferShim"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [Attributes] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            // 只收带 DisplayAttributes 的节点:同一物理屏存在多个 shim
            // 实例,无此字段的实例不携带档案信息。
            guard let dict = IORegistryEntryCreateCFProperty(service, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            else { continue }

            let product = dict["ProductAttributes"] as? [String: Any]
            let manufacturerID = product?["ManufacturerID"] as? String ?? ""
            let legacyManufacturerID = product?["LegacyManufacturerID"] as? Int ?? 0

            // VRR 范围同时存在整数与 16.16 定点两种上报形式,优先整数。
            let vrrMinFixed = dict["MinimumVariableRefreshRate"] as? Int ?? 0
            let vrrMaxFixed = dict["MaximumVariableRefreshRate"] as? Int ?? 0

            // 原生分辨率优先取档案内字段;内建屏档案无此字段时,
            // 用节点级 DisplayWidth/Height 补齐作为对配键。
            let nativeWidth = dict["NativeFormatHorizontalPixels"] as? Int
                ?? intProperty(service, "DisplayWidth")
            let nativeHeight = dict["NativeFormatVerticalPixels"] as? Int
                ?? intProperty(service, "DisplayHeight")

            // 1552 为 Apple 的 EDID 遗留厂商码(另两种形态是数字串厂商码)。
            result.append(Attributes(
                nativeWidth: nativeWidth,
                nativeHeight: nativeHeight,
                productName: product?["ProductName"] as? String ?? "",
                manufacturerID: manufacturerID,
                isAppleManufacturer: legacyManufacturerID == 1552 || manufacturerID.hasPrefix("00-10-fa"),
                productID: product?["ProductID"] as? Int ?? 0,
                serial: product?["AlphanumericSerialNumber"] as? String,
                weekOfManufacture: product?["WeekOfManufacture"] as? Int ?? 0,
                yearOfManufacture: product?["YearOfManufacture"] as? Int ?? 0,
                supportsVariableRefreshRate: (dict["SupportsVariableRefreshRate"] as? Int ?? 0) == 1,
                minRefreshRate: dict["MinimumRefreshRate"] as? Int ?? (vrrMinFixed >> 16),
                maxRefreshRate: dict["MaximumRefreshRate"] as? Int ?? (vrrMaxFixed >> 16),
                defaultColorSpaceIsSRGB: (dict["DefaultColorSpaceIsSRGB"] as? Int).map { $0 != 0 }
            ))
        }
        return result
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int ?? 0
    }
}
