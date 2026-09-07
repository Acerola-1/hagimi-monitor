import AppKit
import SwiftUI

/// 功率流图(冻结原型重制):上排适配器/系统双节点流式布局,下方全宽电池条
/// (填充=电量,旗标=充电限制),短竖导管垂直连到汇流点;导管粗细 ∝ 瓦数。
/// 节点走正常流式布局,连线按容器几何计算绘制,构造上不会重叠。
/// 数据全部来自 BatterySampler 的遥测指标(power-in / power / battery-flow / status),
/// 沙盒版同样可用。活跃导管走硬件加速虚线流光管线(CAShapeLayer lineDashPhase 独立合成,
/// 充电绿 / 放电黄 / 不足红,颜色语义不受低电量模式影响),充放电物理反向流动。
/// 仅展开且面板可见时启动 Core Animation,主线程 0 负载,收起/隐藏即暂停。
struct PowerFlowDiagram: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let tint: Color
    /// 流光动画门控:仅当行展开且面板可见时为 true。
    let animate: Bool

    private static let nodeWidth: CGFloat = 90
    private static let nodeHeight: CGFloat = 46
    private static let stubHeight: CGFloat = 16
    private static let barHeight: CGFloat = 38

    var body: some View {
        if systemWatts != nil {
            VStack(alignment: .leading, spacing: 7) {
                flowArea

                if let note = flowNoteText {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(isInsufficient ? theme.palette.severityTint(for: .critical) : theme.captionText)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: 流图区域(底层硬件加速流光导轨,节点与电池条走正常流式布局)

    private var flowArea: some View {
        ZStack(alignment: .top) {
            PowerFlowHardwareTracksView(
                hasBattery: hasBattery,
                connected: connected,
                flowDirection: flowDirection,
                powerInWatts: powerInWatts,
                systemWatts: systemWatts,
                batteryMagnitude: batteryMagnitude,
                activeTint: activeTint,
                chargeTint: chargeTint,
                dischargeTint: dischargeTint,
                neutralEdge: neutralEdge,
                edgeShimmer: edgeShimmer,
                animate: animate
            )

            VStack(spacing: Self.stubHeight) {
                HStack(spacing: 0) {
                    adapterNode
                    Spacer(minLength: 0)
                    systemNode
                }

                if hasBattery {
                    batteryBar
                }
            }
        }
        .frame(height: hasBattery ? Self.nodeHeight + Self.stubHeight + Self.barHeight : Self.nodeHeight)
    }

    // MARK: 节点

    private var adapterNode: some View {
        VStack(spacing: 1) {
            Text(adapterLabel)
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(adapterValueText)
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.trackFill))
        .opacity(connected ? 1 : 0.4)
        .help(adapterHelpText)
    }

    /// 悬浮提示:展示 PD 握手档位与实测电压电流。
    private var adapterHelpText: String {
        guard connected else { return adapterLabel }
        var parts: [String] = []
        let contract = rawValue("pd-contract")
        if contract != "--" {
            parts.append(String(format: String(localized: "panel.power-flow.tooltip.pd-contract"), contract))
        }
        let telemetry = rawValue("input-telemetry")
        if telemetry != "--" {
            parts.append(String(format: String(localized: "panel.power-flow.tooltip.input-telemetry"), telemetry))
        }
        if parts.isEmpty {
            return adapterLabel
        }
        return parts.joined(separator: "\n")
    }

    private var systemNode: some View {
        VStack(spacing: 1) {
            Text(String(localized: "panel.power-flow.system"))
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
            Text(wattString(systemWatts))
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.trackFill))
    }

    // MARK: 全宽电池条

    /// 电池从「节点」升级为「全宽容器」:填充 = 电量百分比,卡标 = 系统充电限制;
    /// 左侧电量+状态、右侧 ETA 走 flex 两端对齐,文字永不碰撞。卡标从条外
    /// 上缘插入、止于条体上半,既传达「上限卡在这里」又不碰中部文字。
    /// 任何电源状态(含插电直供)都承载信息,不再出现「下半图空白」。
    private var batteryBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(barFillGradient)
                    .frame(width: max(0, CGFloat(module.value) / 100 * (geo.size.width - 4)),
                           height: geo.size.height - 4)
                    .offset(x: 2)

                HStack(spacing: 6) {
                    Text(percent(module.value))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(barTextPrimary)
                    Text(barStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(barTextSecondary)
                    Spacer(minLength: 8)
                    if let eta = barEtaText {
                        Text(eta)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(barTextSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 深色模式填充上的白字需要轻投影保可读性;浅色模式用深字不投影。
                .shadow(color: .black.opacity(isDark ? 0.45 : 0), radius: 2, x: 0, y: 1)
            }
        }
        .frame(height: Self.barHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.trackFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(barBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // 顶部正中接驳端子:垂直导管由此落入电池条
        .overlay(alignment: .top) {
            socketTab
        }
        // 卡标挂在裁剪层之外,顶端探出条外的部分不被裁掉。
        .overlay(limitTick)
    }

    /// 电池顶部接驳端子(Socket Tab):微型凹槽与接触片,垂直导管在此插接。
    private var socketTab: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.trackFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .stroke(barBorder, lineWidth: 1)
                )
            RoundedRectangle(cornerRadius: 1)
                .fill(activeTint.opacity(flowDirection == .idle ? 0.30 : 0.70))
                .frame(width: 8, height: 1.5)
        }
        .frame(width: 16, height: 4)
        .offset(y: -2.5)
    }

    /// 充电上限卡标(冻结原型「方案 B 旗标」):条外上缘倒三角旗头 + 细线下探
    /// 进条体上半(止于中部文字带之上),视觉上像从外部插进电池标记上限位置;
    /// 与电量填充同用百分比定位,随条宽自适应。旗头探出条外,故挂在裁剪层之外。
    private var limitTick: some View {
        GeometryReader { geo in
            if let limit = numericValue("charge-limit"), limit < 100 {
                LimitFlagShape()
                    .fill(isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.42))
                    .frame(width: 8, height: 19)
                    .offset(x: 2 + (geo.size.width - 4) * CGFloat(limit) / 100 - 4, y: -6)
            }
        }
    }

    private var barFillGradient: LinearGradient {
        if isInsufficient {
            return LinearGradient(
                colors: [
                    theme.palette.severityTint(for: .critical).opacity(0.45),
                    theme.palette.severityTint(for: .warning).opacity(0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [flowTint.opacity(0.60), flowTint.opacity(0.28)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var barBorder: Color {
        if isCharging { return flowTint.opacity(0.45) }
        if isInsufficient { return theme.palette.severityTint(for: .critical).opacity(0.5) }
        return .clear
    }

    private var barTextPrimary: Color {
        isDark ? .white : Color.black.opacity(0.78)
    }

    private var barTextSecondary: Color {
        isDark ? Color.white.opacity(0.78) : Color.black.opacity(0.60)
    }

    private var barStatusText: String {
        switch status {
        case "charging": return localizedBatteryState("charging")
        case "on-battery": return localizedBatteryState("on-battery")
        case "maintain":
            // 适配器不足是 maintain 的告警子态(输入顶到额定仍放电补差),优先展示。
            return isInsufficient
                ? String(localized: "battery-state.insufficient")
                : localizedBatteryState("maintain")
        default:
            return localizedBatteryState("ac-power")
        }
    }

    private var barEtaText: String? {
        if let eta = etaText { return eta }
        // 仅当插电且未在充电（交流直供、达限维持或优化充电保护）时展示硬件停充原因细化说明
        if connected && !isCharging {
            return notChargingExplanation
        }
        return nil
    }

    /// 停充硬件原因解释:插电但未充电时的状态文案细化。
    /// 区分「已充满直供」、「已达上限维持」、「优化电池充电保护中」与常规「直供中」。
    private var notChargingExplanation: String {
        let reason = numericValue("not-charging-reason").map(Int.init) ?? 0
        let chargingAllowed = numericValue("charging-allowed").map(Int.init)
        let limit = numericValue("charge-limit").map(Int.init)
        let pct = Int(module.value.rounded())

        // 满电直供
        if pct >= 100 {
            return String(localized: "panel.power-flow.fully-charged")
        }
        // 0x01000000 (16777216): 达限维持 (NotChargingReason bit 24 或固件不允许充电且达到电量上限)
        if (reason & 0x01000000) != 0 || (chargingAllowed == 0 && (limit != nil && pct >= (limit! - 1))) {
            return String(localized: "panel.power-flow.hold-limit")
        }
        // 其它非零停充原因: 优化电池充电或温控保护
        if reason != 0 {
            return String(localized: "panel.power-flow.optimized-protection")
        }
        // 默认交流直供
        return String(localized: "panel.power-flow.direct-supply")
    }

    // MARK: 说明与迷你曲线

    /// 图下说明行:只在需要警示的「适配器不足」场景出现;常规态(充电/直供/
    /// 电池供电/无电池)的瓦数、损耗、ETA 已分别在节点、明细网格与电池条内
    /// 展示,不再重复拼长句。
    private var flowNoteText: String? {
        guard connected, hasBattery, isInsufficient else { return nil }
        let magnitude = String(format: "%.1fW", batteryMagnitude)
        return String(format: String(localized: "panel.power-flow.note.insufficient"), magnitude)
    }

    // MARK: 数据

    private var isDark: Bool {
        theme.palette.colorScheme == .dark
    }

    private var hasBattery: Bool {
        rawValue("type") == "battery"
    }

    private var status: String {
        rawValue("status")
    }

    private var connected: Bool {
        status == "charging" || status == "ac-power" || status == "maintain"
    }

    private var systemWatts: Double? {
        numericValue("power")
    }

    private var powerInWatts: Double? {
        numericValue("power-in")
    }

    /// 电池流向方向,只依据 IOPS 的充电/连接状态判定(status 由 BatterySampler
    /// 依据 kIOPSIsChargingKey / kIOPSPowerSourceStateKey 产出):BatteryPower 的
    /// 符号约定随机型/系统版本不同,不作为方向依据。
    enum FlowDirection { case charging, discharging, idle }

    private var flowDirection: FlowDirection {
        switch status {
        case "charging": return .charging
        case "on-battery", "maintain": return .discharging
        default: return .idle // ac-power:插电且不充电(如满电)
        }
    }

    private var isCharging: Bool { flowDirection == .charging }

    /// 适配器不足:电池放电补差,且适配器输入已逼近额定瓦数(弱适配器带高负载)。
    /// 充电上限维持等策略性放电同样伴随电池放电,但其输入接近零(系统主动
    /// 断输入),与真正的适配器供电不足区分。
    private var isInsufficient: Bool {
        guard connected, (numericValue("battery-flow") ?? 0) < -0.05,
              let powerIn = powerInWatts, let rated = numericValue("adapter"), rated > 0 else {
            return false
        }
        return powerIn / rated > 0.85
    }

    /// 电池流向功率幅度(恒非负)。放电时若遥测尚未刷新(拔电瞬间为 0),用系统
    /// 负载兜底——脱离适配器后系统功耗全部由电池提供。idle 态电池静止。
    private var batteryMagnitude: Double {
        let flow = abs(numericValue("battery-flow") ?? 0)
        switch flowDirection {
        case .discharging: return flow >= 0.05 ? flow : (systemWatts ?? 0)
        case .charging: return flow
        case .idle: return 0
        }
    }

    private var adapterLabel: String {
        let base = hasBattery
            ? String(localized: "panel.power-flow.adapter")
            : String(localized: "battery-state.ac-power")
        let rated = rawValue("adapter")
        return rated == "--" ? base : "\(base) · \(rated)"
    }

    /// 适配器节点数值:未插电显「—」;插电但 SystemPowerIn 尚未由固件填出(USB-C PD
    /// 协商/遥测预热窗口)显「采集中」,而非空白或 0——如实表达「已连接、读数在路上」。
    /// 桌面无电池机型若无遥测瓦数，回退显示交流供电状态而非停留在采集中。
    private var adapterValueText: String {
        guard connected else { return "—" }
        if let powerInWatts { return wattString(powerInWatts) }
        if !hasBattery {
            return String(localized: "battery-state.ac-power")
        }
        return String(localized: "panel.power-flow.collecting")
    }

    private var etaText: String? {
        guard let minutes = numericValue("time-remaining").map(Int.init), minutes > 0 else { return nil }
        let text = Self.durationFormatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
        if status == "charging" {
            return String(format: String(localized: "panel.power-flow.eta-full"), text)
        }
        if status == "on-battery" {
            return String(format: String(localized: "panel.power-flow.eta-empty"), text)
        }
        return nil
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: 配色

    /// 低电量模式:电池条填充/边框转琥珀,系统限电状态在图内直接可读;
    /// 流向导管不参与变色——充电绿/放电黄的流向语义恒定(见 activeTint)。
    private var isLowPowerMode: Bool {
        hasBattery && rawValue("low-power-mode") == "on"
    }

    /// 功率流有效主题色:低电量模式时覆盖为 warning 琥珀——只作用于电池条
    /// (填充/边框),表达「电池处于省电状态」;流向导管的颜色不随之变黄,
    /// 见 chargeTint / activeTint。适配器不足的红色判定在 barFillGradient/
    /// barBorder 内优先于本值。
    private var flowTint: Color {
        isLowPowerMode ? theme.palette.severityTint(for: .warning) : tint
    }

    /// 充电流向底色:模块绿,任何模式下恒定——「正在充电」这条语义不应被
    /// 低电量模式染黄,低电量琥珀由电池条独立承载。
    private var chargeTint: Color { tint }

    /// 放电流向底色:电池供电是正常工况，不应默认呈现警示黄；
    /// 仅在开启低电量模式或电量偏低(<=20%)时呈现琥珀警示色，平时保持通透健康的模块主色。
    private var dischargeTint: Color {
        if isInsufficient { return theme.palette.severityTint(for: .critical) }
        if isLowPowerMode || module.value <= 20 {
            return theme.palette.severityTint(for: .warning)
        }
        return tint
    }

    /// 连线状态色:整条能量流动路径的状态色。
    /// 充电用模块绿;适配器不足转红;放电时仅低电量/低电模式转警示黄,平时保持模块绿。
    private var activeTint: Color {
        if isInsufficient { return theme.palette.severityTint(for: .critical) }
        if flowDirection == .discharging { return dischargeTint }
        return tint
    }

    private var neutralEdge: Color {
        isDark ? Color.white.opacity(0.36) : Color.black.opacity(0.30)
    }

    /// 中性导管上的流动亮色:比导管底色亮一档,流动可辨但不张扬。
    private var edgeShimmer: Color {
        isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.4)
    }

    /// 中性导管光轨头部:暗色底亮白、浅色底深色,与导管语言一致;
    /// 语义导管(充电/放电)头部直接用白点,像火花。
    private var neutralBeamHead: Color {
        isDark ? .white : Color.black.opacity(0.6)
    }

    private func rawValue(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }

    private func numericValue(_ name: String) -> Double? {
        module.metrics.first { $0.name == name }?.numericValue
    }
}

/// 充电上限旗标形状:顶端倒三角旗头(底边在上、尖朝下) + 自旗头尖端下探的
/// 细圆头竖线,单一填充色整形绘制。
private struct LimitFlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headHeight: CGFloat = 5
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + headHeight))
        path.closeSubpath()
        let lineWidth: CGFloat = 1.5
        path.addRoundedRect(
            in: CGRect(x: rect.midX - lineWidth / 2, y: rect.minY + headHeight,
                       width: lineWidth, height: rect.height - headHeight),
            cornerSize: CGSize(width: lineWidth / 2, height: lineWidth / 2)
        )
        return path
    }
}

// MARK: - 硬件加速功率流导轨与虚线流光

private extension Color {
    func toCGColor() -> CGColor {
        if let cgColor = self.cgColor {
            return cgColor
        }
        if #available(macOS 14.0, *) {
            return resolve(in: EnvironmentValues()).cgColor
        }
        return NSColor.white.cgColor
    }
}

/// 功率流导轨与硬件加速虚线流光视图。
/// 采用 NSViewRepresentable 承载 CAShapeLayer 与 Core Animation（lineDashPhase），
/// 在 Render Server 独立硬件加速呈现能量脉冲流动，主线程 CPU 占用降为 0%。
private struct PowerFlowHardwareTracksView: NSViewRepresentable {
    let hasBattery: Bool
    let connected: Bool
    let flowDirection: PowerFlowDiagram.FlowDirection
    let powerInWatts: Double?
    let systemWatts: Double?
    let batteryMagnitude: Double
    let activeTint: Color
    let chargeTint: Color
    let dischargeTint: Color
    let neutralEdge: Color
    let edgeShimmer: Color
    let animate: Bool

    func makeNSView(context: Context) -> PowerFlowTracksNSView {
        PowerFlowTracksNSView()
    }

    func updateNSView(_ nsView: PowerFlowTracksNSView, context: Context) {
        nsView.update(
            hasBattery: hasBattery,
            connected: connected,
            flowDirection: flowDirection,
            powerInWatts: powerInWatts,
            systemWatts: systemWatts,
            batteryMagnitude: batteryMagnitude,
            activeTint: activeTint.toCGColor(),
            chargeTint: chargeTint.toCGColor(),
            dischargeTint: dischargeTint.toCGColor(),
            neutralEdge: neutralEdge.toCGColor(),
            edgeShimmer: edgeShimmer.toCGColor(),
            animate: animate
        )
    }
}

private final class PowerFlowTracksNSView: NSView {
    override var isFlipped: Bool { true }

    private static let nodeWidth: CGFloat = 90
    private static let nodeHeight: CGFloat = 46
    private static let stubHeight: CGFloat = 16
    private static let dashLength: CGFloat = 8
    private static let gapLength: CGFloat = 12
    private static let dashPeriod: CGFloat = 20
    private static let flowLineWidth: CGFloat = 2.2
    private static let flowAnimationDuration: CFTimeInterval = 1.8
    private static let powerThreshold: Double = 0.3

    // 静态底层导轨（辉光 + 实体）
    private let baseGlowLeft = CAShapeLayer()
    private let baseTrackLeft = CAShapeLayer()
    private let baseGlowRight = CAShapeLayer()
    private let baseTrackRight = CAShapeLayer()
    private let baseGlowVertical = CAShapeLayer()
    private let baseTrackVertical = CAShapeLayer()

    // 硬件加速流光层（虚线平移）
    private let dashLayerLeft = CAShapeLayer()
    private let dashLayerRight = CAShapeLayer()
    private let dashLayerVertical = CAShapeLayer()

    // 汇流点层（呼吸辉光 + 中心点）
    private let junctionContainer = CALayer()
    private let junctionGlowLayer = CAGradientLayer()
    private let junctionDotLayer = CALayer()

    // 状态缓存
    private var hasBattery = true
    private var connected = false
    private var flowDirection: PowerFlowDiagram.FlowDirection = .idle
    private var powerInWatts: Double?
    private var systemWatts: Double?
    private var batteryMagnitude: Double = 0
    private var activeTint: CGColor = NSColor.white.cgColor
    private var chargeTint: CGColor = NSColor.white.cgColor
    private var dischargeTint: CGColor = NSColor.white.cgColor
    private var neutralEdge: CGColor = NSColor.gray.cgColor
    private var edgeShimmer: CGColor = NSColor.white.cgColor
    private var animate = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        guard let layer = self.layer else { return }

        // 底轨辉光与实体线
        for glow in [baseGlowLeft, baseGlowRight, baseGlowVertical] {
            glow.fillColor = nil
            glow.lineCap = .round
            layer.addSublayer(glow)
        }
        for track in [baseTrackLeft, baseTrackRight, baseTrackVertical] {
            track.fillColor = nil
            track.lineCap = .round
            layer.addSublayer(track)
        }

        // 硬件合成虚线流光
        for dash in [dashLayerLeft, dashLayerRight, dashLayerVertical] {
            dash.fillColor = nil
            dash.lineCap = .round
            dash.lineWidth = Self.flowLineWidth
            dash.lineDashPattern = [NSNumber(value: Double(Self.dashLength)), NSNumber(value: Double(Self.gapLength))]
            dash.shadowOffset = .zero
            dash.shadowRadius = 2.0
            dash.shadowOpacity = 0.5
            layer.addSublayer(dash)
        }

        // 汇流点呼吸辉光与中心白点
        junctionGlowLayer.type = .radial
        junctionGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        junctionGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        junctionContainer.addSublayer(junctionGlowLayer)

        junctionDotLayer.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        junctionContainer.addSublayer(junctionDotLayer)

        layer.addSublayer(junctionContainer)
    }

    func update(
        hasBattery: Bool,
        connected: Bool,
        flowDirection: PowerFlowDiagram.FlowDirection,
        powerInWatts: Double?,
        systemWatts: Double?,
        batteryMagnitude: Double,
        activeTint: CGColor,
        chargeTint: CGColor,
        dischargeTint: CGColor,
        neutralEdge: CGColor,
        edgeShimmer: CGColor,
        animate: Bool
    ) {
        self.hasBattery = hasBattery
        self.connected = connected
        self.flowDirection = flowDirection
        self.powerInWatts = powerInWatts
        self.systemWatts = systemWatts
        self.batteryMagnitude = batteryMagnitude
        self.activeTint = activeTint
        self.chargeTint = chargeTint
        self.dischargeTint = dischargeTint
        self.neutralEdge = neutralEdge
        self.edgeShimmer = edgeShimmer
        self.animate = animate

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updatePathsAndGeometry()
        updateLayerStyling()
        updateAnimations()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updatePathsAndGeometry()
        updateLayerStyling()
        updateAnimations()
        CATransaction.commit()
    }

    private static func edgeWidth(_ watts: Double?) -> CGFloat {
        guard let watts, watts >= 0.05 else { return 1.8 }
        return min(3.2, 1.8 + sqrt(watts) * 0.14)
    }

    private func updatePathsAndGeometry() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        let topY = Self.nodeHeight / 2
        let junction = CGPoint(x: w / 2, y: topY)
        let adapterRight = CGPoint(x: Self.nodeWidth, y: topY)
        let systemLeft = CGPoint(x: w - Self.nodeWidth, y: topY)
        let stubEnd = CGPoint(x: w / 2, y: Self.nodeHeight + Self.stubHeight)

        if !hasBattery {
            // 无电池台式机:适配器 → 系统一条直通导轨
            let desktopPath = CGMutablePath()
            desktopPath.move(to: adapterRight)
            desktopPath.addLine(to: systemLeft)

            baseTrackLeft.path = desktopPath
            baseGlowLeft.path = desktopPath
            dashLayerLeft.path = desktopPath

            baseTrackRight.isHidden = true
            baseGlowRight.isHidden = true
            dashLayerRight.isHidden = true

            baseTrackVertical.isHidden = true
            baseGlowVertical.isHidden = true
            dashLayerVertical.isHidden = true

            junctionContainer.isHidden = true
            return
        }

        // 有电池笔记本:左段(适配器→汇流点)
        let leftPath = CGMutablePath()
        leftPath.move(to: adapterRight)
        leftPath.addLine(to: junction)

        baseTrackLeft.path = leftPath
        baseGlowLeft.path = leftPath
        dashLayerLeft.path = leftPath
        baseTrackLeft.isHidden = false
        baseGlowLeft.isHidden = false

        // 右段(汇流点→系统)
        let rightPath = CGMutablePath()
        rightPath.move(to: junction)
        rightPath.addLine(to: systemLeft)

        baseTrackRight.path = rightPath
        baseGlowRight.path = rightPath
        dashLayerRight.path = rightPath
        baseTrackRight.isHidden = false
        baseGlowRight.isHidden = false

        // 垂直段(汇流点 ↕ 电池)
        let vertBasePath = CGMutablePath()
        vertBasePath.move(to: junction)
        vertBasePath.addLine(to: stubEnd)

        baseTrackVertical.path = vertBasePath
        baseGlowVertical.path = vertBasePath
        baseTrackVertical.isHidden = false
        baseGlowVertical.isHidden = false

        // 硬件物理流向:充电时汇流点下探入电池;放电时电池上涌入汇流点
        let vertDashPath = CGMutablePath()
        switch flowDirection {
        case .charging:
            vertDashPath.move(to: junction)
            vertDashPath.addLine(to: stubEnd)
            dashLayerVertical.path = vertDashPath
        case .discharging:
            vertDashPath.move(to: stubEnd)
            vertDashPath.addLine(to: junction)
            dashLayerVertical.path = vertDashPath
        case .idle:
            dashLayerVertical.path = nil
        }

        // 汇流点
        junctionContainer.isHidden = false
        junctionContainer.position = junction

        let glowSize: CGFloat = 28
        junctionGlowLayer.bounds = CGRect(x: 0, y: 0, width: glowSize, height: glowSize)
        junctionGlowLayer.position = .zero
        junctionGlowLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        junctionGlowLayer.cornerRadius = glowSize / 2

        let dotSize: CGFloat = 4
        junctionDotLayer.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        junctionDotLayer.position = .zero
        junctionDotLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        junctionDotLayer.cornerRadius = dotSize / 2
    }

    private func updateLayerStyling() {
        // 左段样式
        let leftColor = connected ? activeTint : neutralEdge
        let leftGlowAlpha: CGFloat = connected ? 0.35 : 0.22
        let effectiveWatts = hasBattery ? (connected ? powerInWatts : nil) : (systemWatts ?? powerInWatts)
        let wLeft = Self.edgeWidth(effectiveWatts)
        baseTrackLeft.lineWidth = wLeft
        baseGlowLeft.lineWidth = wLeft * 2.4
        baseTrackLeft.strokeColor = leftColor.copy(alpha: 0.92) ?? leftColor
        baseGlowLeft.strokeColor = leftColor.copy(alpha: leftGlowAlpha) ?? leftColor

        let leftDashColor = connected ? activeTint : edgeShimmer
        dashLayerLeft.strokeColor = leftDashColor
        dashLayerLeft.shadowColor = leftDashColor

        // 右段样式
        let wRight = Self.edgeWidth(systemWatts)
        baseTrackRight.lineWidth = wRight
        baseGlowRight.lineWidth = wRight * 2.4
        baseTrackRight.strokeColor = activeTint.copy(alpha: 0.92) ?? activeTint
        baseGlowRight.strokeColor = activeTint.copy(alpha: 0.35) ?? activeTint
        dashLayerRight.strokeColor = activeTint
        dashLayerRight.shadowColor = activeTint

        // 垂直段样式
        let vColor: CGColor
        let vGlowAlpha: CGFloat
        switch flowDirection {
        case .charging:
            vColor = chargeTint
            vGlowAlpha = 0.35
        case .discharging:
            vColor = dischargeTint
            vGlowAlpha = 0.30
        case .idle:
            vColor = neutralEdge
            vGlowAlpha = 0.22
        }
        let wVert = (flowDirection == .idle) ? 1.8 : Self.edgeWidth(batteryMagnitude)
        baseTrackVertical.lineWidth = wVert
        baseGlowVertical.lineWidth = wVert * 2.4
        baseTrackVertical.strokeColor = vColor.copy(alpha: 0.92) ?? vColor
        baseGlowVertical.strokeColor = vColor.copy(alpha: vGlowAlpha) ?? vColor

        let vertDashColor = (flowDirection == .charging) ? chargeTint : dischargeTint
        dashLayerVertical.strokeColor = vertDashColor
        dashLayerVertical.shadowColor = vertDashColor
    }

    private func updateAnimations() {
        let isLeftActive: Bool
        if !hasBattery {
            isLeftActive = animate && (systemWatts ?? 0) >= Self.powerThreshold
        } else {
            isLeftActive = animate && connected && (powerInWatts ?? 0) >= Self.powerThreshold
        }

        let isRightActive = hasBattery && animate && (systemWatts ?? 0) >= Self.powerThreshold
        let isVerticalActive = hasBattery && animate && (flowDirection != .idle) && (batteryMagnitude >= Self.powerThreshold)
        let isJunctionBreathing = hasBattery && animate && (connected || (systemWatts ?? 0) >= Self.powerThreshold)

        updateDashAnimation(layer: dashLayerLeft, active: isLeftActive)
        updateDashAnimation(layer: dashLayerRight, active: isRightActive)
        updateDashAnimation(layer: dashLayerVertical, active: isVerticalActive)
        updateJunctionBreathing(active: isJunctionBreathing)
    }

    private func updateDashAnimation(layer: CAShapeLayer, active: Bool) {
        let animKey = "dashFlowAnimation"
        if active {
            layer.isHidden = false
            if layer.animation(forKey: animKey) == nil {
                let anim = CABasicAnimation(keyPath: "lineDashPhase")
                anim.fromValue = 0.0
                anim.toValue = -Double(Self.dashPeriod)
                anim.duration = Self.flowAnimationDuration
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .linear)
                anim.isRemovedOnCompletion = false
                layer.add(anim, forKey: animKey)
            }
        } else {
            layer.isHidden = true
            layer.removeAnimation(forKey: animKey)
        }
    }

    private func updateJunctionBreathing(active: Bool) {
        let breatheAnimKey = "junctionBreathe"
        let baseColor = connected ? activeTint : neutralEdge
        junctionGlowLayer.colors = [
            baseColor.copy(alpha: 0.65) ?? baseColor,
            baseColor.copy(alpha: 0.0) ?? baseColor
        ]

        if active {
            if junctionGlowLayer.animation(forKey: breatheAnimKey) == nil {
                let group = CAAnimationGroup()
                group.duration = 1.4
                group.autoreverses = true
                group.repeatCount = .infinity
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                group.isRemovedOnCompletion = false

                let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
                scaleAnim.fromValue = 0.85
                scaleAnim.toValue = 1.25

                let opacityAnim = CABasicAnimation(keyPath: "opacity")
                opacityAnim.fromValue = 0.35
                opacityAnim.toValue = 0.85

                group.animations = [scaleAnim, opacityAnim]
                junctionGlowLayer.add(group, forKey: breatheAnimKey)
            }
        } else {
            junctionGlowLayer.removeAnimation(forKey: breatheAnimKey)
            junctionGlowLayer.transform = CATransform3DIdentity
            junctionGlowLayer.opacity = 0.4
        }
    }
}

