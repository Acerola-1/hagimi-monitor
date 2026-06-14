import SwiftUI

/// 媒体键接管设置区,单一 group 容器:
/// ① 两个主开关(亮度/音量接管)—— 始终显示
/// ② 权限提示条 —— 仅开启接管且未授权时出现(独立于 group 的扁平块)
/// ③ 开关下属选项(OSD/精细步进)—— 勾选任一接管后,在同一 group 内
///    用 SettingsDivider 接着展开,不另起独立板块
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

            // 接管亮度键后,正下方展开亮度专属的精细步进,位置紧邻体现从属
            if settings.mediaKeyBrightnessEnabled {
                SettingsDivider()

                SettingsRow(
                    title: String(localized: "mediaKey.fine-scale-brightness"),
                    subtitle: String(localized: "mediaKey.fine-scale-hint")
                ) {
                    Toggle("", isOn: $settings.mediaKeyFineScaleBrightness)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsDivider()

            SettingsRow(title: String(localized: "mediaKey.volume-toggle")) {
                Toggle("", isOn: $settings.mediaKeyVolumeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // 接管音量键后,正下方展开音量专属的精细步进
            if settings.mediaKeyVolumeEnabled {
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

            // OSD 是亮度+音量共用的全局选项,任一接管开启时出现在板块末尾
            if anyTakeoverEnabled {
                SettingsDivider()

                SettingsRow(title: String(localized: "mediaKey.show-osd")) {
                    Toggle("", isOn: $settings.mediaKeyShowOSD)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }

        // 权限提示:只在需要引导时出现,扁平样式不占用 group 容器
        if anyTakeoverEnabled, !permission.isTrusted {
            permissionHint
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
