import Foundation
import Combine
import OSLog

/// 风扇 SMC 读取协议:抽象出 FanSampler 依赖的最小接口,便于单元测试注入 mock。
/// SMCReader 已符合此协议(fanCount / allFans 签名匹配)。
protocol FanSMCReading: AnyObject {
    /// 读 SMC key `FNum`,返回机器物理风扇数;无风扇或读取失败返回 nil。
    func fanCount() -> Int?
    /// 读取所有风扇的当前 RPM 与 min/max 范围。返回数组长度 = fanCount。
    func allFans() -> [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)]
}

/// 风扇采样器:周期读 SMC 的 FNum / F0Ac.../F0Mn/F0Mx。
/// 与 SystemMonitorSampler 解耦:风扇读数是「多风扇列表」而非「单模块值」,且只在
/// `fanAvailable == true` 时才有意义;不进入标准 MonitorKind 采样管线。
/// 启动时读 FNum 一次缓存 count,后续采样只读 RPM/min/max。
final class FanSampler {
    /// 采样周期:风扇响应慢(温度变化后几秒到十几秒),2s 足够。
    private static let sampleInterval: TimeInterval = 2.0

    private let smcReader: FanSMCReading?
    private var timer: AnyCancellable?
    /// 启动时缓存,后续不再读 FNum(FNum 是机器静态属性)。
    private let fanCount: Int

    /// 当前所有风扇读数。fans 为空 = 该机无风扇或读取失败。
    @Published private(set) var fans: [FanInfo] = []

    /// 当前风扇系统整体状态(取所有风扇中最差值)。每次采样后同步更新。
    /// 告警服务订阅此值,在状态恶化时触发通知。
    @Published private(set) var status: FanStatus = .unknown

    /// SMC 读取器工厂:仅在 DISPLAY_CONTROL(直连版)下创建 SMCReader。
    /// 沙盒版 IOServiceOpen(AppleSMC) 被 sandbox 拒绝,直接返回 nil,
    /// 使 fanCount=0 → available=false,风扇模块静默禁用(与 CPU 温度门控一致)。
    private static func makeSMCReader() -> FanSMCReading? {
        #if DISPLAY_CONTROL
        return SMCReader()
        #else
        return nil
        #endif
    }

    init(smcReader: FanSMCReading? = makeSMCReader()) {
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
        // 同步更新整体状态(取最差风扇状态),供告警服务订阅。
        let newStatus = FanInfo.overallStatus(of: newFans)
        if newStatus != status {
            status = newStatus
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
