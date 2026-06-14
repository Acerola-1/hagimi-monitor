import SwiftUI

struct MediaKeySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var permission: AccessibilityPermissionService

    var body: some View {
        SettingsGroup(String(localized: "mediaKey.section-title")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.mediaKeyBrightnessEnabled) {
                    Text(String(localized: "mediaKey.brightness-toggle"))
                }
                Toggle(isOn: $settings.mediaKeyVolumeEnabled) {
                    Text(String(localized: "mediaKey.volume-toggle"))
                }

                if settings.mediaKeyBrightnessEnabled || settings.mediaKeyVolumeEnabled {
                    Divider()
                    permissionBlock
                    Divider()
                    optionsBlock
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var permissionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: permission.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permission.isTrusted ? .green : .orange)
                Text(permission.isTrusted
                     ? String(localized: "mediaKey.status-authorized")
                     : String(localized: "mediaKey.status-not-authorized"))
                    .font(.callout.weight(.semibold))
            }

            if !permission.isTrusted {
                Text(String(localized: "mediaKey.permission-required"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "mediaKey.permission-explanation"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(String(localized: "mediaKey.open-system-settings")) {
                    permission.request()
                }
                Button(String(localized: "mediaKey.refresh-permission")) {
                    permission.refresh()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.mediaKeyShowOSD) {
                Text(String(localized: "mediaKey.show-osd"))
            }
            Toggle(isOn: $settings.mediaKeyFineScaleBrightness) {
                Text(String(localized: "mediaKey.fine-scale-brightness"))
            }
            Toggle(isOn: $settings.mediaKeyFineScaleVolume) {
                Text(String(localized: "mediaKey.fine-scale-volume"))
            }
        }
    }
}
