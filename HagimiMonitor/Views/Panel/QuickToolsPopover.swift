import AppKit
import CoreGraphics
import SwiftUI

/// 快捷功能条目。键盘锁定双渠道均为事件 tap 拦截
/// (见 KeyboardLockController),解锁入口即本磁贴开关。
enum QuickToolKind: CaseIterable {
    case keyboardLock
    case systemAwake
    case displayAwake

    var titleKey: String.LocalizationValue {
        switch self {
        case .keyboardLock: "quicktools.keyboard-lock"
        case .systemAwake: "quicktools.system-awake"
        case .displayAwake: "quicktools.display-awake"
        }
    }

    var symbol: String {
        switch self {
        case .keyboardLock: "keyboard"
        case .systemAwake: "laptopcomputer"
        case .displayAwake: "sun.max"
        }
    }
}

/// 每个入口按钮实例独享的锚点盒:面板每秒重渲染会重建视图树,@State
/// 持有的盒子跨渲染存活,宿主 NSView 换新时同步弱引用。菜单栏面板与
/// 钉住面板各持一个实例,浮层始终锚定到实际被点击的那块面板。
@MainActor
final class QuickToolsAnchorBox {
    fileprivate weak var view: NSView?
}

/// 把 SwiftUI 按钮的宿主 NSView 写入锚点盒,供 NSPopover 定位。
struct QuickToolsAnchorView: NSViewRepresentable {
    let box: QuickToolsAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

/// 工具浮层呈现器:NSPopover 挂在面板窗口下,独立于面板每秒刷新
/// (macOS 26+ 自动液态玻璃外观)。transient 行为:点击浮层外自动收起。
@MainActor
final class QuickToolsPopoverPresenter: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    /// 浮层关闭回调:同步 store 的呈现状态(面板入口按钮的打开态高亮)。
    private let onClosed: @MainActor () -> Void
    /// 内容控制器:首次构建完成布局并测定 contentSize,之后重开仅更新
    /// 主题,消除弹出前的布局延迟。关闭后释放:内容结构变化(如磁贴增删)
    /// 时下次打开重新测定尺寸,避免沿用过期 contentSize。
    private var hostingController: NSHostingController<QuickToolsPopoverView>?
    /// 最近一次关闭时刻:transient 浮层点外部会自动收起,同一次点击的
    /// mouseDown 关浮层、mouseUp 到达入口按钮,需识别为「关闭」而非
    /// 重新弹出。窗口期低于人手两次独立点击的最小间隔,快速连点不被吞。
    private var lastCloseMediaTime: CFTimeInterval = 0

    init(onClosed: @escaping @MainActor () -> Void) {
        self.onClosed = onClosed
        super.init()
        popover.behavior = .transient
        // 关闭动画禁用:浮层是面板的子窗口,点行展开时 mouseDown 触发的
        // 浮层渐隐(约 0.15s)会与 mouseUp 的窗口高度补间重叠,子窗口逐帧
        // 跟随父窗口重定位,引发布局抖动(面板内容瞬移后回弹)。
        // 即时脱离让两种动画永不重叠。
        popover.animates = false
        popover.delegate = self
    }

    /// 以入口按钮的锚点盒向下弹出/收起浮层。
    func toggle(theme: MonitorPanelTheme, anchor: QuickToolsAnchorBox) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard CACurrentMediaTime() - lastCloseMediaTime > 0.15 else { return }
        guard let anchorView = anchor.view, anchorView.window != nil else { return }
        let controller = prepareHostingController(theme: theme)
        popover.contentViewController = controller
        QuickToolsStore.shared.isPopoverPresented = true
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    func dismiss() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            lastCloseMediaTime = CACurrentMediaTime()
            hostingController = nil
            onClosed()
        }
    }

    /// 预热内容控制器:未布局时 fittingSize 读数为零,浮层会以零尺寸弹出
    /// 导致「点了没反应」;布局异常时退回定宽估算尺寸兜底。
    private func prepareHostingController(theme: MonitorPanelTheme) -> NSHostingController<QuickToolsPopoverView> {
        if let existing = hostingController {
            existing.rootView = QuickToolsPopoverView(theme: theme)
            return existing
        }
        let controller = NSHostingController(rootView: QuickToolsPopoverView(theme: theme))
        controller.view.layoutSubtreeIfNeeded()
        let fitting = controller.view.fittingSize
        popover.contentSize = fitting.width > 1 && fitting.height > 1
            ? fitting
            : CGSize(width: 250, height: 220)
        hostingController = controller
        return controller
    }
}

