import SwiftUI

struct MediaKeySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var permission: AccessibilityPermissionService

    private var anyTakeoverEnabled: Bool {
        settings.mediaKeyBrightnessEnabled || settings.mediaKeyVolumeEnabled
    }

    var body: some View {
        SettingsGroup(String(localized: "mediaKey.section-title")) {
            SettingsRow(title: String(localized: "mediaKey.brightness-toggle")) {
                Toggle("", isOn: $settings.mediaKeyBrightnessEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(title: String(localized: "mediaKey.volume-toggle")) {
                Toggle("", isOn: $settings.mediaKeyVolumeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if anyTakeoverEnabled {
                SettingsDivider()

                SettingsRow(title: String(localized: "mediaKey.show-osd")) {
                    Toggle("", isOn: $settings.mediaKeyShowOSD)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
        // 未授权时整组置灰不可操作:接管开关开了也不生效,先灰掉避免「开了没反应」
        // 的困惑;授权入口由下方常驻提示卡提供。
        .disabled(!permission.isTrusted)

        // 提示卡改为未授权即常驻(不再依赖开关状态)——开关已灰掉,这里是唯一授权入口。
        if !permission.isTrusted {
            permissionHint
        }
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(String(localized: "mediaKey.permission-title"))
                    .font(.callout.weight(.medium))
            }

            Text(String(localized: "mediaKey.permission-explanation"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(String(localized: "mediaKey.open-system-settings")) {
                    permission.request()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(String(localized: "mediaKey.refresh-permission")) {
                    permission.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
