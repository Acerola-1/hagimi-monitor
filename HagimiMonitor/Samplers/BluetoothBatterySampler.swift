import Foundation
import IOBluetooth
import CoreBluetooth
import Combine
import OSLog

/// 蓝牙设备电量探针。
///
/// 三数据源合并(按归一化 MAC / 持久化绑定表关联同一台设备):
/// 1. IOBluetooth(公开 framework,两渠道一致可用)——已配对已连接设备的
///    MAC、系统名(设备端改名实时反映)、CoD 类型,以及系统侧电量
///    (未公开 getter,AVRCP/HFP 上报;仅 Direct 版可用)。BLE 鼠标等设备的
///    isConnected() 可能报 false,由其余数据源补齐;
/// 2. `system_profiler SPBluetoothDataType -json`——设备电量
///    (device_batteryLevel* 键;控制中心读数同源)。
///    沙盒内 bluetoothd 拒绝向沙盒客户端提供数据(实测返回空骨架),
///    直连版与 IOBluetooth 读数互为冗余;
/// 3. CoreBluetooth 直读 GATT(BLEBatteryReader)——BLE 设备实时电量与清单补充
///    (2A19 Notify 推送或低频主动读取),以及形态类别(2A01 GAP Appearance)。
///    支持多 Battery Service 实例(如左耳/右耳/充电仓),聚合取最低电量。
///
/// 电量优先级:GATT(设备自报精确值,实时推送)> 系统侧读数
/// (IOBluetooth/profiler 同源,粗粒度分档)。
///
/// 支持边界:
/// - 可覆盖:经典蓝牙耳机/音箱/键鼠(设备清单可见);标准 GATT 180F/2A19
///   BLE 设备(可读取电量);macOS 自身能提供电量的设备(Direct 版兜底)。
/// - 不可覆盖:只使用厂商私有电量协议的设备;不公开标准服务且系统也不提供
///   电量的设备;完全无法被公开 API 召回的 BLE 外设。
/// - 原则:不通过长期无过滤扫描提高覆盖率(避免把附近未连接设备误认为已连接,
///   并增加功耗);对私有协议设备明确降级,不伪造数据。
///
/// 身份关联:数据源间无公开地址互换接口,用持久化绑定表(归一化 MAC ↔
/// BLE identifier)关联。绑定在无歧义窗口(同名匹配/名称相似度唯一配对)
/// 学习一次后永久生效,此后设备改名、多设备并存都能稳定合并。
///
/// 成本与缓存:system_profiler 启动数百毫秒,探针按 10s 周期在后台队列轮询;
/// IOBluetooth 查询微秒级,主线程独立刷新;BLE 电量由常驻读取器订阅推送。
/// 结果经 @Published 回主线程。
///
/// 响应速度:10s 轮询只是兜底,连断变化由 IOBluetooth 通知事件驱动——
/// 全局连接通知(per-class)+ 每设备断开通知(per-device,随清单动态注册),
/// 0.5s 防抖合并后立即跑快速路径。新连接设备的 AVRCP/HFP 电量上报
/// 滞后于链路建立,防抖窗口后再做渐进重试(2s/6s/15s/30s)。
/// 蓝牙控制器三态。unknown 表示数据源尚未给出任何确认(启动期 IOBluetooth /
/// CoreBluetooth / system_profiler 都未返回);on / off 是数据源的权威结论。
/// 面板行据此门控:unknown 保留占位行(与其他模块启动期占位一致),只有
/// off 才移除——否则启动竞态会让行消失又出现(表现为面板高度闪断)。
enum BluetoothControllerState {
    case unknown
    case on
    case off
}

final class BluetoothBatterySampler: NSObject {
    /// 兜底轮询周期:连断变化由 IOBluetooth 通知即时驱动,此周期仅覆盖
    /// 通知遗漏场景(如设备休眠导致的静默链路变化)。
    private static let sampleInterval: TimeInterval = 10
    /// system_profiler 正常数百毫秒返回,个别蓝牙控制器无响应时可能挂起,
    /// 超过此时长终止进程并放弃本次结果。
    private static let probeTimeout: DispatchTimeInterval = .seconds(8)
    /// 身份绑定表的持久化键:归一化 MAC -> BindingRecord(JSON 编码)。
    private static let bindingsDefaultsKey = "bluetooth.identityBindings"
    /// 绑定失效阈值:超过此时长未在 BLE 快照中召回则移除绑定。
    /// 7 天足够覆盖设备临时离线(出差、充电盒存放、周末不用),
    /// 又不会让废弃绑定永久残留。
    private static let bindingStalenessThreshold: TimeInterval = 7 * 24 * 60 * 60

    private var timer: AnyCancellable?
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.bluetooth-probe", qos: .utility)
    private let bleReader = BLEBatteryReader()

