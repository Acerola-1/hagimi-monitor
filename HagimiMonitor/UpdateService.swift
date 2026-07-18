#if DIRECT_DISTRIBUTION
import Combine
import Foundation
import Sparkle

/// Sparkle 自更新的封装(仅直接分发 / GitHub 版编译)。
///
/// 用 `SPUStandardUpdaterController` 驱动标准更新流程:检查 → 展示更新日志弹窗 →
/// 下载(EdDSA 签名校验)→ 替换 .app → 重启完成。整套 UI 由 Sparkle 原生提供,
/// 我们只需暴露「检查更新」入口与「能否检查」状态给关于页使用。
///
/// App Store 版不编译本文件(更新交由商店管理),故不引入 Sparkle 符号。
@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    /// 是否可发起检查(下载/安装进行中时 Sparkle 会置为 false),用于禁用按钮避免重复触发。
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    override init() {
        // startingUpdater: true → 随 App 启动即开始后台定时检查(遵循 Sparkle 默认周期)。
        // 不传 delegate,使用 Sparkle 标准行为;feed URL 与公钥由 Info.plist 提供。
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        // 绑定 Sparkle 的 canCheckForUpdates 到本地发布属性,供 SwiftUI 响应式禁用按钮。
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 手动触发检查更新。若有新版本,Sparkle 会弹出带更新日志的窗口引导用户下载安装;
    /// 若已是最新,Sparkle 会提示「已是最新版本」。
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
