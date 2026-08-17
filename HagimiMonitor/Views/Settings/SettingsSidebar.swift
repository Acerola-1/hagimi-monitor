import SwiftUI

enum SettingsRoute: Hashable {
    case general
    case module(MonitorKind)
    /// 显示器模块:Direct 为控制+信息,App Store 为纯信息展示(两渠道都有入口)。
    case displayModule
    case about
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    @ObservedObject var settings: MonitorSettings
    /// 无风扇机型(如 MacBook Air)不显示风扇模块入口,避免出现无效开关。
    let fanAvailable: Bool
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updateService = UpdateService.shared
    #endif

    var body: some View {
        List(selection: $selection) {
            Section {
                Label(String(localized: "settings.sidebar.general"), systemImage: "gearshape")
                    .tag(SettingsRoute.general)
            }

            Section {
                // 蓝牙入口无条件显示:「无连接设备/蓝牙关闭」是瞬态,拿它门控
                // 常驻设置项会让用户误以为功能消失(与风扇的硬件级门控不同)。
                ForEach(MonitorKind.userVisibleCases.filter { $0 != .fan || fanAvailable }) { kind in
                    // 自绘图标(蓝牙符文)与 SF Symbols 共用同一 Label 形态;
                    // 自绘资产按固有尺寸(24pt)渲染,需收敛到 SF Symbols
                    // 跟随字体的视觉大小,否则图标明显偏大。
                    Label {
                        Text(kind.title)
                    } icon: {
                        if kind == .bluetooth {
                            kind.symbolImage
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        } else {
                            kind.symbolImage
                        }
                    }
                    .tag(SettingsRoute.module(kind))
                }

                HStack(spacing: 6) {
                    Label(String(localized: "settings.sidebar.display"), systemImage: "slider.horizontal.below.rectangle")
                    #if DISPLAY_CONTROL
                    BetaBadge()
                    #endif
                }
                .tag(SettingsRoute.displayModule)
            }

            Section {
                #if DIRECT_DISTRIBUTION
                HStack(spacing: 6) {
                    Label(String(localized: "settings.sidebar.about"), systemImage: "info.circle")
                    if updateService.availableUpdateVersion != nil {
                        UpdateAvailableBadge()
                    }
                }
                .tag(SettingsRoute.about)
                #else
                Label(String(localized: "settings.sidebar.about"), systemImage: "info.circle")
                    .tag(SettingsRoute.about)
                #endif
            }
        }
        .listStyle(.sidebar)
        .controlSize(.small)
        .font(.callout)
    }
}

#if DISPLAY_CONTROL
private struct BetaBadge: View {
    var body: some View {
        Text(String(localized: "settings.sidebar.beta-badge"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}
#endif

#if DIRECT_DISTRIBUTION
private struct UpdateAvailableBadge: View {
    var body: some View {
        Text(String(localized: "settings.sidebar.new-badge"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}
#endif
