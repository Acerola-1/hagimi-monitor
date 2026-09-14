import AppKit
import SwiftUI

/// 原生统计报表主窗口视图。
struct NativeReportView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    let onReload: () -> Void
    let onPrint: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息与全局操作条
            ReportTopBarView(
                viewModel: viewModel,
                onReload: onReload,
                onPrint: onPrint,
                onExport: onExport
            )

            // 下方主工作区：左侧模块导航 + 右侧内容容器
            HStack(spacing: 0) {
                ReportSidebarView(selectedModule: $viewModel.selectedModule)

                ZStack {
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text(String(localized: "stats.r.loading", defaultValue: "正在载入硬件规格与统计快照…"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if viewModel.selectedModule == .details {
                            ReportDetailsTableView(viewModel: viewModel)
                                .padding(18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 16) {
                                    moduleContentView
                                }
                                .padding(18)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1100, minHeight: 640)
        .background(VisualEffectBlurView(material: .popover, blendingMode: .behindWindow))
    }

    @ViewBuilder
    private var moduleContentView: some View {
        switch viewModel.selectedModule {
        case .overview:
            ReportOverviewView(viewModel: viewModel)
        case .cpu:
            ReportCpuView(viewModel: viewModel)
        case .gpu:
            ReportGpuView(viewModel: viewModel)
        case .memory:
            ReportMemoryView(viewModel: viewModel)
        case .network:
            ReportNetworkView(viewModel: viewModel)
        case .disk:
            ReportDiskView(viewModel: viewModel)
        case .power:
            ReportPowerView(viewModel: viewModel)
        case .thermal:
            ReportThermalView(viewModel: viewModel)
        case .apps:
            ReportAppsView(viewModel: viewModel)
        case .events:
            ReportEventsView(viewModel: viewModel)
        case .details:
            ReportDetailsTableView(viewModel: viewModel)
        case .insights:
            ReportInsightsView(viewModel: viewModel)
        case .machine:
            ReportMachineView(viewModel: viewModel)
        }
    }
}

/// AppKit 原生毛玻璃背景视图适配器
struct VisualEffectBlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
