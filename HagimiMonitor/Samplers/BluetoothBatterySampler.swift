import Foundation
import IOBluetooth
import CoreBluetooth
import Combine
import OSLog

/// 蓝牙设备类别,用于面板图标映射。来源优先级:CoD(IOBluetooth)>
/// device_minorType(system_profiler)>GAP Appearance(GATT 自报)>
/// 名称关键词推断;均未知归 other,不猜测设备形态。
enum BluetoothDeviceType: Equatable {
    case mouse
    case keyboard
    case headphones
    case headset
    case gamepad
    case trackpad
    case speaker
    case other

    init(minorType: String?) {
        switch minorType?.lowercased() {
        case "mouse": self = .mouse
        case "keyboard": self = .keyboard
        case "headphones", "earbuds": self = .headphones
        case "headset": self = .headset
        case "gamepad", "joystick": self = .gamepad
        case "trackpad": self = .trackpad
        case "speaker": self = .speaker
        default: self = .other
        }
    }

    /// 蓝牙 CoD(Class of Device)映射,取 IOBluetoothDevice 的
    /// deviceClassMajor/deviceClassMinor 字段:
    /// - Audio/Video(major 0x04):耳机类统一归 headphones,0x08 loudspeaker
    ///   归 speaker;
    /// - Peripheral(major 0x05):高 2 位是键盘/指向设备格式位,低 6 位是
    ///   子类型(0x01 joystick / 0x02 gamepad);
    /// - 其余 major(misc/computer 等)无稳定形态信息,返回 nil。
    static func fromClassOfDevice(major: Int, minor: Int) -> BluetoothDeviceType? {
        switch major {
        case 0x04:
            return minor == 0x08 ? .speaker : .headphones
        case 0x05:
            switch minor & 0xC0 {
            case 0x40: return .keyboard
            case 0x80, 0xC0: return .mouse
            default:
                switch minor & 0x3F {
                case 0x01, 0x02: return .gamepad
                default: return nil
                }
            }
        default:
            return nil
        }
    }

    /// GAP Appearance(GATT 0x2A01,uint16:高 10 位类别、低 6 位子类)映射,
    /// 值表出自 SIG Assigned Numbers(appearance_values.yaml)。仅映射本应用
    /// 有图标语言的形态,其余返回 nil 由调用方沿名称推断兜底。
    static func fromAppearance(_ appearance: UInt16) -> BluetoothDeviceType? {
        switch appearance {
        case 0x03C1: return .keyboard            // HID:Keyboard
        case 0x03C2: return .mouse               // HID:Mouse
        case 0x03C3, 0x03C4: return .gamepad     // HID:Joystick/Gamepad
        case 0x03C5: return .trackpad            // HID:Digitizer Tablet
        case 0x0841, 0x0842, 0x0843, 0x0844, 0x0845:
            return .speaker                      // Audio Sink:各类扬声器/Speakerphone
        case 0x0941, 0x0943, 0x0944, 0x0945, 0x0946:
            return .headphones                   // Wearable Audio:Earbud/Headphones/Neck Band/L/R
        case 0x0942: return .headset             // Wearable Audio:Headset
        default: return nil
        }
    }

    /// 无 CoD/设备类型元数据时,按名称关键词推断图标;推不出保持 other。
    static func inferred(fromName name: String) -> BluetoothDeviceType {
        let lowered = name.lowercased()
        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { lowered.contains($0) }
        }
        if containsAny(["mouse", "鼠标"]) { return .mouse }
        if containsAny(["keyboard", "键盘"]) { return .keyboard }
        if containsAny(["trackpad", "触控板"]) { return .trackpad }
        if containsAny(["gamepad", "controller", "手柄"]) { return .gamepad }
        if containsAny(["headphone", "earbud", "buds", "headset", "airpods", "耳机", "耳夹", "耳麦"]) { return .headphones }
        if containsAny(["speaker", "音箱", "音响"]) { return .speaker }
        return .other
    }

    /// SF Symbols 无蓝牙通用符号,按设备形态取图标。
    var symbol: String {
        switch self {
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .headphones, .headset: return "headphones"
        case .gamepad: return "gamecontroller"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .speaker: return "hifispeaker"
        case .other: return "questionmark.circle"
        }
    }
}

/// 单台已连接蓝牙设备。batteryLevel 为 nil 表示设备未上报电量
/// (走厂商私有协议,macOS 蓝牙栈收不到),不伪造读数。
struct BluetoothDeviceInfo: Identifiable, Equatable {
    /// 归一化 MAC(去分隔符小写)或 "ble-UUID"。跨数据源身份关联的锚点。
    let address: String
    let name: String
    let type: BluetoothDeviceType
    /// 0-100;nil = 未上报。
    let batteryLevel: Int?
    /// system_profiler 的 device_services(如 "HID BLE" / "HFP AVRCP A2DP GATT ACL")。
    var services: String? = nil

