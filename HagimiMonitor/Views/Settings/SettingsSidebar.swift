import SwiftUI

enum SettingsRoute: Hashable {
    case general
    case module(MonitorKind)
    /// 显示器模块:Direct 为控制+信息,App Store 为纯信息展示(两渠道都有入口)。
    case displayModule
    /// 小工具:面板中的快捷功能入口与各工具磁贴的显隐。
    case quickTools
    /// 数据统计:今日概览与网页报表入口。
    case statistics
    /// 存储管理:本地数据占用可视化与选择性清理。
    case storage
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

    private var listSelection: Binding<SettingsRoute> {
        Binding(
            get: { selection == .storage ? .statistics : selection },
            set: { selection = $0 }
        )
    }

    var body: some View {
        List(selection: listSelection) {
            // 常规:单条目,标题与条目文字(「常规」)重复,不单列分组标题。
            Section {
                Label(String(localized: "settings.sidebar.general"), systemImage: "gearshape")
                    .tag(SettingsRoute.general)
            }

            // 监控:各硬件模块与显示器。
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

                Label(String(localized: "settings.sidebar.display"), systemImage: "slider.horizontal.below.rectangle")
                    .tag(SettingsRoute.displayModule)
            } header: {
                Text(String(localized: "settings.sidebar.modules"))
            }

            // 扩展:小工具与数据统计(数据存储管理作为数据统计的子页,不占侧栏条目)。
            Section {
                Label(String(localized: "settings.sidebar.quick-tools"), systemImage: "wrench.and.screwdriver")
                    .tag(SettingsRoute.quickTools)

                Label(String(localized: "settings.sidebar.statistics"), systemImage: "chart.bar.doc.horizontal")
                    .tag(SettingsRoute.statistics)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = .statistics
                    }
            } header: {
                Text(String(localized: "settings.sidebar.extensions"))
            }

            // 关于:单条目,标题与条目文字(「关于」)重复,不单列分组标题。
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
