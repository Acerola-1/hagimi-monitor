import AppKit
import SwiftUI

/// 功率流图(冻结原型重制):上排适配器/系统双节点流式布局,下方全宽电池条
/// (填充=电量,旗标=充电限制),短竖导管垂直连到汇流点;导管粗细 ∝ 瓦数。
/// 节点走正常流式布局,连线按容器几何计算绘制,构造上不会重叠。
/// 数据全部来自 BatterySampler 的遥测指标(power-in / power / battery-flow / status),
/// 沙盒版同样可用。活跃导管走辉光 + 相位联动的能量脉冲(充电绿 / 放电黄 /
/// 不足红,颜色语义不受低电量模式影响)。为避免玻璃窗口被逐帧重合成，
/// 连线保持静态，仅随采样数据变化更新。
struct PowerFlowDiagram: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let tint: Color

    private static let nodeWidth: CGFloat = 104
    private static let nodeHeight: CGFloat = 46
    private static let stubHeight: CGFloat = 16
    private static let barHeight: CGFloat = 38

    var body: some View {
        if systemWatts != nil {
            CompatibleGlassContainer(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    flowArea

                    if let note = flowNoteText {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(isInsufficient ? theme.palette.severityTint(for: .critical) : theme.captionText)
                            .lineLimit(2)
                    }
                }
                // 与明细网格同 28pt 缩进,分区标题与图内容左缘对齐。
                .padding(.leading, 28)
            }
        }
    }

    // MARK: 流图区域(边在底层 Canvas,节点与电池条走正常流式布局)

    private var flowArea: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                drawEdges(&context, size: size, time: nil)
            }

            VStack(spacing: Self.stubHeight) {
                HStack(spacing: 36) {
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

    // MARK: 连线

    /// 连线宽度 ∝ 瓦数(苹果风细线:1.8 + √W × 0.14,封顶 3.2;无值 1.8)。
    private func edgeWidth(_ watts: Double?) -> CGFloat {
        guard let watts, watts >= 0.05 else { return 1.8 }
        return min(3.2, 1.8 + sqrt(watts) * 0.14)
    }

    /// 辉光细线:底层同色宽线过 blur 形成柔和光晕,顶层细实线定形。
    private func glowSegment(
        _ context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color,
        width: CGFloat,
        glowAlpha: Double = 0.35
    ) {
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(3, width * 2.6)))
            layer.stroke(line, with: .color(color.opacity(glowAlpha)),
                         style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round))
        }
        context.stroke(line, with: .color(color.opacity(0.92)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawEdges(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval?) {
        let topY = Self.nodeHeight / 2
        let junction = CGPoint(x: size.width / 2, y: topY)
        let adapterRight = CGPoint(x: Self.nodeWidth, y: topY)
        let systemLeft = CGPoint(x: size.width - Self.nodeWidth, y: topY)

        // 无电池台式机:适配器 → 系统一条直通细线辉光,不渲染汇流点与导管。
        if !hasBattery {
            glowSegment(&context, from: adapterRight, to: systemLeft,
                        color: connected ? activeTint : neutralEdge, width: edgeWidth(systemWatts))
            if let time {
                let cycle = max(1.6, min(3.6, 5.2 / (1 + (systemWatts ?? 0) / 30)))
                let u = CGFloat((time / cycle).truncatingRemainder(dividingBy: 1))
                drawPulse(&context, from: adapterRight, to: systemLeft,
                          progress: easeInOutCubic(u), color: connected ? activeTint : edgeShimmer,
                          head: neutralBeamHead,
                          width: edgeWidth(systemWatts))
            }
            return
        }

        // S1/S2 水平线静态本体:状态色辉光细线(左段插电才有,右段恒有)。
        glowSegment(&context, from: adapterRight, to: junction,
                    color: connected ? activeTint : neutralEdge, width: edgeWidth(powerInWatts),
                    glowAlpha: connected ? 0.35 : 0.22)
        glowSegment(&context, from: junction, to: systemLeft,
                    color: activeTint, width: edgeWidth(systemWatts))

        // 相位联动光轨:单一相位沿 适配器→汇流点→系统 全路径行进,
        // 段内缓动,汇流点交接辉光;未插电时左段自动停摆。右段系统恒耗电恒活跃。
        drawLinkedBeams(&context, adapterRight: adapterRight, junction: junction,
                        systemLeft: systemLeft, time: time)

        // 汇流点 ↕ 电池导管:充电绿 / 放电琥珀(适配器不足转红)/ 无流动淡线,
        // 与水平线同一辉光语言;脉冲按流向行进(充电注入电池、放电汇入节点)。
        let stubEnd = CGPoint(x: junction.x, y: Self.nodeHeight + Self.stubHeight)
        switch flowDirection {
        case .charging:
            glowSegment(&context, from: junction, to: stubEnd,
                        color: chargeTint, width: edgeWidth(batteryMagnitude))
            if let time {
                let cycle = max(1.4, min(2.6, 4.0 / (1 + batteryMagnitude / 15)))
                let u = CGFloat((time / cycle).truncatingRemainder(dividingBy: 1))
                drawPulse(&context, from: junction, to: stubEnd,
                          progress: easeInOutCubic(u), color: chargeTint, head: .white.opacity(0.96),
                          width: edgeWidth(batteryMagnitude), tailFraction: 0.3)
            }
        case .discharging:
            let color = isInsufficient
                ? theme.palette.severityTint(for: .critical).opacity(0.85)
                : theme.palette.severityTint(for: .warning).opacity(0.8)
            glowSegment(&context, from: stubEnd, to: junction,
                        color: color, width: edgeWidth(batteryMagnitude), glowAlpha: 0.3)
            if let time {
                let cycle = max(1.4, min(2.6, 4.0 / (1 + batteryMagnitude / 15)))
                let u = CGFloat((time / cycle).truncatingRemainder(dividingBy: 1))
                drawPulse(&context, from: stubEnd, to: junction,
                          progress: easeInOutCubic(u), color: color, head: .white.opacity(0.96),
                          width: edgeWidth(batteryMagnitude), tailFraction: 0.3)
            }
        case .idle:
            glowSegment(&context, from: junction, to: stubEnd,
                        color: neutralEdge, width: 1.8, glowAlpha: 0.22)
        }

        // 汇流点:白色小圆 + 状态色呼吸辉光。
        drawJunctionDot(&context, at: junction, time: time)
    }

    /// 汇流点:底层状态色径向辉光(呼吸放大),顶层白色小圆 + 状态色光晕。
    private func drawJunctionDot(
        _ context: inout GraphicsContext,
        at junction: CGPoint,
        time: TimeInterval?
    ) {
        let breath = time.map { 0.5 + 0.5 * sin($0 * .pi / 1.4) } ?? 0.5
        let color = connected ? activeTint : neutralEdge
        let r = 5 * (1 + 0.25 * breath)
        context.fill(
            Path(ellipseIn: CGRect(x: junction.x - r * 3.2, y: junction.y - r * 3.2,
                                   width: r * 6.4, height: r * 6.4)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.4 * breath + 0.1), color.opacity(0)]),
                center: junction,
                startRadius: 0,
                endRadius: r * 3.2
            )
        )
        let dot = Path(ellipseIn: CGRect(x: junction.x - 2.5, y: junction.y - 2.5, width: 5, height: 5))
        context.fill(dot, with: .color(.white.opacity(0.9 + 0.1 * breath)))
    }

    // MARK: 能量光轨(相位联动脉冲)

    /// 段内加减速缓动:彗星在汇流点前后“减速停靠→加速接棒”,形成交接脉动。
    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// 相位联动光轨:单一相位沿 适配器→汇流点→系统 全路径行进,两段共享时钟,
    /// 能量在汇流点连续交接不断裂;周期/数量 ∝ 总传输瓦数。time 为 nil
    /// (门控关闭)时不绘制。
    private func drawLinkedBeams(
        _ context: inout GraphicsContext,
        adapterRight: CGPoint,
        junction: CGPoint,
        systemLeft: CGPoint,
        time: TimeInterval?
    ) {
        guard let time else { return }
        let lenLeft = junction.x - adapterRight.x
        let lenRight = systemLeft.x - junction.x
        let lenTotal = lenLeft + lenRight
        guard lenTotal > 0 else { return }
        let fJ = lenLeft / lenTotal

        let wattsLeft = connected ? powerInWatts : nil
        let wattsRight = systemWatts ?? 0
        let totalW = (wattsLeft ?? 0) + wattsRight
        guard totalW >= 0.05 else { return }

        let cycle = max(1.6, min(3.6, 5.2 / (1 + totalW / 30)))
        let beams = totalW > 60 ? 2 : 1
        // 脉冲走状态色:充电绿 / 放电黄 / 不足红;头部白点如火花。
        let pulseColor = connected ? activeTint : edgeShimmer
        for k in 0..<beams {
            let u = CGFloat(((time / cycle) + Double(k) / Double(beams)).truncatingRemainder(dividingBy: 1))
            drawJunctionGlow(&context, at: junction, u: u, fJ: fJ, color: pulseColor)
            if u <= fJ {
                guard let wattsLeft, wattsLeft >= 0.05 else { continue }
                drawPulse(&context, from: adapterRight, to: junction,
                          progress: easeInOutCubic(u / fJ),
                          color: pulseColor, head: neutralBeamHead,
                          width: edgeWidth(wattsLeft))
            } else {
                drawPulse(&context, from: junction, to: systemLeft,
                          progress: easeInOutCubic((u - fJ) / (1 - fJ)),
                          color: pulseColor, head: neutralBeamHead,
                          width: edgeWidth(wattsRight))
            }
        }
    }

    /// 汇流点交接辉光:脉冲行经汇流点前后短暂点亮放大,强化能量在此交接分发。
    private func drawJunctionGlow(
        _ context: inout GraphicsContext,
        at junction: CGPoint,
        u: CGFloat,
        fJ: CGFloat,
        color: Color
    ) {
        let d = abs(u - fJ)
        guard d < 0.10 else { return }
        let a = 1 - d / 0.10
        let r = (4.5 + 4 * a) * 2.4
        context.fill(
            Path(ellipseIn: CGRect(x: junction.x - r, y: junction.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.9 * a), color.opacity(0)]),
                center: junction,
                startRadius: 0,
                endRadius: r
            )
        )
    }

    /// 能量脉冲:拖短尾、辉光收敛、渐变陡峭,读感是离散的“能量脉冲包”而非
    /// 连续流带。细导管(<3pt)降级纯色脉冲,不叠加发光层。
    private func drawPulse(
        _ context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        progress: CGFloat,
        color: Color,
        head: Color,
        width: CGFloat,
        tailFraction: CGFloat = 0.20
    ) {
        guard progress > 0.004 else { return }
        let p0 = lerp(from, to, max(0, progress - tailFraction))
        let p1 = lerp(from, to, progress)
        var beam = Path()
        beam.move(to: p0)
        beam.addLine(to: p1)

        if width < 3 {
            context.stroke(beam, with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: max(1.4, width), lineCap: .round))
            let r = max(1.3, width * 0.5)
            context.fill(
                Path(ellipseIn: CGRect(x: p1.x - r, y: p1.y - r, width: r * 2, height: r * 2)),
                with: .color(head.opacity(0.94))
            )
            return
        }

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.2))
            layer.stroke(
                beam,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.35), color.opacity(0.85)]),
                    startPoint: p0,
                    endPoint: p1
                ),
                style: StrokeStyle(lineWidth: width + 1.6, lineCap: .round)
            )
        }
        context.stroke(
            beam,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0), color.opacity(0.55), head.opacity(0.96)]),
                startPoint: p0,
                endPoint: p1
            ),
            style: StrokeStyle(lineWidth: max(1.4, width * 0.6), lineCap: .round)
        )
        let r = max(1.6, width * 0.5)
        context.fill(
            Path(ellipseIn: CGRect(x: p1.x - r, y: p1.y - r, width: r * 2, height: r * 2)),
            with: .color(head.opacity(0.96))
        )
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
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
            adapterLoadBar
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .compatibleLiquidSurface(
            tint: tint.opacity(0.08),
            cornerRadius: 9,
            style: .liquidClear
        ) {
            theme.trackFill
        }
        .opacity(connected ? 1 : 0.4)
    }

    /// 适配器额定负载率细条:实际输入 / 额定瓦数。逼近上限逐级告警色,
    /// 直观预警「适配器不足」场景;未插电时隐藏。
    private var adapterLoadBar: some View {
        let load: Double = {
            guard let powerInWatts, let rated = numericValue("adapter"), rated > 0 else { return 0 }
            return min(1, powerInWatts / rated)
        }()
        let fillColor: Color = if load > 0.92 {
            theme.palette.severityTint(for: .critical)
        } else if load > 0.75 {
            theme.palette.severityTint(for: .warning)
        } else {
            isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
        }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(isDark ? 0.10 : 0.08))
            RoundedRectangle(cornerRadius: 2)
                .fill(fillColor)
                .frame(width: load * (Self.nodeWidth - 28))
        }
        .frame(height: 2.5)
        .padding(.horizontal, 10)
        .opacity(connected ? 1 : 0)
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
        .compatibleLiquidSurface(
            tint: tint.opacity(0.08),
            cornerRadius: 9,
            style: .liquidClear
        ) {
            theme.trackFill
        }
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
                    .frame(width: max(0, CGFloat(module.value) / 100 * geo.size.width - 4),
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
        .compatibleLiquidSurface(
            tint: flowTint.opacity(0.08),
            cornerRadius: 10,
            style: .liquidClear
        ) {
            theme.trackFill
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(barBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // 卡标挂在裁剪层之外,顶端探出条外的部分不被裁掉。
        .overlay(limitTick)
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
                    .offset(x: geo.size.width * CGFloat(limit) / 100 - 4, y: -6)
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
        // 真直供且无 ETA(已充满/达充电限制):展示「直供」状态语,条内信息不断档。
        if status == "ac-power" {
            return String(localized: "panel.power-flow.direct-supply")
        }
        return nil
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
    private enum FlowDirection { case charging, discharging, idle }

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
        let base = String(localized: "panel.power-flow.adapter")
        let rated = rawValue("adapter")
        return rated == "--" ? base : "\(base) · \(rated)"
    }

    /// 适配器节点数值:未插电显「—」;插电但 SystemPowerIn 尚未由固件填出(USB-C PD
    /// 协商/遥测预热窗口)显「采集中」,而非空白或 0——如实表达「已连接、读数在路上」。
    private var adapterValueText: String {
        guard connected else { return "—" }
        if let powerInWatts { return wattString(powerInWatts) }
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

    /// 连线状态色:充电用模块绿;放电用警示黄,适配器不足优先转警示红。
    /// 「充电绿 / 放电黄 / 不足红」整条路径共享同一状态色。
    private var activeTint: Color {
        if isInsufficient { return theme.palette.severityTint(for: .critical) }
        if flowDirection == .discharging { return theme.palette.severityTint(for: .warning) }
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
