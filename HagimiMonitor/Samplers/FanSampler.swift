import Foundation
import Combine
import OSLog

/// 风扇采样器:周期读 SMC 的 FNum / F0Ac.../F0Mn/F0Mx。
/// 与 SystemMonitorSampler 解耦:风扇读数是「多风扇列表」而非「单模块值」,且只在
/// `fanAvailable == true` 时才有意义;不进入标准 MonitorKind 采样管线。
/// 启动时读 FNum 一次缓存 count,后续采样只读 RPM/min/max。
final class FanSampler {
    /// 采样周期:风扇响应慢(温度变化后几秒到十几秒),2s 足够。
    private static let sampleInterval: TimeInterval = 2.0

    private let smcReader: SMCReader?
    private var timer: AnyCancellable?
    /// 启动时缓存,后续不再读 FNum(FNum 是机器静态属性)。
    private let fanCount: Int

    /// 当前所有风扇读数。fans 为空 = 该机无风扇或读取失败。
    @Published private(set) var fans: [FanInfo] = []

    init(smcReader: SMCReader? = SMCReader()) {
        self.smcReader = smcReader
        // 启动时一次性读取,缓存机器物理风扇数;nil/0 = 无风扇
        self.fanCount = smcReader?.fanCount() ?? 0
    }

    /// 是否有风扇(读 FNum 成功且 > 0)。与 `fans.isEmpty` 语义略有差别:
    /// 该值在初始化时确定,`fans` 数组则随每次采样动态更新。
    var available: Bool { fanCount > 0 }

    func start() {
        guard available, timer == nil else { return }
        // 启动后立即采一次,避免面板展开时空白 2s
        sample()
        timer = Timer.publish(every: Self.sampleInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sample()
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample() {
        guard available, let smcReader else { return }
        let raw = smcReader.allFans()
        let newFans = raw.map { entry in
            FanInfo(
                id: entry.id,
                name: Self.fanName(id: entry.id, totalCount: fanCount),
                currentRPM: entry.currentRPM,
                minRPM: entry.minRPM,
                maxRPM: entry.maxRPM
            )
        }
        // 避免在数据未变时触发 Combine 重绘
        if newFans != fans {
            fans = newFans
        }
    }

    /// 多风扇命名约定:Mac Pro 等多风扇机 SMC 不提供 F{id}ID,按 Stats 惯例
    /// 2 风扇时叫 Left/Right,其它按 id 编号 "Fan #N"。
    private static func fanName(id: Int, totalCount: Int) -> String {
        if totalCount == 2 {
            return id == 0 ? "Left Fan" : "Right Fan"
        }
        return "Fan #\(id)"
    }
}
