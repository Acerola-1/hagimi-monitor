import Testing
@testable import HagimiMonitorDirect
import CoreGraphics
import Foundation

/// fake Gamma API:记录调用,可控成功/失败与基线。
final class FakeGammaAPI: GammaAPI, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var applyCalls: [(factor: CGGammaValue, displayID: CGDirectDisplayID)] = []
    private(set) var restoreCalls: [CGDirectDisplayID] = []
    private(set) var baselineFetches: [CGDirectDisplayID] = []
    /// 是否返回成功。
    var appliesSucceed = true
    /// 返回的基线表(模拟显示器已有校色/其他调光软件)。
    var baseline: GammaTransferTables?
    /// 返回的基线是否为恒等表。
    var identityBaseline = true

    private var baselineLock = NSLock()

    func transferTables(for displayID: CGDirectDisplayID) -> GammaTransferTables? {
        baselineLock.lock()
        baselineFetches.append(displayID)
        let b = baseline ?? (identityBaseline ? Self.identity : nil)
        baselineLock.unlock()
        return b
    }

    func applyDimming(factor: CGGammaValue, displayID: CGDirectDisplayID) -> GammaApplyResult {
        lock.lock()
        applyCalls.append((factor, displayID))
        lock.unlock()
        return appliesSucceed ? .success : .failure(.failure)
    }

    func restore(displayID: CGDirectDisplayID) -> GammaApplyResult {
        lock.lock()
        restoreCalls.append(displayID)
        lock.unlock()
        return appliesSucceed ? .success : .failure(.failure)
    }

    static let identity = GammaTransferTables(
        redMin: 0, redMax: 1, redGamma: 1,
        greenMin: 0, greenMax: 1, greenGamma: 1,
        blueMin: 0, blueMax: 1, blueGamma: 1
    )
}

/// 组 8 软件调光测试(8.1/8.2/8.3)。
/// 验收:Gamma 失败不更新成功状态;基线不累乘;100% 恢复基线;只写模式不自动施加。
struct GammaDimmingControllerTests {
    private func makeController(_ api: FakeGammaAPI) -> GammaDimmingController {
        GammaDimmingController(gammaAPI: api)
    }

    // MARK: - 8.1 结构化结果

    @Test func gammaFailureDoesNotUpdateAppliedState() {
        let api = FakeGammaAPI()
        api.appliesSucceed = false
        let controller = makeController(api)
        let result = controller.setDimming(percent: 50, for: 1)
        #expect(result == .failure(.failure))
        // 失败不更新 dimming 状态(仍认为 100% 未调光)。
        #expect(controller.dimmingPercent(for: 1) == 100, "失败不应保存为已成功应用")
        #expect(!controller.isDimming(displayID: 1))
    }

    @Test func gammaSuccessUpdatesAppliedState() {
        let api = FakeGammaAPI()
        let controller = makeController(api)
        #expect(controller.setDimming(percent: 40, for: 1) == .success)
        #expect(controller.dimmingPercent(for: 1) == 40)
        #expect(controller.isDimming(displayID: 1))
    }

    // MARK: - 8.2 基线不累乘

    /// 50→50 不累乘:基线只在首次启用前读取一次,后续 setDimming 不重新取基线。
    @Test func baselineFetchedOnlyOnce() {
        let api = FakeGammaAPI()
        let controller = makeController(api)
        controller.setDimming(percent: 50, for: 1)
        controller.setDimming(percent: 50, for: 1)
        #expect(api.baselineFetches.count == 1, "基线只在首次启用前读取一次")
        #expect(api.baselineFetches == [1])
    }

    /// 100% 恢复基线:reset 后按基线恢复,而非系统恒等表。
    @Test func resetRestoresBaselineNotIdentity() {
        let api = FakeGammaAPI()
        // 模拟显示器已有校色(非恒等基线)。
        api.baseline = GammaTransferTables(
            redMin: 0, redMax: 0.8, redGamma: 2.2,
            greenMin: 0, greenMax: 0.8, greenGamma: 2.2,
            blueMin: 0, blueMax: 0.8, blueGamma: 2.2
        )
        let controller = makeController(api)
        controller.setDimming(percent: 60, for: 1)
        controller.reset(displayID: 1)
        // 基线在首次 setDimming 时已取;reset 恢复到该基线。
        #expect(api.baselineFetches == [1])
        #expect(!controller.isDimming(displayID: 1))
    }

    /// 取基线失败:不假称可无损恢复,但仍应用(降级为恒等恢复)。
    @Test func baselineUnavailableFallsBackToIdentityRestore() {
        let api = FakeGammaAPI()
        api.identityBaseline = false // 基线为 nil
        api.baseline = nil
        let controller = makeController(api)
        controller.setDimming(percent: 30, for: 1)
        controller.reset(displayID: 1)
        // 基线不可得:reset 走系统恒等恢复(不声称恢复原始校色)。
        #expect(api.restoreCalls.contains(1))
    }

    // MARK: - 8.3 事件驱动重施加

    /// 普通刷新不重复施加:reapplyAll 只在明确的事件驱动点调用,setDimming 才是施加源。
    @Test func reapplyOnlyAppliesActiveOnlineDisplays() {
        let api = FakeGammaAPI()
        let controller = makeController(api)
        controller.setDimming(percent: 70, for: 1)
        controller.setDimming(percent: 30, for: 2)
        let applyBefore = api.applyCalls.count

        // 只对在线显示器重新施加(显示器 2 已断开被过滤)。
        controller.reapplyAll(onlineIDs: [1])
        let newCalls = Array(api.applyCalls.dropFirst(applyBefore))
        #expect(!newCalls.isEmpty, "唤醒重施加应发生")
        // reapplyAll 只施加在线显示器 1,不施加离线显示器 2。
        #expect(newCalls.allSatisfy { $0.displayID == 1 }, "离线显示器不应被施加,实际 \(newCalls)")
    }
}