    var id: String { address }
}

/// device_batteryLevel* 解析:
/// - 单值形态("63%" / "63")直接取该值;
/// - 多分量形态("Left: 67%, Right: 65%, Case: 89%")取最小值代表设备电量;
/// - macOS 26 起 JSON 键为 device_batteryLevelMain,旧版为 device_batteryLevel,
///   多单体耳机另有 Left/Right/Case 分量——调用方把全部变体拼接后交本解析器。
/// 优先取带 % 后缀的数字(排除固件号等无关数字);无法解析返回 nil。
enum BluetoothBatteryParser {
    static func batteryLevel(from raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let tokens = numericTokens(in: raw)
        let percent = tokens.filter { $0.hasPercent }.map(\.value)
        if !percent.isEmpty {
            return percent.filter { (0...100).contains($0) }.min()
        }
        return tokens.map(\.value).filter { (0...100).contains($0) }.min()
    }

    /// 扫描字符串中的数字段,记录其后是否紧跟 %。
    private static func numericTokens(in raw: String) -> [(value: Int, hasPercent: Bool)] {
        var tokens: [(value: Int, hasPercent: Bool)] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
                continue
            }
            if let value = Int(current) {
                tokens.append((value, character == "%"))
            }
            current = ""
        }
        if let value = Int(current) {
            tokens.append((value, false))
        }
        return tokens
    }
}

/// 蓝牙设备电量探针。
///
/// 三数据源合并(按归一化 MAC / 持久化绑定表关联同一台设备):
/// 1. IOBluetooth(公开 framework,两渠道一致可用)——已配对已连接设备的
///    MAC、系统名(设备端改名实时反映)、CoD 类型,以及系统侧电量
///    (未公开 getter,AVRCP/HFP 上报;沙盒内可用)。BLE 鼠标等设备的
///    isConnected() 可能报 false,由其余数据源补齐;
/// 2. `system_profiler SPBluetoothDataType -json`——设备电量
///    (device_batteryLevel* 键;控制中心读数同源)。
///    沙盒内 bluetoothd 拒绝向沙盒客户端提供数据(实测返回空骨架),
///    直连版与 IOBluetooth 读数互为冗余;
/// 3. CoreBluetooth 直读 GATT(BLEBatteryReader)——BLE 设备实时电量与清单补充
///    (2A19 Notify 推送),以及形态类别(2A01 GAP Appearance)。
///
/// 电量优先级:GATT(设备自报精确值,实时推送)> 系统侧读数
/// (IOBluetooth/profiler 同源,粗粒度分档)。
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
final class BluetoothBatterySampler: NSObject {
    /// 兜底轮询周期:连断变化由 IOBluetooth 通知即时驱动,此周期仅覆盖
    /// 通知遗漏场景(如设备休眠导致的静默链路变化)。
    private static let sampleInterval: TimeInterval = 10
    /// system_profiler 正常数百毫秒返回,个别蓝牙控制器无响应时可能挂起,
    /// 超过此时长终止进程并放弃本次结果。
    private static let probeTimeout: DispatchTimeInterval = .seconds(8)
    /// 身份绑定表的持久化键:归一化 MAC -> BLE identifier(UUID)。
    private static let bindingsDefaultsKey = "bluetooth.identityBindings"

    private var timer: AnyCancellable?
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.bluetooth-probe", qos: .utility)
    private let bleReader = BLEBatteryReader()

    /// IOBluetooth 最新快照(主线程镜像,已连接设备,归一化地址)。
    private var ioDevices: [BluetoothDeviceInfo] = []
    /// system_profiler 最新结果的主线程镜像。
    private var profilerControllerOn = false
    private var profilerDevices: [BluetoothDeviceInfo] = []
    /// BLE 侧已连接外设快照,由读取器在主线程发布。
    private var bleSnapshots: [BLEDeviceSnapshot] = []
    /// CoreBluetooth 视角的控制器开关;未授权时保持 false。
    private var cbControllerOn = false
    /// 已学身份绑定(归一化 MAC -> BLE UUID),跨启动持久。
    private var identityBindings: [String: String] = [:]
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
    /// 电量粘性缓存(归一化地址 -> 最近读到的系统侧电量):
    /// IOBluetooth 的 AVRCP 电量属性会间歇性回空,设备保持连接期间
    /// 沿用最近读数保证显示连续;设备离场(清单消失)时清除,
    /// 重连后重新学习,不会残留跨会话旧值。
    private var lastKnownBattery: [String: Int] = [:]

    /// 已连接蓝牙设备(按「有电量优先、再按名称」排序)。
    @Published private(set) var devices: [BluetoothDeviceInfo] = []
    /// 蓝牙控制器是否开启;关闭时面板不渲染蓝牙行。
    @Published private(set) var controllerOn = false