    /// IOBluetooth 最新快照(主线程镜像,已连接设备,归一化地址)。
    private var ioDevices: [BluetoothDeviceInfo] = []
    /// system_profiler 最新结果的主线程镜像:控制器状态仅在探针成功解析出
    /// controller_state 字段后才有值(进程失败/超时/沙盒空骨架保持 nil,
    /// 不构成关闭证据);设备清单同理,失败时维持上次结果。
    private var profilerControllerOn: Bool?
    /// profiler 控制器状态更新时间,用于与 CB 状态比较新旧。
    private var profilerControllerUpdatedAt: Date?
    private var profilerDevices: [BluetoothDeviceInfo] = []
    /// BLE 侧已连接外设快照,由读取器在主线程发布。
    private var bleSnapshots: [BLEDeviceSnapshot] = []
    /// CoreBluetooth 视角的控制器开关:central 状态回调到达后才有值
    /// (poweredOn/poweredOff),授权未决或未回调时保持 nil。
    private var cbControllerOn: Bool?
    /// CB 控制器状态更新时间:CB 回调实时到达,与 profiler 周期快照
    /// 比较新旧,避免旧快照覆盖最新状态。
    private var cbControllerUpdatedAt: Date?
    /// 已学身份绑定(归一化 MAC -> BindingRecord),跨启动持久。
    private var identityBindings: [String: BindingRecord] = [:]
    /// 全局连接通知持有体;unregister 后置 nil,避免重复注销。
    private var connectObserver: IOBluetoothUserNotification?
    /// 每台已连接设备的断开通知(归一化地址 -> 通知对象),随清单动态注册/注销。
    private var disconnectObservers: [String: IOBluetoothUserNotification] = [:]
    /// 连断事件防抖任务(合并连发链路事件为一次快速刷新)。
    private var eventRefreshWork: DispatchWorkItem?
    /// 防抖窗口内出现过连接事件(决定刷新后是否安排电量重试)。
    private var pendingConnectEvent = false
    /// 连接后电量渐进重试任务(归一化地址 → 任务组),新设备独立调度,
    /// 后续其他设备连接不重建已设备的重试链。
    private var batteryRetryWorksByAddress: [String: [DispatchWorkItem]] = [:]
    /// 最近一轮 IOBluetooth 清单的地址集,用于识别「新连接」的设备。
    private var previouslySeenAddresses: Set<String> = []
    /// 探针在飞标记:避免同一时间多个 system_profiler 进程堆积。
    private var probeInFlight = false
    /// 探针纪元:CB 报告蓝牙关闭时递增,在飞探针捕获启动时的纪元,
    /// 完成回调纪元不匹配即丢弃——防止关机前启动的探针把陈旧 attrib_on
    /// 以更新的时间戳写回,翻转已确定的关闭状态。
    private var probeEpoch = 0
    /// 生命周期 generation token:start/stop 递增,在飞异步回调捕获旧值后
    /// 到达即丢弃,防止停止后旧探针/BLE/重试回调重新发布状态。
    private var sessionGeneration: Int = 0
    /// 电量粘性缓存(归一化地址 -> 最近读到的系统侧电量):
    /// IOBluetooth 的 AVRCP 电量属性会间歇性回空,设备保持连接期间
    /// 沿用最近读数保证显示连续;设备离场(清单消失)时清除,
    /// 重连后重新学习,不会残留跨会话旧值。
    private var lastKnownBattery: [String: Int] = [:]

    /// 已连接蓝牙设备(按「有电量优先、再按名称」排序)。
    @Published private(set) var devices: [BluetoothDeviceInfo] = []
    /// 蓝牙控制器三态;off 时面板移除蓝牙行,unknown 保留占位行。
    @Published private(set) var controllerOn: BluetoothControllerState = .unknown

