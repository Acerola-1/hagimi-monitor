import AppKit
import SwiftUI

@MainActor
final class AccessibilityPermissionGuide {
    static let shared = AccessibilityPermissionGuide()

    private var panel: NSPanel?
    private let panelSize = CGSize(width: 320, height: 166)

    func present() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let guide = AccessibilityPermissionGuideView(
            appURL: Bundle.main.bundleURL,
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

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
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
                    Text(String(localized: "mediaKey.permission.guide-title"))
                        .font(.headline)
                    Text(String(localized: "mediaKey.permission.guide-subtitle"))
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
