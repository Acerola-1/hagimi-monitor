import AppKit
import SwiftUI

@MainActor
final class AccessibilityPermissionGuide {
    static let shared = AccessibilityPermissionGuide()

    /// 浮窗归属的权限域:辅助功能与输入监控共用这一个浮窗,两项权限的
    /// 授权服务在各自 refresh() 里都会"已授权即关引导"——不按域匹配的话,
    /// A 项授权后的感知回调会把链式引导刚弹出的 B 项浮窗误杀。
    enum Domain {
        case accessibility
        case inputMonitoring
    }

    private var panel: NSPanel?
    private var domain: Domain?

    private let panelSize = CGSize(width: 320, height: 166)

    func present(
        domain: Domain = .accessibility,
        titleKey: String.LocalizationValue = "mediaKey.permission.guide-title",
        subtitleKey: String.LocalizationValue = "mediaKey.permission.guide-subtitle"
    ) {
        if let panel {
            if self.domain == domain {
                panel.orderFrontRegardless()
                return
            }
            // 链式引导衔接到下一项权限:旧浮窗内容已过时,重建。
            panel.orderOut(nil)
            self.panel = nil
        }
        self.domain = domain

        let guide = AccessibilityPermissionGuideView(
            appURL: Bundle.main.bundleURL,
            titleKey: titleKey,
            subtitleKey: subtitleKey,
            onClose: { [weak self] in self?.dismiss() }
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: guide)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameOrigin(Self.origin(for: panelSize))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 关闭指定域的浮窗:当前浮窗已归属另一项权限(链式引导已衔接)则不动。
    func dismiss(domain: Domain) {
        guard self.domain == domain else { return }
        panel?.orderOut(nil)
        panel = nil
        self.domain = nil
    }

    /// 无条件关闭(撤销上锁意图等用户操作场景)。
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        domain = nil
    }

    private static func origin(for size: CGSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.midY - size.height / 2
        )
    }
}

private struct AccessibilityPermissionGuideView: View {
    let appURL: URL
    var titleKey: String.LocalizationValue = "mediaKey.permission.guide-title"
    var subtitleKey: String.LocalizationValue = "mediaKey.permission.guide-subtitle"
    let onClose: () -> Void

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "HagimiMonitor"
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: titleKey))
                        .font(.headline)
                    Text(String(localized: subtitleKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "mediaKey.permission.close-guide"))
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.quaternary.opacity(0.5))

                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 62, height: 62)
                }
                .frame(width: 76, height: 76)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(.tint.opacity(0.7), lineWidth: 2)
                }
                .shadow(color: Color.accentColor.opacity(0.2), radius: 5, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .onDrag {
                    NSItemProvider(object: appURL as NSURL)
                } preview: {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 62, height: 62)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "mediaKey.permission.drag-app"))
                        .font(.callout.weight(.medium))
                }
            }
        }
        .padding(14)
        .frame(width: 320, height: 166, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .help(appName)
    }
}
