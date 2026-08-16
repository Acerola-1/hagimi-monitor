import AppKit
import CoreGraphics
import IOKit
import SwiftUI

/// 单台显示器的信息快照(B4,冻结原型)。
/// 分辨率/刷新率/HDR 走公开 API,双渠道可用;亮度与 DDC 支持仅 Direct 版回填。
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let resolution: String
    let refreshRate: String
    /// HDR(EDR)当前是否开启;nil = 该显示器不支持 EDR,展示"—"。
    let hdrOn: Bool?
    /// 链路最大位深(如 "10 bit"),来自系统驱动 DisplayHints 的 MaxBpc;
    /// 内建屏与未适配的 HDMI 外接读不到,显示 "--"。口径为「链路/面板
    /// 支持的最大每通道位数」:8bit+FRC 面板同样上报 10,与 Dell/Apple
    /// 官网「10.7 亿色 / 1 billion colors」的标称口径一致。
    let colorDepth: String
    /// 内建屏亮度百分比(Direct 独有,沙盒无私有接口)。
    var brightnessPercent: Int? = nil
    /// 是否支持 DDC 控制(Direct 独有)。
    var supportsDDC: Bool? = nil
}

/// 显示器信息区(B4,两渠道通用,冻结原型):行头"N 台 · 外接 M",
/// 展开后按显示器分节展示分辨率/刷新率/HDR 等信息。
/// 数据全部来自公开 API(CGDisplay + NSScreen),沙盒安全;
/// 亮度/DDC 两项由 Direct 版通过 #if DISPLAY_CONTROL 钩子回填。
struct DisplayInfoSection: View {
    let theme: MonitorPanelTheme
    /// 展开/收起前的窗口层动画同步钩子(与其他模块行同一机制):
    /// FluidPanelController 的窗口尺寸动画由此启动,与内容高度补间同速合拍。
    var beginExpansionAnimation: () -> Void = {}

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

            CollapsibleDetail(isExpanded: isExpanded && !displays.isEmpty) {
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
            // 与其他模块行同款展开动画:窗口层与内容高度补间同时同速,
            // 缺了这一步会表现为「内容突然出现/消失」。
            beginExpansionAnimation()
            withAnimation(.easeInOut(duration: MonitorConstants.panelExpansionDuration)) {
                isExpanded.toggle()
            }
        }
        .compatibleGlassEffect(tint: theme.palette.displayGlassTint, cornerRadius: MonitorConstants.rowCornerRadius)
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
        let external = displays.filter { !$0.isBuiltIn }.count
        return String(format: String(localized: "panel.displays.summary"), displays.count, external)
    }

    // MARK: 单台显示器分节

    @ViewBuilder
    private func displaySection(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(display.name)
                    .monitorPanelLabelFont(tracking: 0.8)
                    .foregroundStyle(theme.captionText)
                    .fixedSize()
                Rectangle()
                    .fill(theme.palette.displaySeparator)
                    .frame(height: 1)
            }
            .padding(.leading, 28)

            VStack(spacing: 7) {
                HStack(spacing: 16) {
                    cell(label: String(localized: "metric.display.resolution"), value: display.resolution)
                    cell(label: String(localized: "metric.display.refresh-rate"), value: display.refreshRate)
                }
                HStack(spacing: 16) {
                    cell(
                        label: "HDR",
                        value: display.hdrOn.map {
                            $0 ? String(localized: "metric-value.on") : String(localized: "metric-value.off")
                        } ?? "--"
                    )
                    cell(label: String(localized: "metric.display.color-depth"), value: display.colorDepth)
                }
                // 亮度/DDC 视条件单行殿后,与上方四项基本信息互不挤占。
                if display.isBuiltIn, let brightness = display.brightnessPercent {
                    cell(label: String(localized: "metric.display.brightness"), value: "\(brightness)%")
                } else if !display.isBuiltIn, let supportsDDC = display.supportsDDC {
                    cell(
                        label: "DDC",
                        value: supportsDDC ? String(localized: "metric.display.ddc-available") : "--",
                        emphasized: supportsDDC
                    )
                }
            }
            .padding(.leading, 28)
        }
    }

    /// 明细单元格:与 MetricDetailGrid 同构(label 左 caption 色 / 值右 mono 次要色)。
    private func cell(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 6)

            Text(value)
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(emphasized ? theme.palette.severityTint(for: .calm) : theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // 链路能力探针整个采集只读一次,再与各显示器对配。
        let linkHints = DisplayLinkCapabilities.hints()
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

            // HDR:用 NSScreen 的 EDR 分量判定——
            // maximumPotential > 1 表示具备 EDR 能力;maximum(当前可用) > 1 表示正处 HDR 增益态。
            var hdrOn: Bool? = nil
            if let screen, screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.01 {
                hdrOn = screen.maximumExtendedDynamicRangeColorComponentValue > 1.01
            }

            var info = DisplayInfo(
                id: id,
                name: screen?.localizedName ?? "Display \(id)",
                isBuiltIn: builtIn,
                resolution: resolution,
                refreshRate: refreshRate,
                hdrOn: hdrOn,
                colorDepth: Self.linkColorDepth(
                    hints: linkHints,
                    displayName: screen?.localizedName,
                    width: mode?.pixelWidth ?? 0,
                    height: mode?.pixelHeight ?? 0
                )
            )

            #if DISPLAY_CONTROL
            // 亮度与 DDC 依赖私有接口,仅 Direct 版回填(见 DisplayInfoSupport)。
            if builtIn {
                info.brightnessPercent = displayInfoBrightnessPercent(id)
            }
            info.supportsDDC = displayInfoSupportsDDC(id)
            #endif

            return info
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
