import SwiftUI

/// 媒体键接管设置区。
///
/// 拆成三个视觉单元,每个都小而克制,与同页 SettingsGroup 的呼吸节奏一致:
/// ① 主开关 group(亮度/音量接管)—— 始终显示
/// ② 权限提示条 —— 仅在开启接管且未授权时出现,扁平 inline 样式
/// ③ 细化选项 group(OSD/精细步进)—— 仅在开启接管时出现
struct MediaKeySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var permission: AccessibilityPermissionService

    private var anyTakeoverEnabled: Bool {
        settings.mediaKeyBrightnessEnabled || settings.mediaKeyVolumeEnabled
    }

    var body: some View {
        // ① 主开关:与上方 controls group 对等的精简单元
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
        }

        // ② 权限提示:只在需要引导时出现,扁平样式不占用 group 容器
        if anyTakeoverEnabled, !permission.isTrusted {
            permissionHint
        }

        // ③ 细化选项:只在已开启接管时出现
        if anyTakeoverEnabled {
            SettingsGroup(String(localized: "mediaKey.options-title")) {
                SettingsRow(title: String(localized: "mediaKey.show-osd")) {
                    Toggle("", isOn: $settings.mediaKeyShowOSD)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(
                    title: String(localized: "mediaKey.fine-scale-brightness"),
                    subtitle: String(localized: "mediaKey.fine-scale-hint")
                ) {
                    Toggle("", isOn: $settings.mediaKeyFineScaleBrightness)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(
                    title: String(localized: "mediaKey.fine-scale-volume"),
                    subtitle: String(localized: "mediaKey.fine-scale-hint")
                ) {
                    Toggle("", isOn: $settings.mediaKeyFineScaleVolume)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    /// 权限提示条:扁平 inline 样式(不套 group 圆角容器),说明文案 + 行内按钮。
    /// 配色克制(.secondary + 橙色点缀),与 SettingsTip 气质一致。
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
