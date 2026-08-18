#if !DIRECT_DISTRIBUTION
import AppKit
import SwiftUI

/// App Store 渠道的键盘锁定引擎:全屏遮罩窗口。
/// 沙盒内拿不到拦截型事件 tap 所需的辅助功能权限,唯一路径是让
/// 一块全屏无边框窗口成为 key window——键盘事件全部进入其
/// responder chain,内容不含文本控件即全部丢弃。鼠标同时被遮罩
/// 接管:若放行点击,点击其他窗口会转移 key window,锁定即失效。
/// 解锁逃生口:遮罩上的解锁按钮、⌃⌥⌘L(键盘事件本就到达遮罩,
/// SwiftUI keyboardShortcut 在 responder chain 内生效)、自动解锁。
@MainActor
final class KeyboardLockShieldController {
    /// 自动解锁兜底,与 Direct 渠道事件 tap 方案同一时长。
    static let autoUnlockInterval: TimeInterval = 20 * 60

    /// 自动解锁触发,owner 负责同步 UI 状态。
    var onAutoUnlock: (() -> Void)?
    /// 解锁按钮/快捷键触发,走 owner 的 toggle 语义。
    var onUnlock: (() -> Void)?

    private var windows: [NSWindow] = []
    private var autoUnlockTimer: DispatchSourceTimer?
    private var screenObserver: NSObjectProtocol?

    var isShown: Bool { !windows.isEmpty }

    /// 铺满所有屏幕并开始锁定。重复调用幂等。
    /// - Returns: 遮罩窗口是否成功建立(即锁定生效)。
    func present() -> Bool {
        guard windows.isEmpty else { return true }
        rebuildWindows()
        guard !windows.isEmpty else { return false }
        // 菜单栏应用无 Dock 激活路径,显式激活保证遮罩稳定持有
        // key window(键盘事件路由的前提)。
        NSApp.activate(ignoringOtherApps: true)
        startAutoUnlockTimer()
        observeScreenChanges()
        return true
    }

    /// 解除锁定:关全部遮罩窗口、停计时与屏幕监听。
    func dismiss() {
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        windows.forEach { $0.close() }
        windows = []
    }

    // MARK: - 遮罩窗口

    /// 每块屏幕一个遮罩窗口:任何一块屏裸露都会让点击转移 key window、
    /// 键盘从那块屏漏走。主屏窗口成为 key,副屏窗口同样可成为 key。
    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = []
        let preference = MonitorSettings(defaults: .standard).colorSchemePreference
        for screen in NSScreen.screens {
            let window = KeyboardLockShieldWindow(contentRect: screen.frame)
            // 每窗口独立宿主视图:同一 SwiftUI 根视图跨多个宿主
            // 会导致状态共享异常。
            window.contentView = NSHostingView(
                rootView: KeyboardLockShieldView(preference: preference) { [weak self] in
                    self?.onUnlock?()
                }
            )
            windows.append(window)
            if screen == NSScreen.main {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }

    /// 锁定期插拔显示器:重建遮罩,新接入的屏幕不裸露。
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown else { return }
                self.rebuildWindows()
            }
        }
    }

    private func startAutoUnlockTimer() {
        autoUnlockTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.autoUnlockInterval)
        timer.setEventHandler { [weak self] in
            self?.dismiss()
            self?.onAutoUnlock?()
        }
        autoUnlockTimer = timer
        timer.resume()
    }
}

/// 全屏遮罩窗口:无边框、盖过菜单栏的置顶层、可成为 key(接管键盘)。
private final class KeyboardLockShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    /// 功能键(亮度/音量/控制中心等)不走普通 keyDown,而是以系统定义
    /// 事件到达 key window,未被应用处理时系统才执行默认响应(弹 HUD、
    /// 调亮度)。吞掉这类事件即可连带抑制系统默认行为,无需任何权限。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .systemDefined { return }
        super.sendEvent(event)
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}

/// 遮罩内容:全屏压暗 + 中央解锁卡片。卡片文案与强调色走
/// MonitorPalette 令牌;全屏压暗层属特殊表面,用固定黑透明度。
private struct KeyboardLockShieldView: View {
    @Environment(\.colorScheme) private var colorScheme
    let preference: MonitorColorSchemePreference
    let onUnlock: () -> Void

    private var theme: MonitorPanelTheme {
        ThemeCache.theme(preference: preference, scheme: colorScheme)
    }

    private var accent: Color {
        theme.palette.quickToolAccent(.keyboardLock)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 56, height: 56)
                    Image(systemName: "keyboard")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                Text(String(localized: "quicktools.keyboard-lock.shield-title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Text(String(localized: "quicktools.keyboard-lock.shield-subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                Button(action: onUnlock) {
                    Label(String(localized: "quicktools.keyboard-lock.unlock"), systemImage: "lock.open")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 190)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut("l", modifiers: [.command, .option, .control])
                .padding(.top, 4)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
