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

/// Gamma 传输表应用结果(8.1)。成功/失败必须可观测,失败不保存为已成功应用。
nonisolated enum GammaApplyResult: Equatable, Sendable {
    case success
    case failure(CGError)
}

/// Gamma API 注入边界:生产实现调用 CGSetDisplayTransferByFormula,
/// 测试注入 fake 验证"成功才更新 applied、失败不伪造"。
nonisolated protocol GammaAPI: AnyObject {
    /// 获取当前传输表(基线)。失败返回 nil。
    func transferTables(for displayID: CGDirectDisplayID) -> GammaTransferTables?
    /// 应用线性压暗传输表(factor 0..1)。
    func applyDimming(factor: CGGammaValue, displayID: CGDirectDisplayID) -> GammaApplyResult
    /// 恢复原始传输表(基线或系统默认)。
    func restore(displayID: CGDirectDisplayID) -> GammaApplyResult

    /// 基于首次启用前保存的基线生成调光表;未提供基线时使用基础 API。
    func applyDimming(
        factor: CGGammaValue,
        baseline: GammaTransferTables?,
        displayID: CGDirectDisplayID
    ) -> GammaApplyResult

    /// 恢复指定基线。没有基线时回退到系统默认表。
    func restore(
        baseline: GammaTransferTables?,
        displayID: CGDirectDisplayID
    ) -> GammaApplyResult
}

extension GammaAPI {
    func applyDimming(
        factor: CGGammaValue,
        baseline: GammaTransferTables?,
        displayID: CGDirectDisplayID
    ) -> GammaApplyResult {
        applyDimming(factor: factor, displayID: displayID)
    }

    func restore(
        baseline: GammaTransferTables?,
        displayID: CGDirectDisplayID
    ) -> GammaApplyResult {
        restore(displayID: displayID)
    }
}

/// 一次完整的 Gamma 传输表(红/绿/蓝 通道)。
nonisolated struct GammaTransferTables: Equatable, Sendable {
    let redMin: CGGammaValue
    let redMax: CGGammaValue
    let redGamma: CGGammaValue
    let greenMin: CGGammaValue
    let greenMax: CGGammaValue
    let greenGamma: CGGammaValue
    let blueMin: CGGammaValue
    let blueMax: CGGammaValue
    let blueGamma: CGGammaValue

}

/// 生产 Gamma API:CGSetDisplayTransferByFormula 包装。
nonisolated final class SystemGammaAPI: GammaAPI {
    func transferTables(for displayID: CGDirectDisplayID) -> GammaTransferTables? {
        var rMin = CGGammaValue(0), rMax = CGGammaValue(0), rGamma = CGGammaValue(0)
        var gMin = CGGammaValue(0), gMax = CGGammaValue(0), gGamma = CGGammaValue(0)
        var bMin = CGGammaValue(0), bMax = CGGammaValue(0), bGamma = CGGammaValue(0)
        let result = CGGetDisplayTransferByFormula(
            displayID,
            &rMin, &rMax, &rGamma,
            &gMin, &gMax, &gGamma,
            &bMin, &bMax, &bGamma
        )
        guard result == .success else { return nil }
        return GammaTransferTables(
            redMin: rMin, redMax: rMax, redGamma: rGamma,
            greenMin: gMin, greenMax: gMax, greenGamma: gGamma,
            blueMin: bMin, blueMax: bMax, blueGamma: bGamma
        )
    }

    func applyDimming(factor: CGGammaValue, displayID: CGDirectDisplayID) -> GammaApplyResult {
        applyDimming(factor: factor, baseline: nil, displayID: displayID)
    }

    func applyDimming(
        factor: CGGammaValue,
        baseline: GammaTransferTables?,
        displayID: CGDirectDisplayID
    ) -> GammaApplyResult {
        let redMax = baseline.map { $0.redMin + ($0.redMax - $0.redMin) * factor } ?? factor
        let greenMax = baseline.map { $0.greenMin + ($0.greenMax - $0.greenMin) * factor } ?? factor
        let blueMax = baseline.map { $0.blueMin + ($0.blueMax - $0.blueMin) * factor } ?? factor
        let result = CGSetDisplayTransferByFormula(
            displayID,
            baseline?.redMin ?? 0.0, redMax, baseline?.redGamma ?? 1.0,
            baseline?.greenMin ?? 0.0, greenMax, baseline?.greenGamma ?? 1.0,
            baseline?.blueMin ?? 0.0, blueMax, baseline?.blueGamma ?? 1.0
        )
        return result == .success ? .success : .failure(result)
    }

    func restore(displayID: CGDirectDisplayID) -> GammaApplyResult {
        restore(baseline: nil, displayID: displayID)
    }

    func restore(baseline: GammaTransferTables?, displayID: CGDirectDisplayID) -> GammaApplyResult {
        let result = CGSetDisplayTransferByFormula(
            displayID,
            baseline?.redMin ?? 0.0, baseline?.redMax ?? 1.0, baseline?.redGamma ?? 1.0,
            baseline?.greenMin ?? 0.0, baseline?.greenMax ?? 1.0, baseline?.greenGamma ?? 1.0,
            baseline?.blueMin ?? 0.0, baseline?.blueMax ?? 1.0, baseline?.blueGamma ?? 1.0
        )
        return result == .success ? .success : .failure(result)
    }
}

