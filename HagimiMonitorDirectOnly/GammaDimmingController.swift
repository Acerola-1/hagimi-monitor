import AppKit
import CoreGraphics
import Foundation
import OSLog

private let gammaLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "GammaDimming")

/// 调光模式:标识某台显示器当前使用哪种方式控制亮度。
/// - hardware: DDC/CI 或 DisplayServices 原生协议(真硬件背光,无损画质)
/// - gamma: Gamma 传输表软件调光(压低像素值,不省电,损失暗部细节)
enum DimmingMode {
    case hardware
    case gamma
}

/// Gamma 表软件调光控制器(降级层 T3)。
///
/// 当 DDC 不可用(无 IOAVService、显示器明确不支持 DDC/CI、或连接方式不转发 DDC
/// 如 DisplayLink/AirPlay)时,通过修改显示器 Gamma 传输表来实现软件调光。
///
/// 原理:CGSetDisplayTransferByFormula 设置 out = (in^gamma) * (max-min) + min。
/// 调光时 gamma=1(线性),min=0,max=factor(亮度百分比/100),即 out = in * factor。
/// 100% = identity(不调光),0% = 全黑。
///
/// 已知限制:
/// - 不改变显示器背光,不省电;
/// - 会损失暗部细节(低位深度截断);
/// - 与 Night Shift/f.lux 等 gamma 修改工具冲突(覆盖而非叠加);
/// - 睡眠/唤醒后系统会重置 gamma 表,需在唤醒后重新施加(由 refresh 流程触发)。
nonisolated final class GammaDimmingController {
    static let shared = GammaDimmingController()

    /// 每台显示器当前的 gamma 调光百分比(0-100,100 = 不调光)。
    private var dimLevels: [CGDirectDisplayID: Double] = [:]
    private let lock = NSLock()

    private init() {}

    /// 设置指定显示器的软件调光级别。
    /// - Parameter percent: 亮度百分比(0-100)。100 = 不调光(恢复原始 gamma)。
    func setDimming(percent: Double, for displayID: CGDirectDisplayID) {
        let clamped = min(100, max(0, percent))

        lock.lock()
        dimLevels[displayID] = clamped
        lock.unlock()

        applyGamma(displayID: displayID, percent: clamped)
    }

    /// 获取指定显示器当前的软件调光百分比。
    func dimmingPercent(for displayID: CGDirectDisplayID) -> Double {
        lock.lock(); defer { lock.unlock() }
        return dimLevels[displayID] ?? 100
    }

    /// 该显示器是否正在使用 gamma 调光(调光百分比 < 100)。
    func isDimming(displayID: CGDirectDisplayID) -> Bool {
        dimmingPercent(for: displayID) < 100
    }

    /// 重置指定显示器的 gamma 表到系统默认。
    /// 仅当该显示器存在调光残留时才恢复 gamma,避免对从未调光过的显示器做无谓调用。
    func reset(displayID: CGDirectDisplayID) {
        lock.lock()
        let hadState = dimLevels.removeValue(forKey: displayID) != nil
        lock.unlock()

        guard hadState else { return }
        // 对单台显示器恢复 identity gamma。
        applyGamma(displayID: displayID, percent: 100)
    }

    /// 清除不在 `onlineIDs` 中的显示器的调光残留并恢复 gamma。
    /// 在每次显示器检测后、`reapplyAll` 前调用:先丢弃已断开显示器的残留状态,
    /// 避免 `reapplyAll` 对离线显示器做无谓的 gamma 施加(必然失败且产生日志噪音)。
    func resetDisconnected(onlineIDs: Set<CGDirectDisplayID>) {
        lock.lock()
        let staleIDs = Array(dimLevels.keys.filter { !onlineIDs.contains($0) })
        for id in staleIDs {
            dimLevels.removeValue(forKey: id)
        }
        lock.unlock()

        for displayID in staleIDs {
            applyGamma(displayID: displayID, percent: 100)
        }
    }

    /// 重新施加所有活跃的 gamma 调光。
    /// 用于睡眠/唤醒/显示器重配置后恢复——系统在这些事件后会重置 gamma 表。
    func reapplyAll() {
        lock.lock()
        let snapshot = dimLevels
        lock.unlock()

        guard !snapshot.isEmpty else { return }

        gammaLog.info("Reapplying gamma dimming for \(snapshot.count, privacy: .public) display(s) after system event")
        for (displayID, percent) in snapshot {
            applyGamma(displayID: displayID, percent: percent)
        }
    }

    /// 清除所有 gamma 调光状态并恢复系统默认 gamma。
    func resetAll() {
        lock.lock()
        let ids = Array(dimLevels.keys)
        dimLevels.removeAll()
        lock.unlock()

        for displayID in ids {
            applyGamma(displayID: displayID, percent: 100)
        }
    }

    /// 应用 gamma 传输表公式到指定显示器。
    /// 公式: out = (in^gamma) * (max-min) + min
    /// 调光: gamma=1, min=0, max=factor → out = in * factor(线性压暗)
    private func applyGamma(displayID: CGDirectDisplayID, percent: Double) {
        let factor = CGGammaValue(percent / 100.0)

        let result = CGSetDisplayTransferByFormula(
            displayID,
            1.0, 0.0, factor,
            1.0, 0.0, factor,
            1.0, 0.0, factor
        )

        if result == .success {
            gammaLog.debug("Applied gamma dimming \(percent, privacy: .public)% to display \(displayID, privacy: .public)")
        } else {
            gammaLog.error("Failed to apply gamma dimming to display \(displayID, privacy: .public): error \(result.rawValue, privacy: .public)")
        }
    }
}