/// 工具浮层内容:控制中心风格的点亮式磁贴,激活态整体点亮,
/// 与只读监控数据在视觉上严格区分。不设标题行——浮层由「工具」
/// 按钮弹出,内容即入口本身,标题行只占纵向空间。
struct QuickToolsPopoverView: View {
    @ObservedObject private var store = QuickToolsStore.shared
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 7) {
            ForEach(QuickToolKind.allCases, id: \.self) { kind in
                QuickToolTile(kind: kind, theme: theme)
            }
        }
        .padding(12)
        .frame(width: 250)
    }
}

/// 单个功能磁贴:圆形徽章 + 名称 + 系统标准开关。点亮时底色、
/// 描边、徽章沿同一条弹簧曲线整体过渡。
private struct QuickToolTile: View {
    @ObservedObject private var store = QuickToolsStore.shared
    let kind: QuickToolKind
    let theme: MonitorPanelTheme

    /// 点亮/熄灭共用的弹簧曲线:磁贴各元素同节奏,避免"生硬瞬切"。
    private static let toggleSpring = Animation.spring(response: 0.32, dampingFraction: 0.8)

    private var isOn: Bool {
        switch kind {
        case .keyboardLock: store.keyboardLocked
        case .systemAwake: store.systemSleepPrevented
        case .displayAwake: store.displayAwake
        }
    }

    private var accent: Color {
        theme.palette.quickToolTint
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isOn ? accent : theme.palette.trackFill)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : theme.secondaryText)
                }
                .frame(width: 32, height: 32)

                Text(String(localized: kind.titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                // 系统标准开关:macOS 26+ 自动液态玻璃,tint 染强调色保留
                // 点亮质感。关闭命中,点击统一由整块磁贴承接,避免磁贴按钮
                // 与开关各触发一次造成双重切换。
                Toggle(String(localized: kind.titleKey), isOn: .constant(isOn))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accent)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous)
                    .fill(isOn ? theme.palette.quickToolActiveFill : theme.palette.trackFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous)
                    .strokeBorder(isOn ? accent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
        }
        // 磁贴按压反馈完全交给点亮态过渡,不用 .plain 默认的按压变暗。
        .buttonStyle(QuickToolTileButtonStyle())
        .animation(Self.toggleSpring, value: isOn)
    }

    /// 状态切换统一包在同一条弹簧动画里:store 的 @Published 变化经
    /// withAnimation 传递到所有观察视图,与磁贴自身的 animation 双保险。
    private func toggle() {
        withAnimation(Self.toggleSpring) {
            switch kind {
            case .keyboardLock: store.toggleKeyboardLock()
            case .systemAwake: store.toggleSystemSleepPrevention()
            case .displayAwake: store.toggleDisplayAwake()
            }
        }
    }
}

/// 磁贴按钮样式:按压不做任何视觉变化(无变暗/无位移),
/// 状态反馈完全由点亮/熔灭的整体过渡承担。
private struct QuickToolTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 面板底部的工具入口按钮。独立子视图观察 QuickToolsStore:
/// 开关状态与浮层开闭只重绘本按钮,不牵动整块面板,避免面板闪烁。
struct QuickToolsEntryButton: View {
    @ObservedObject private var store = QuickToolsStore.shared
    let theme: MonitorPanelTheme
    @State private var anchor = QuickToolsAnchorBox()

    var body: some View {
        Button {
            store.popoverPresenter.toggle(theme: theme, anchor: anchor)
        } label: {
            Label(String(localized: "panel.tools"), systemImage: "wrench.and.screwdriver")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .compatibleButtonStyle()
        .background(QuickToolsAnchorView(box: anchor))
        .overlay(
            RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                .opacity(store.isPopoverPresented ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: store.isPopoverPresented)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(theme.palette.quickToolTint)
                .frame(width: 5, height: 5)
                .padding(.trailing, 12)
                .opacity(store.anyActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: store.anyActive)
        }
    }
}