/// Gamma 表软件调光控制器(降级层 T3)。
///
/// 当 DDC 不可用(无 IOAVService、显示器明确不支持 DDC/CI、或连接方式不转发 DDC
/// 如 DisplayLink/AirPlay)时,通过修改显示器 Gamma 传输表来实现软件调光。
///
/// `setDimming` 返回结构化结果,只有成功才更新应用状态与成功值;
/// 首次启用软件调光前读取当前传输表作为本应用基线,100% 恢复基线;
/// 基线缓存与连接代次关联,应用自身的调光表不会再次作为基线累乘;
/// 刷新读数不重复施加 Gamma,仅用户写入或系统重置后的唤醒事件重施加。
///
/// 已知限制:
/// - 不改变显示器背光,不省电;
/// - 会损失暗部细节(低位深度截断);
/// - 与 Night Shift/f.lux 等 gamma 修改工具冲突(覆盖而非叠加);
/// - 睡眠/唤醒后系统会重置 gamma 表,需在唤醒后重新施加。
nonisolated final class GammaDimmingController {
    static let shared = GammaDimmingController()

    private let gammaAPI: GammaAPI
    private var dimLevels: [CGDirectDisplayID: Double] = [:]
    /// 每台显示器的基线传输表(首次启用前读取),绑定连接代次。
    private var baselines: [CGDirectDisplayID: GammaTransferTables] = [:]
    private let lock = NSLock()

    init(gammaAPI: GammaAPI = SystemGammaAPI()) {
        self.gammaAPI = gammaAPI
        _ = DDCEnvironmentGate.shared.addChangeHandler { [weak self] in
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
            self?.reapplyAll(onlineIDs: Set(ids.prefix(Int(count))))
        }
    }

    /// 设置指定显示器的软件调光级别。
    /// - Returns: 结构化结果;失败不更新 applied 状态与成功值。
    @discardableResult
    func setDimming(percent: Double, for displayID: CGDirectDisplayID) -> GammaApplyResult {
        let clamped = min(100, max(0, percent))
        let factor = CGGammaValue(clamped / 100.0)

        lock.lock()
        // 首次启用前读取基线;已有基线保持不变,后续应用都从同一基线计算。
        if baselines[displayID] == nil, let table = gammaAPI.transferTables(for: displayID) {
            baselines[displayID] = table
        }
        let baseline = baselines[displayID]
        lock.unlock()

        let result: GammaApplyResult
        if clamped >= 99.999, let baseline {
            result = gammaAPI.restore(baseline: baseline, displayID: displayID)
        } else {
            result = gammaAPI.applyDimming(factor: factor, baseline: baseline, displayID: displayID)
        }
        lock.lock()
        if result == .success {
            dimLevels[displayID] = clamped
        }
        lock.unlock()
        if result == .success {
            gammaLog.debug("Applied gamma dimming \(clamped, privacy: .public)% to display \(displayID, privacy: .public)")
        } else if case .failure(let error) = result {
            gammaLog.error("Failed to apply gamma dimming to display \(displayID, privacy: .public): \(error.rawValue, privacy: .public)")
        }
        return result
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

    /// 重置指定显示器的 gamma 表到基线(或系统默认)。
    /// 仅当该显示器存在调光残留时才恢复,避免对从未调光过的显示器做无谓调用。
    @discardableResult
    func reset(displayID: CGDirectDisplayID) -> GammaApplyResult {
        lock.lock()
        let hadState = dimLevels[displayID] != nil
        let baseline = baselines[displayID]
        lock.unlock()

        guard hadState else { return .success }
        let result = gammaAPI.restore(baseline: baseline, displayID: displayID)
        if result == .success {
            lock.lock()
            dimLevels.removeValue(forKey: displayID)
            baselines.removeValue(forKey: displayID)
            lock.unlock()
        }
        return result
    }

    /// 清除不在 `onlineIDs` 中的显示器的调光残留并恢复 gamma。
    func resetDisconnected(onlineIDs: Set<CGDirectDisplayID>) {
        lock.lock()
        let staleIDs = Array(dimLevels.keys.filter { !onlineIDs.contains($0) })
        lock.unlock()

        for displayID in staleIDs {
            reset(displayID: displayID)
        }
    }

    /// 重新施加所有活跃的 gamma 调光(唤醒/系统重置后)。
    /// 仅对仍有效的连接施加;基线缺失时不盲目施加(避免用错误基线累乘)。
    func reapplyAll(onlineIDs: Set<CGDirectDisplayID>) {
        lock.lock()
        let snapshot = dimLevels.filter { onlineIDs.contains($0.key) }
        lock.unlock()

        guard !snapshot.isEmpty else { return }
        gammaLog.info("Reapplying gamma dimming for \(snapshot.count, privacy: .public) display(s) after system event")
        for (displayID, percent) in snapshot {
            setDimming(percent: percent, for: displayID)
        }
    }

    /// 清除所有 gamma 调光状态并恢复系统默认 gamma。
    @discardableResult
    func resetAll() -> GammaApplyResult {
        lock.lock()
        let ids = Array(dimLevels.keys)
        lock.unlock()

        var last: GammaApplyResult = .success
        for displayID in ids {
            last = reset(displayID: displayID)
        }
        return last
    }
}