    override init() {
        // 迁移历史绑定键(原始 MAC 格式)为归一化格式。
        let stored = UserDefaults.standard
            .dictionary(forKey: Self.bindingsDefaultsKey) as? [String: String] ?? [:]
        identityBindings = stored.reduce(into: [:]) { result, pair in
            result[Self.normalizeMAC(pair.key)] = pair.value
        }
    }

    func start() {
        guard timer == nil else { return }
        bleReader.updateKnownIdentifiers(boundIdentifiers())
        bleReader.onSnapshotsUpdate = { [weak self] snapshots in
            guard let self else { return }
            self.bleSnapshots = snapshots
            self.publishMerged()
        }
        bleReader.onControllerStateUpdate = { [weak self] isOn in
            guard let self else { return }
            self.cbControllerOn = isOn
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
        profilerControllerOn = false
        profilerDevices = []
        bleSnapshots = []
        cbControllerOn = false
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
    /// 补充合并。沙盒内返回空骨架,不影响快速路径。
    private func probeProfiler() {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = Self.probe()
            DispatchQueue.main.async {
                self.profilerControllerOn = snapshot.controllerOn
                self.profilerDevices = snapshot.devices
                AppLogger.sampler.info("Bluetooth probe: profiler=\(snapshot.devices.count), io=\(self.ioDevices.count)")
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
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
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
        for address in newAddresses where batteryRetryWorksByAddress[address] == nil {
            batteryRetryWorksByAddress[address] = [2, 6, 15, 30].map { delay in
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
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

    /// 合并三数据源并发布:新学到的身份绑定持久化;排序后发布。
    private func publishMerged() {
        controllerOn = profilerControllerOn || cbControllerOn || !ioDevices.isEmpty
        let result = Self.merge(
            ioDevices: ioDevices,
            profilerDevices: profilerDevices,
            bleSnapshots: bleSnapshots,
            bindings: identityBindings
        )
        if !result.learnedBindings.isEmpty {
            identityBindings.merge(result.learnedBindings) { _, new in new }
            UserDefaults.standard.set(identityBindings, forKey: Self.bindingsDefaultsKey)
            bleReader.updateKnownIdentifiers(boundIdentifiers())
        }
        devices = Self.displayOrder(result.devices)
        let summary = devices
            .map { "\($0.name)=\($0.batteryLevel.map { "\($0)%" } ?? "-")" }
            .joined(separator: ", ")
        AppLogger.sampler.info("Bluetooth merged: \(summary, privacy: .public)")
    }

    /// 绑定表当前已知的外设标识(identifier 兜底召回名单)。
    private func boundIdentifiers() -> [UUID] {
        identityBindings.values.compactMap(UUID.init(uuidString:))
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
            // 读到新值更新粘性缓存;回空时沿用缓存,电量显示不断流。
            let fresh = Self.ioBatteryPercent(of: device)
            if let fresh {
                lastKnownBattery[address] = fresh
            }
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
                  (1...100).contains(boxed.intValue) else {
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

        // 3b) 同名匹配 + 学习绑定。
        for index in merged.indices where !consumedIndices.contains(index) {
            guard let snapshotIndex = remainingSnapshots.firstIndex(where: { $0.name == merged[index].name }) else {
                continue
            }
            let snapshot = remainingSnapshots.remove(at: snapshotIndex)
            mergeEntry(at: index, with: snapshot)
            learned[merged[index].address] = snapshot.identifier.uuidString
        }

        // 3c) 相似度配对 + 学习绑定:设备端改名后名字对不上,按归一化编辑
        //     距离找最相似的未绑定条目;最优唯一且足够近时认定同一设备
        //     (歧义或不够近时不猜,留作 CB 独有条目),学习绑定后不再依赖。
        if !remainingSnapshots.isEmpty {
            var consumedSnapshotIndices = Set<Int>()
            for (snapshotIndex, snapshot) in remainingSnapshots.enumerated() {
                guard let cbName = snapshot.name else { continue }
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

    private static func probe() -> (controllerOn: Bool, devices: [BluetoothDeviceInfo]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return (false, [])
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
            return (false, [])
        }
        task.waitUntilExit()

        guard task.terminationStatus == 0, let output else {
            return (false, [])
        }
        return parse(profilerJSON: output)
    }

    /// 解析 system_profiler SPBluetoothDataType -json 输出。拆成纯函数便于单测。
    static func parse(profilerJSON data: Data) -> (controllerOn: Bool, devices: [BluetoothDeviceInfo]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]],
              let entry = entries.first else {
            return (false, [])
        }

        let controller = entry["controller_properties"] as? [String: Any]
        let controllerOn = (controller?["controller_state"] as? String) == "attrib_on"

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

        return (controllerOn, displayOrder(devices))
    }
}