    override init() {
        // 迁移历史绑定数据:优先尝试新格式(JSON 编码的 [String: BindingRecord]),
        // 失败则回退到旧格式([String: String],MAC -> UUID)并升级为 BindingRecord。
        if let data = UserDefaults.standard.data(forKey: Self.bindingsDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: BindingRecord].self, from: data) {
            identityBindings = decoded.reduce(into: [:]) { result, pair in
                result[Self.normalizeMAC(pair.key)] = pair.value
            }
        } else if let stored = UserDefaults.standard
            .dictionary(forKey: Self.bindingsDefaultsKey) as? [String: String] {
            // 旧格式兼容迁移:UUID 字符串升级为 BindingRecord,version=1,lastSeenAt=now。
            let now = Date()
            identityBindings = stored.reduce(into: [:]) { result, pair in
                result[Self.normalizeMAC(pair.key)] = BindingRecord(uuid: pair.value, version: 1, lastSeenAt: now)
            }
            // 升级后写回新格式。
            if let encoded = try? JSONEncoder().encode(identityBindings) {
                UserDefaults.standard.set(encoded, forKey: Self.bindingsDefaultsKey)
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        // 单元测试运行期间跳过蓝牙采样的常驻启动,避免系统授权弹窗阻塞测试 runner。
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else {
            return
        }
        sessionGeneration += 1
        let capturedGeneration = sessionGeneration
        bleReader.updateKnownIdentifiers(boundIdentifiers())
        bleReader.onSnapshotsUpdate = { [weak self] snapshots in
            // generation 不匹配:stop() 已发生,丢弃迟到回调。
            guard let self, self.sessionGeneration == capturedGeneration else { return }
            self.bleSnapshots = snapshots
            self.publishMerged()
        }
        bleReader.onControllerStateUpdate = { [weak self] isOn in
            guard let self, self.sessionGeneration == capturedGeneration else { return }
            self.cbControllerOn = isOn
            self.cbControllerUpdatedAt = Date()
            if !isOn {
                // 蓝牙关闭:立即清空所有设备状态,避免重新打开后显示已断开的设备。
                // IOBluetooth 的 isConnected() 在蓝牙刚重新打开时可能返回缓存值,
                // 导致已断开设备被错误保留;清空后重新枚举可确保状态准确。
                self.probeEpoch += 1
                self.ioDevices = []
                self.profilerDevices = []
                self.profilerControllerOn = nil
                self.profilerControllerUpdatedAt = nil
                self.bleSnapshots = []
                self.lastKnownBattery.removeAll()
                self.previouslySeenAddresses.removeAll()
                // 取消所有在飞重试与防抖任务。
                self.batteryRetryWorksByAddress.values.forEach { works in
                    works.forEach { $0.cancel() }
                }
                self.batteryRetryWorksByAddress.removeAll()
                self.eventRefreshWork?.cancel()
                self.eventRefreshWork = nil
                self.pendingConnectEvent = false
            } else {
                // 蓝牙重新打开:延迟刷新,给系统时间更新 isConnected() 状态。
                // IOBluetooth 的连接状态在蓝牙刚重新打开时可能不准确(缓存),
                // 延迟 1.5 秒后重新枚举可确保只保留真正连接的设备。
                // 如果设备真的重新连接了,系统会发送连接通知触发即时刷新,
                // 此延迟是兜底,不会遗漏真正连接的设备。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.sessionGeneration == capturedGeneration else { return }
                    self.refreshIO()
                    self.probeProfiler()
                }
            }
            self.publishMerged()
        }
        // 已授权用户启动即常驻监视(BLE 电量经 2A19 Notify 实时推送,
        // 设备清单 10s 周期同步);授权未决则推迟到面板首次可见
        // (activateBLE),避免启动瞬间被系统授权弹窗打断。
        if CBManager.authorization == .allowedAlways {
            bleReader.ensureWatching()
        }
        // 全局连接通知:任何设备链路建立即回调,事件驱动取代轮询等待。
        connectObserver = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(ioDeviceDidConnect(_:device:))
        )
        // 快速路径先行(微秒级,面板首开即有清单),profiler 异步补充电量。
        refreshIO()
        // 启动时已连接的设备不算「新连接」,后续重试只针对事件驱动的新设备。
        previouslySeenAddresses = Set(ioDevices.map(\.address))
        probeProfiler()
        timer = Timer.publish(every: Self.sampleInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshIO()
                self?.probeProfiler()
            }
    }

    /// 面板可见时激活 CoreBluetooth:授权未决时创建 central 即触发系统
    /// 授权弹窗(此刻用户正打开面板,请求时机自然);已授权则幂等补挂
    /// (覆盖运行期授权状态变化)。被拒后系统不再弹窗,静默跳过;用户在
    /// 系统设置改为允许后,下次面板可见即恢复,无需重启应用。
    func activateBLE() {
        guard timer != nil else { return }
        switch CBManager.authorization {
        case .notDetermined, .allowedAlways:
            bleReader.ensureWatching()
        default:
            break
        }
    }

    func stop() {
        // 递增 generation,使所有在飞异步回调失效(探针/BLE/防抖/重试)。
        sessionGeneration += 1
        timer?.cancel()
        timer = nil
        connectObserver?.unregister()
        connectObserver = nil
        for observer in disconnectObservers.values {
            observer.unregister()
        }
        disconnectObservers.removeAll()
        eventRefreshWork?.cancel()
        eventRefreshWork = nil
        pendingConnectEvent = false
        batteryRetryWorksByAddress.values.forEach { works in
            works.forEach { $0.cancel() }
        }
        batteryRetryWorksByAddress.removeAll()
        previouslySeenAddresses.removeAll()
        lastKnownBattery.removeAll()
        ioDevices = []
        profilerControllerOn = nil
        profilerControllerUpdatedAt = nil
        profilerDevices = []
        bleSnapshots = []
        cbControllerOn = nil
        cbControllerUpdatedAt = nil
        probeInFlight = false
        probeEpoch += 1
        bleReader.stop()
        publishMerged()
    }

    /// 快速路径:IOBluetooth 枚举(微秒级)主线程执行,连断状态即时发布,
    /// 不等 system_profiler。同时维护每设备断开通知的注册表。
    private func refreshIO() {
        ioDevices = ioConnectedDevices()
        publishMerged()
    }

    /// 慢速路径:system_profiler 探针(数百毫秒~8s)后台执行,结果回主线程
    /// 补充合并。失败时保留最近一次成功快照,不清空 profiler 设备。
    /// 同一时间只允许一个探针在飞,避免进程堆积。
    private func probeProfiler() {
        guard !probeInFlight else { return }
        probeInFlight = true
        let capturedGeneration = sessionGeneration
        let capturedEpoch = probeEpoch
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = Self.probe()
            DispatchQueue.main.async {
                // generation 不匹配:stop() 已发生,丢弃迟到探针结果。
                guard self.sessionGeneration == capturedGeneration else { return }
                // 纪元不匹配:探针启动后蓝牙被关闭,关机前的 attrib_on 不是
                // 有效证据,丢弃;探针在飞期已由新一轮探针接管。
                guard self.probeEpoch == capturedEpoch else {
                    self.probeInFlight = false
                    return
                }
                self.probeInFlight = false
                switch outcome {
                case .success(let controllerOn, let devices):
                    self.profilerControllerOn = controllerOn
                    // 仅在探针给出权威结论时更新时间戳;controllerOn 为 nil
                    // (无 controller_state 字段)不构成新证据。
                    if controllerOn != nil {
                        self.profilerControllerUpdatedAt = Date()
                    }
                    self.profilerDevices = devices
                    AppLogger.sampler.info("Bluetooth probe success: profiler=\(devices.count), io=\(self.ioDevices.count)")
                case .failure:
                    // 启动失败 / 超时 / 异常 JSON / 沙盒空骨架:保留上次成功快照。
                    AppLogger.sampler.info("Bluetooth probe failure: keeping last known snapshot")
                }
                self.publishMerged()
            }
        }
    }

    // MARK: - 事件驱动(连断通知)

    /// 设备连接通知回调(注册线程即主线程 runloop)。
    @objc private func ioDeviceDidConnect(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        scheduleEventRefresh(retries: true)
    }

    /// 设备断开通知回调(随清单注册,断开的设备从下一轮清单消失)。
    @objc private func ioDeviceDidDisconnect(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        scheduleEventRefresh(retries: false)
    }

    /// 连断事件防抖:一次连断常伴随多条链路事件(ACL/HFP/A2DP 分链路),
    /// 0.5s 窗口合并为一次快速路径刷新 + BLE 侧即时召回。
    /// 窗口内只要出现过连接事件,刷新后就安排电量重试——不被夹在
    /// 中间的其他设备断开事件取消。
    private func scheduleEventRefresh(retries: Bool) {
        eventRefreshWork?.cancel()
        pendingConnectEvent = pendingConnectEvent || retries
        let shouldRetry = pendingConnectEvent
        let capturedGeneration = sessionGeneration
        let work = DispatchWorkItem { [weak self] in
            // generation 不匹配:stop() 已发生,丢弃迟到防抖回调。
            guard let self, self.sessionGeneration == capturedGeneration else { return }
            self.pendingConnectEvent = false
            self.refreshIO()
            self.bleReader.refreshImmediately()
            if shouldRetry {
                self.scheduleBatteryRetriesForNewDevices()
            }
        }
        eventRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 新连接设备的 AVRCP/HFP 电量上报滞后于链路建立,且首报可能
    /// 间歇性回空(属性随会话建立渐进填充):仅对新出现的设备安排
    /// 2s/6s/15s/30s 渐进重试,每轮都更新粘性缓存,读到即稳定显示;
    /// 已在场设备的重试链不受后续连接事件影响。无新设备时不重排。
    private func scheduleBatteryRetriesForNewDevices() {
        let newAddresses = Set(ioDevices.map(\.address)).subtracting(previouslySeenAddresses)
        previouslySeenAddresses = Set(ioDevices.map(\.address))
        let capturedGeneration = sessionGeneration
        for address in newAddresses where batteryRetryWorksByAddress[address] == nil {
            batteryRetryWorksByAddress[address] = [2, 6, 15, 30].map { delay in
                let work = DispatchWorkItem { [weak self] in
                    // generation 不匹配:stop() 已发生,丢弃迟到重试回调。
                    guard let self, self.sessionGeneration == capturedGeneration else { return }
                    if lastKnownBattery[address] == nil {
                        refreshIO()
                    }
                    // 读到电量即取消本设备剩余重试;未读到则留给下一档。
                    if lastKnownBattery[address] != nil,
                       let chain = batteryRetryWorksByAddress.removeValue(forKey: address) {
                        chain.forEach { $0.cancel() }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(delay), execute: work)
                return work
            }
        }
    }

    /// 控制器状态合并(纯函数,便于单测):取最新的权威证据。
    /// CB 状态是实时回调(poweredOn/poweredOff 秒级到达),profiler 是周期快照(10s 一次)。
    /// 两者均有证据时按时间戳取新,避免旧 profiler 快照覆盖最新 CB 状态。
    /// hasIODevices 视为开启的弱证据(有已连接设备说明蓝牙在工作),仅在两源均无权威状态时使用。
    static func resolveControllerState(
        cbEvidence: (isOn: Bool, at: Date)?,
        profilerEvidence: (isOn: Bool, at: Date)?,
        hasIODevices: Bool
    ) -> BluetoothControllerState {
        switch (cbEvidence, profilerEvidence) {
        case let (cb?, profiler?):
            return (cb.at >= profiler.at ? cb.isOn : profiler.isOn) ? .on : .off
        case let (cb?, nil):
            return cb.isOn ? .on : .off
        case let (nil, profiler?):
            return profiler.isOn ? .on : .off
        case (nil, nil):
            return hasIODevices ? .on : .unknown
        }
    }

    /// 合并三数据源并发布:新学到的身份绑定持久化;排序后发布。
    private func publishMerged() {
        let cbEvidence: (isOn: Bool, at: Date)? = cbControllerOn.flatMap { isOn in
            cbControllerUpdatedAt.map { (isOn, $0) }
        }
        let profilerEvidence: (isOn: Bool, at: Date)? = profilerControllerOn.flatMap { isOn in
            profilerControllerUpdatedAt.map { (isOn, $0) }
        }
        controllerOn = Self.resolveControllerState(
            cbEvidence: cbEvidence,
            profilerEvidence: profilerEvidence,
            hasIODevices: !ioDevices.isEmpty
        )

        // 将绑定记录映射为 UUID 供三源合并。
        let bindingsForMerge = identityBindings.mapValues { $0.uuid }
        let result = Self.merge(
            ioDevices: ioDevices,
            profilerDevices: profilerDevices,
            bleSnapshots: bleSnapshots,
            bindings: bindingsForMerge
        )
        if !result.learnedBindings.isEmpty {
            let now = Date()
            for (address, uuid) in result.learnedBindings {
                // 新学习绑定:version=1,lastSeenAt=now。
                identityBindings[address] = BindingRecord(uuid: uuid, version: 1, lastSeenAt: now)
            }
            persistBindings()
            bleReader.updateKnownIdentifiers(boundIdentifiers())
        }
        // 维护绑定:更新已召回的 lastSeenAt,清理长期未召回的过期绑定。
        maintainBindings(recalledUUIDs: Set(bleSnapshots.map { $0.identifier.uuidString }))
        devices = Self.displayOrder(result.devices)
        // 日常日志只记录设备数量;详细设备名/电量用 .private 隐私级别,
        // 调试构建可见但不暴露在系统日志中。
        AppLogger.sampler.info("Bluetooth merged: \(self.devices.count) devices")
        #if DEBUG
        let summary = self.devices
            .map { "\($0.name)=\($0.batteryLevel.map { "\($0)%" } ?? "-")" }
            .joined(separator: ", ")
        AppLogger.sampler.debug("Bluetooth devices: \(summary, privacy: .private)")
        #endif
    }

    /// 绑定表当前已知的外设标识(identifier 兜底召回名单)。
    private func boundIdentifiers() -> [UUID] {
        identityBindings.values.compactMap { UUID(uuidString: $0.uuid) }
    }

    /// 持久化绑定表:JSON 编码后写入 UserDefaults。
    private func persistBindings() {
        if let data = try? JSONEncoder().encode(identityBindings) {
            UserDefaults.standard.set(data, forKey: Self.bindingsDefaultsKey)
        }
    }

    /// 维护绑定表(纯函数,便于单测):更新已召回绑定的 lastSeenAt,清理长期未召回的过期绑定。
    static func maintainBindings(
        _ bindings: [String: BindingRecord],
        recalledUUIDs: Set<String>,
        now: Date = Date(),
        stalenessThreshold: TimeInterval = bindingStalenessThreshold
    ) -> (bindings: [String: BindingRecord], changed: Bool) {
        var updated = bindings
        var changed = false

        // 更新已召回绑定的 lastSeenAt(节流:距上次更新超过 1 小时才刷新)。
        for (address, record) in updated where recalledUUIDs.contains(record.uuid) {
            if now.timeIntervalSince(record.lastSeenAt) > 3600 {
                updated[address]?.lastSeenAt = now
                changed = true
            }
        }

        // 清理过期绑定:超过阈值未召回。临时离线(如设备存放、出差)不触发移除。
        for (address, record) in updated
        where now.timeIntervalSince(record.lastSeenAt) > stalenessThreshold {
            updated.removeValue(forKey: address)
            changed = true
        }

        return (updated, changed)
    }

    /// 维护绑定表:更新已召回绑定的 lastSeenAt,清理长期未召回的过期绑定。
    private func maintainBindings(recalledUUIDs: Set<String>) {
        let outcome = Self.maintainBindings(identityBindings, recalledUUIDs: recalledUUIDs)
        if outcome.changed {
            identityBindings = outcome.bindings
            persistBindings()
            bleReader.updateKnownIdentifiers(boundIdentifiers())
        }
    }

    /// MAC 归一化:去冒号/横线、转小写。IOBluetooth 报横线小写格式,
    /// system_profiler 报冒号大写格式,归一化后才能跨源对齐。
    static func normalizeMAC(_ raw: String) -> String {
        raw.lowercased().filter(\.isHexDigit)
    }

    /// IOBluetooth 侧已连接设备快照:系统名(实时反映设备端改名)、
    /// 归一化 MAC、CoD 类型、经 AVRCP/HFP 上报给系统的电量。
    /// BLE 设备的 isConnected() 可能报 false,
    /// 此类设备由 profiler/CoreBluetooth 路径补入清单。
    /// 枚举同时维护每设备断开通知注册表(断开通知是 per-device API)。
    private func ioConnectedDevices() -> [BluetoothDeviceInfo] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        var byAddress: [String: BluetoothDeviceInfo] = [:]
        for device in paired where device.isConnected() {
            guard let raw = device.addressString else { continue }
            let address = Self.normalizeMAC(raw)
            guard !address.isEmpty, byAddress[address] == nil else { continue }
            registerDisconnectObserver(for: device, address: address)
            let name = device.nameOrAddress ?? address
#if DIRECT_DISTRIBUTION
            // Direct 版:读取 IOBluetooth 未公开的电池 getter(bluetoothd 随 AVRCP/HFP 会话填充);
            // 读到新值更新粘性缓存,回空时沿用缓存,电量显示不断流。
            let fresh = Self.ioBatteryPercent(of: device)
            if let fresh {
                lastKnownBattery[address] = fresh
            }
#else
            // App Store 版:不使用私有 getter,电量由 profiler 或 BLE GATT 补齐;
            // 部分只通过该接口提供电量的经典蓝牙设备会显示"电量不可用"。
            let fresh: Int? = nil
#endif
            byAddress[address] = BluetoothDeviceInfo(
                address: address,
                name: name,
                type: BluetoothDeviceType.fromClassOfDevice(
                    major: Int(device.deviceClassMajor),
                    minor: Int(device.deviceClassMinor)
                ) ?? BluetoothDeviceType.inferred(fromName: name),
                batteryLevel: fresh ?? lastKnownBattery[address]
            )
        }
        // 清单里消失的设备注销其断开通知并清电量缓存与重试链。
        for (address, observer) in disconnectObservers where byAddress[address] == nil {
            observer.unregister()
            disconnectObservers.removeValue(forKey: address)
            lastKnownBattery.removeValue(forKey: address)
            batteryRetryWorksByAddress.removeValue(forKey: address)?.forEach { $0.cancel() }
        }
        return Array(byAddress.values)
    }

    /// 为已连接设备补注册断开通知;已注册的跳过(幂等)。
    private func registerDisconnectObserver(for device: IOBluetoothDevice, address: String) {
        guard disconnectObservers[address] == nil else { return }
        disconnectObservers[address] = device.register(
            forDisconnectNotification: self, selector: #selector(ioDeviceDidDisconnect(_:device:))
        )
    }

#if DIRECT_DISTRIBUTION
    /// 读取 IOBluetoothDevice 未公开的电池 getter(batteryPercentSingle 等)。
    /// bluetoothd 随 AVRCP/HFP 会话填充——经典蓝牙耳机的电量走此通道,
    /// 是沙盒内该类设备电量的唯一来源(实测 macOS 26)。
    /// 属性会间歇性回空(AVRCP 会话重建/懒加载期间),由调用方的
    /// 粘性缓存保证显示连续性。
    /// 读取顺序:多单体(左/右/仓)取非零最小值,单体设备取 Single/Combined/headsetBattery/裸键。
    /// responds(to:) 先确认 getter 存在(系统 API 变更时安全降级为 nil),
    /// valueForKey 装箱值统一按 NSNumber 提取,覆盖全部数值装箱类型。
    private static func ioBatteryPercent(of device: IOBluetoothDevice) -> Int? {
        func number(for key: String) -> Int? {
            guard device.responds(to: Selector((key))),
                  let boxed = device.value(forKey: key) as? NSNumber,
                  (0...100).contains(boxed.intValue) else {
                return nil
            }
            return boxed.intValue
        }
        let segmentKeys = ["batteryPercentLeft", "batteryPercentRight", "batteryPercentCase"]
        let segments = segmentKeys.compactMap { number(for: $0) }
        if !segments.isEmpty {
            return segments.min()
        }
        return number(for: "batteryPercentSingle")
            ?? number(for: "batteryPercentCombined")
            ?? number(for: "headsetBattery")
            ?? number(for: "batteryPercent")
    }
#endif

    /// 三数据源合并(纯函数,可单测):
    /// 1. IOBluetooth 条目为骨架(归一化 MAC + CoD 类型 + 系统名 + 系统侧电量);
    /// 2. profiler 条目按归一化 MAC 注入电量(骨架缺电量时),缺类型时补强;
    ///    profiler 独有条目(BLE 鼠标等 isConnected 报 false 的设备)追加;
    /// 3. BLE 快照按 已学绑定 → 同名 → 名称相似度唯一配对 关联,
    ///    GATT 精确电量覆盖系统侧读数,并在配对成功时学习绑定(此后改名免疫);
    /// 4. 未消化的 BLE 条目为 CB 独有设备,按 identifier 作稳定 id 补入。
    ///
    /// 名称显示与系统 UI 一致(IOBluetooth 系统名优先);纯 profiler 条目
    /// (services 非 nil)在 CB 关联时用 GAP 名覆盖——这是设备端改名后
    /// profiler 缓存旧名的场景。
    static func merge(
        ioDevices: [BluetoothDeviceInfo],
        profilerDevices: [BluetoothDeviceInfo],
        bleSnapshots: [BLEDeviceSnapshot],
        bindings: [String: String]
    ) -> (devices: [BluetoothDeviceInfo], learnedBindings: [String: String]) {
        var merged = ioDevices
        var learned: [String: String] = [:]
        var consumedIndices = Set<Int>()
        var remainingSnapshots = bleSnapshots

        func mergeEntry(at index: Int, with snapshot: BLEDeviceSnapshot) {
            let device = merged[index]
            // 纯 profiler 条目(services 非 nil)的名可能滞后于设备端改名,
            // 用 GAP 实时名覆盖;IOBluetooth 条目(services nil)的系统名
            // 已实时,保留。
            let name = device.services == nil ? device.name : (snapshot.name ?? device.name)
            // 类型已定位(CoD/profiler 元数据)则保留;仍未知时用设备自报的
            // GAP Appearance 补位——这是设备端的形态声明,不是名称猜测。
            let type = device.type != .other
                ? device.type
                : snapshot.appearance.flatMap(BluetoothDeviceType.fromAppearance) ?? device.type
            merged[index] = BluetoothDeviceInfo(
                address: device.address,
                name: name,
                type: type,
                // GATT 2A19 是设备自报的精确读数且经 Notify 实时推送;
                // profiler 的 AVRCP 值是系统粗粒度分档,仅作兜底。
                batteryLevel: snapshot.batteryLevel ?? device.batteryLevel,
                services: device.services
            )
            consumedIndices.insert(index)
        }

        // 2) profiler 注入电量(直连版;沙盒内 profiler 为空自动跳过)。
        for device in profilerDevices {
            let key = normalizeMAC(device.address)
            if let index = merged.firstIndex(where: { $0.address == key }) {
                var target = merged[index]
                var updated = false
                if target.batteryLevel == nil, let level = device.batteryLevel {
                    target = BluetoothDeviceInfo(
                        address: target.address, name: target.name, type: target.type,
                        batteryLevel: level, services: target.services
                    )
                    updated = true
                }
                if target.type == .other, device.type != .other {
                    target = BluetoothDeviceInfo(
                        address: target.address, name: target.name, type: device.type,
                        batteryLevel: target.batteryLevel, services: target.services
                    )
                    updated = true
                }
                if updated { merged[index] = target }
            } else {
                merged.append(BluetoothDeviceInfo(
                    address: key,
                    name: device.name,
                    type: device.type,
                    batteryLevel: device.batteryLevel,
                    services: device.services
                ))
            }
        }

        // 3a) 已学绑定:UUID 命中即关联,不受当前名字与其它设备干扰。
        for (address, boundUUID) in bindings {
            guard let snapshotIndex = remainingSnapshots.firstIndex(where: { $0.identifier.uuidString == boundUUID }),
                  let mergedIndex = merged.firstIndex(where: { $0.address == address }),
                  !consumedIndices.contains(mergedIndex) else {
                continue
            }
            mergeEntry(at: mergedIndex, with: remainingSnapshots.remove(at: snapshotIndex))
        }

        // 3b) 同名匹配 + 学习绑定:仅当两侧名称均唯一时才允许,避免同名设备错误绑定。
        // 统计两侧名称出现次数
        var mergedNameCount: [String: Int] = [:]
        for index in merged.indices where !consumedIndices.contains(index) {
            mergedNameCount[merged[index].name, default: 0] += 1
        }
        var snapshotNameCount: [String: Int] = [:]
        for snapshot in remainingSnapshots {
            if let name = snapshot.name {
                snapshotNameCount[name, default: 0] += 1
            }
        }

        for index in merged.indices where !consumedIndices.contains(index) {
            let name = merged[index].name
            // 两侧均唯一才允许学习绑定:两台同名设备不得任选一台永久绑定
            guard mergedNameCount[name] == 1, snapshotNameCount[name] == 1,
                  let snapshotIndex = remainingSnapshots.firstIndex(where: { $0.name == name }) else {
                continue
            }
            let snapshot = remainingSnapshots.remove(at: snapshotIndex)
            mergeEntry(at: index, with: snapshot)
            learned[merged[index].address] = snapshot.identifier.uuidString
            // 更新计数,避免后续重复处理
            mergedNameCount[name] = 0
            snapshotNameCount[name] = 0
        }

        // 3c) 相似度配对 + 学习绑定:设备端改名后名字对不上,按归一化编辑
        //     距离找最相似的未绑定条目;最优唯一且足够近时认定同一设备
        //     (歧义或不够近时不猜,留作 CB 独有条目),学习绑定后不再依赖。
        //     BLE 侧名称不唯一时同样禁止学习绑定(同名设备不得任选一台)。
        if !remainingSnapshots.isEmpty {
            // 统计 BLE 侧名称出现次数
            var snapshotNameCount3c: [String: Int] = [:]
            for snapshot in remainingSnapshots {
                if let name = snapshot.name {
                    snapshotNameCount3c[name, default: 0] += 1
                }
            }
            var consumedSnapshotIndices = Set<Int>()
            for (snapshotIndex, snapshot) in remainingSnapshots.enumerated() {
                guard let cbName = snapshot.name else { continue }
                // BLE 侧名称不唯一时不允许学习绑定
                guard snapshotNameCount3c[cbName] == 1 else { continue }
                var scored: [(index: Int, distance: Double)] = []
                for index in merged.indices where !consumedIndices.contains(index) {
                    guard bindings[merged[index].address] == nil else { continue }
                    scored.append((index, nameDistance(merged[index].name, cbName)))
                }
                scored.sort { $0.distance < $1.distance }
                if let best = scored.first,
                   best.distance <= 1.0 / 3.0,
                   scored.count == 1 || scored[1].distance - best.distance > 0.2 {
                    mergeEntry(at: best.index, with: snapshot)
                    learned[merged[best.index].address] = snapshot.identifier.uuidString
                    consumedSnapshotIndices.insert(snapshotIndex)
                }
            }
            for snapshotIndex in consumedSnapshotIndices.sorted(by: >) {
                remainingSnapshots.remove(at: snapshotIndex)
            }
        }

        // 4) 未消化的 BLE 条目为 CB 独有设备:identifier 作稳定 id 补入,
        //    类型按 GAP Appearance(设备自报)优先、名称关键词兜底。
        for snapshot in remainingSnapshots {
            let name = snapshot.name ?? String(snapshot.identifier.uuidString.prefix(8))
            merged.append(BluetoothDeviceInfo(
                address: "ble-\(snapshot.identifier.uuidString)",
                name: name,
                type: snapshot.appearance.flatMap(BluetoothDeviceType.fromAppearance)
                    ?? BluetoothDeviceType.inferred(fromName: name),
                batteryLevel: snapshot.batteryLevel
            ))
        }

        return (merged, learned)
    }

    /// 归一化编辑距离(0-1,越小越相似):改名通常只动少数字符。
    private static func nameDistance(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty {
            return a.isEmpty && b.isEmpty ? 0 : 1
        }
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        var previous = Array(0...n)
        var current = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            current[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return Double(previous[n]) / Double(Swift.max(m, n))
    }

    /// 展示排序:有电量上报的设备排前(信息量大),同组内按名称排,列表顺序稳定不跳动。
    static func displayOrder(_ devices: [BluetoothDeviceInfo]) -> [BluetoothDeviceInfo] {
        devices.sorted { lhs, rhs in
            let lhsMissing = lhs.batteryLevel == nil
            let rhsMissing = rhs.batteryLevel == nil
            if lhsMissing != rhsMissing { return !lhsMissing }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private static func probe() -> ProbeOutcome {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return .failure
        }

        // readDataToEndOfFile 会阻塞到进程退出,若 system_profiler 挂起则永久不返。
        // 读输出放到独立线程,本线程用信号量等待,超时后终止进程并放弃本次结果。
        nonisolated(unsafe) var output: Data?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }

        if done.wait(timeout: .now() + probeTimeout) == .timedOut {
            task.terminate()
            return .failure
        }
        task.waitUntilExit()

        guard task.terminationStatus == 0, let output else {
            return .failure
        }
        return parse(profilerJSON: output)
    }

    /// 解析 system_profiler SPBluetoothDataType -json 输出。拆成纯函数便于单测。
    /// controllerOn 仅在输出携带 controller_state 字段时给出权威结论
    /// (attrib_on 为开,其余值为关);JSON 失效、根字段缺失或沙盒空骨架
    /// (无 controller_state 且无 device_connected)返回 .failure,调用方保留
    /// 最近一次成功快照,不构成「蓝牙关闭」证据。
    static func parse(profilerJSON data: Data) -> ProbeOutcome {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]],
              let entry = entries.first else {
            return .failure
        }

        let controllerState = (entry["controller_properties"] as? [String: Any])?["controller_state"] as? String
        let controllerOn = controllerState.map { $0 == "attrib_on" }
        let hasConnectedField = entry["device_connected"] != nil
        // 沙盒空骨架:无 controller_state 且无 device_connected 字段,不构成权威结论。
        if controllerState == nil && !hasConnectedField {
            return .failure
        }

        var devices: [BluetoothDeviceInfo] = []
        // device_connected 是「单键字典」数组:每个元素形如 { "设备名": { 属性... } }。
        if let connected = entry["device_connected"] as? [[String: Any]] {
            for item in connected {
                for (name, info) in item {
                    guard let props = info as? [String: Any] else { continue }
                    // 电量键随系统版本漂移:macOS 26 为 device_batteryLevelMain,
                    // 旧版为 device_batteryLevel,多单体耳机有 Left/Right/Case 分量。
                    // 收集全部变体拼接后交给解析器统一取值。
                    let batteryRaw = props.keys
                        .filter { $0.hasPrefix("device_batteryLevel") }
                        .sorted()
                        .compactMap { props[$0] as? String }
                        .joined(separator: ", ")
                    devices.append(BluetoothDeviceInfo(
                        address: normalizeMAC(props["device_address"] as? String ?? name),
                        name: name,
                        type: BluetoothDeviceType(minorType: props["device_minorType"] as? String),
                        batteryLevel: BluetoothBatteryParser.batteryLevel(from: batteryRaw.isEmpty ? nil : batteryRaw),
                        services: props["device_services"] as? String
                    ))
                }
            }
        }

        return .success(controllerOn: controllerOn, devices: displayOrder(devices))
    }
}
