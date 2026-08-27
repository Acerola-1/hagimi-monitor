import Foundation
@preconcurrency import CoreBluetooth
import OSLog

/// CoreBluetooth 侧单台已连接外设的快照。
struct BLEDeviceSnapshot: Equatable {
    /// 系统按设备 MAC 派生的稳定标识:设备改名不变、跨重启稳定。
    /// CoreBluetooth 无公开 MAC 接口,此标识是与 system_profiler 地址
    /// 做身份关联的可靠锚点。
    let identifier: UUID
    /// 空中 GAP 名(实时,设备端改名立即反映);极少数外设可能为 nil。
    let name: String?
    /// GATT 2A19 电量读数;nil = 无标准电池服务或尚未读到。
    let batteryLevel: Int?
    /// GATT 2A01 Appearance 类别值(设备自报形态);nil = 未读到 GAP 服务。
    let appearance: UInt16?

    init(identifier: UUID, name: String?, batteryLevel: Int?, appearance: UInt16? = nil) {
        self.identifier = identifier
        self.name = name
        self.batteryLevel = batteryLevel
        self.appearance = appearance
    }
}

/// BLE 设备电量常驻读取器。
///
/// 常驻连接 + 订阅模式:
/// 1. 电量变化经 2A19 特征 Notify 实时推送,不等轮询;
/// 2. 设备断开经 didDisconnectPeripheral 秒级感知——系统对蓝牙连/断
///    不发任何公开通知(Apple 开发者论坛确认),应用自持连接是唯一事件钩子;
/// 3. 单次读取失败(如鼠标休眠)由周期性重连兜底。
///
/// 设备发现走双路召回:常见标准服务(180F/180A/1812)过滤 retrieve 为主,
/// 身份绑定表已知设备按 identifier 直接召回兜底(覆盖无标准服务缓存的设备);
/// 由本读取器主动连接后 discoverServices 强制完成 GATT 发现并读电量。
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    /// Appearance(2A01)在 GAP 服务(1800)下,是设备自报的形态类别声明,
    /// 也是无 CoD 的 BLE 设备在沙盒内唯一的形态数据源。
    private static let gapServiceUUID = CBUUID(string: "1800")
    private static let appearanceCharacteristicUUID = CBUUID(string: "2A01")
    /// 服务召回过滤:retrieveConnectedPeripherals 只返回系统已完成 GATT 缓存
    /// 且包含所列服务之一的已连接外设,空数组语义是「匹配零服务」返回空。
    /// 180A 几乎全 BLE 设备标配,1812 覆盖 HID 键鼠,与 180F 组合尽量扩大召回面。
    private static let discoveryServiceUUIDs: [CBUUID] = [
        CBUUID(string: "180F"),
        CBUUID(string: "180A"),
        CBUUID(string: "1812"),
    ]
    /// 周期性 retrieve:发现新连接设备、清理消失设备。新设备出现由
    /// sampler 的连断事件通知即时触发召回,此周期是事件遗漏时的兜底上限。
    private static let refreshInterval: TimeInterval = 10
    /// 单次连接安全网:超时未连上则放弃,等下个周期重挂。
    private static let connectTimeout: TimeInterval = 10

    /// 所有状态流转都在此队列上,天然串行。
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.ble-battery", qos: .utility)
    private var central: CBCentralManager?
    /// 常驻连接的外设(强引用保证 delegate 回调可达),值为最新已知名。
    private var tracked: [CBPeripheral: String] = [:]
    private var connectTimeouts: [CBPeripheral: DispatchWorkItem] = [:]
    private var refreshTimer: DispatchSourceTimer?
    /// 电量读数按外设标识存取:设备改名后仍指向同一条目。
    private var batteryByIdentifier: [UUID: Int] = [:]
    /// Appearance 类别值按外设标识存取,生命周期与电量读数一致。
    private var appearanceByIdentifier: [UUID: UInt16] = [:]
    /// 身份绑定表已知的外设标识:服务召回覆盖不到的设备(无标准服务缓存)
    /// 按 identifier 直接召回的兜底名单,由 sampler 在绑定更新时注入。
    private var knownIdentifiers: [UUID] = []

    /// 已连接外设快照(主线程,内容变化才发布)。
    var onSnapshotsUpdate: (([BLEDeviceSnapshot]) -> Void)?
    /// 控制器开关(poweredOn/poweredOff,主线程);授权中间态不发布。
    var onControllerStateUpdate: ((Bool) -> Void)?

    /// 更新 identifier 兜底召回名单(线程安全,串行队列写入)。
    func updateKnownIdentifiers(_ identifiers: [UUID]) {
        queue.async { [weak self] in
            self?.knownIdentifiers = identifiers
        }
    }

    /// 启动监视:幂等。初始化 CoreBluetooth,就绪后常驻监视外设。
    func ensureWatching() {
        queue.async { [weak self] in
            guard let self, self.central == nil else { return }
            self.central = CBCentralManager(
                delegate: self,
                queue: self.queue,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
    }

    /// 外部事件(蓝牙连断通知)触发立即召回:新设备的出现延迟从
    /// 一个刷新周期降到事件防抖窗口;central 未就绪时静默跳过。
    func refreshImmediately() {
        queue.async { [weak self] in
            self?.refreshNow()
        }
    }

    /// 全部关停:取消周期刷新与自持连接、清空读数,并把快照/开关状态
    /// 归零回主线程(订阅方据此摘除面板行)。stop 后 ensureWatching 幂等重建。
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshTimer?.cancel()
            self.refreshTimer = nil
            for work in self.connectTimeouts.values {
                work.cancel()
            }
            self.connectTimeouts.removeAll()
            for peripheral in self.tracked.keys {
                self.central?.cancelPeripheralConnection(peripheral)
            }
            // central 一并释放:ensureWatching 重建时会重新触发 didUpdateState,
            // 周期召回定时器与控制器状态发布随之恢复。
            self.central = nil
            self.tracked.removeAll()
            self.batteryByIdentifier.removeAll()
            self.appearanceByIdentifier.removeAll()
            self.lastPublishedSnapshots = []
            self.lastPublishedControllerState = nil
            DispatchQueue.main.async { [weak self] in
                self?.onSnapshotsUpdate?([])
                self?.onControllerStateUpdate?(false)
            }
        }
    }

    // MARK: - 常驻监视循环

    /// 同步系统连接清单 + 为新出现的外设挂常驻连接。
    private func refreshNow() {
        guard let central, central.state == .poweredOn else { return }
        // 双路召回:常见标准服务过滤为主 + 绑定表 identifier 直接召回兜底
        // (覆盖系统未缓存其标准服务的设备,召回后仅保留已连接态)。
        var peripherals = central.retrieveConnectedPeripherals(withServices: Self.discoveryServiceUUIDs)
        if !knownIdentifiers.isEmpty {
            let seen = Set(peripherals.map(\.identifier))
            let recalled = central.retrievePeripherals(withIdentifiers: knownIdentifiers)
                .filter { $0.state == .connected && !seen.contains($0.identifier) }
            peripherals.append(contentsOf: recalled)
        }
        // 无名外设没有可展示的身份,不进清单也不跟踪。
        peripherals = peripherals.filter { $0.name != nil }
        let identifiers = Set(peripherals.map(\.identifier))

        // 系统已不再报告的常驻外设:断开并清理其读数。
        for (peripheral, _) in tracked where !identifiers.contains(peripheral.identifier) {
            central.cancelPeripheralConnection(peripheral)
            tracked.removeValue(forKey: peripheral)
            connectTimeouts.removeValue(forKey: peripheral)?.cancel()
            batteryByIdentifier.removeValue(forKey: peripheral.identifier)
            appearanceByIdentifier.removeValue(forKey: peripheral.identifier)
        }

        // 已跟踪的外设同步最新空中名(设备端改名在此反映);新出现的挂常驻连接。
        var newPeripherals: [CBPeripheral] = []
        for peripheral in peripherals {
            if let knownName = tracked[peripheral] {
                tracked[peripheral] = peripheral.name ?? knownName
            } else {
                newPeripherals.append(peripheral)
            }
        }
        for peripheral in newPeripherals {
            attach(peripheral, central: central)
        }
        publishSnapshots()
    }

    /// 为外设挂常驻连接:已连接(系统持有链路)直接建交,否则发起连接并设安全网超时。
    private func attach(_ peripheral: CBPeripheral, central: CBCentralManager) {
        guard let name = peripheral.name else { return }
        tracked[peripheral] = name
        if peripheral.state == .connected {
            setUp(peripheral)
            return
        }
        central.connect(peripheral, options: nil)
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral,
                  self.tracked[peripheral] != nil,
                  peripheral.state != .connected else { return }
            self.connectTimeouts.removeValue(forKey: peripheral)
            self.tracked.removeValue(forKey: peripheral)
            self.central?.cancelPeripheralConnection(peripheral)
        }
        connectTimeouts[peripheral] = work
        queue.asyncAfter(deadline: .now() + Self.connectTimeout, execute: work)
    }

    /// 连接就绪:发现电池服务(电量)与 GAP 服务(Appearance)。
    private func setUp(_ peripheral: CBPeripheral) {
        connectTimeouts.removeValue(forKey: peripheral)?.cancel()
        peripheral.delegate = self
        peripheral.discoverServices([Self.batteryServiceUUID, Self.gapServiceUUID])
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshNow()
        }
        timer.resume()
        refreshTimer = timer
    }

    // MARK: - 发布(去重后回主线程)

    private var lastPublishedSnapshots: [BLEDeviceSnapshot] = []
    private var lastPublishedControllerState: Bool?

    private func publishSnapshots() {
        let snapshots = tracked
            .map { BLEDeviceSnapshot(
                identifier: $0.key.identifier,
                name: $0.value,
                batteryLevel: batteryByIdentifier[$0.key.identifier],
                appearance: appearanceByIdentifier[$0.key.identifier]
            ) }
            .sorted { $0.identifier.uuidString < $1.identifier.uuidString }
        guard snapshots != lastPublishedSnapshots else { return }
        lastPublishedSnapshots = snapshots
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotsUpdate?(snapshots)
        }
    }

    private func publishControllerState(_ isOn: Bool) {
        guard lastPublishedControllerState != isOn else { return }
        lastPublishedControllerState = isOn
        DispatchQueue.main.async { [weak self] in
            self?.onControllerStateUpdate?(isOn)
        }
    }

    // MARK: - CBCentralManagerDelegate
    // 回调已投递到 queue;nonisolated + 入队保证与其它操作串行。

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        queue.async { [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                self.publishControllerState(true)
                self.refreshNow()
                self.startRefreshTimer()
            case .poweredOff:
                // 蓝牙被用户关闭:清空全部状态,面板行立即消失。
                self.publishControllerState(false)
                self.tracked.removeAll()
                self.batteryByIdentifier = [:]
                self.appearanceByIdentifier = [:]
                self.publishSnapshots()
            case .unauthorized, .unsupported:
                // 用户拒绝授权 / 无硬件:静默禁用,system_profiler 路径不受影响。
                AppLogger.sampler.info("BLE battery reader disabled, central state: \(central.state.rawValue)")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        queue.async { [weak self] in
            guard let self, self.tracked[peripheral] != nil else { return }
            self.setUp(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.connectTimeouts.removeValue(forKey: peripheral)?.cancel()
            self.tracked.removeValue(forKey: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        queue.async { [weak self] in
            guard let self else { return }
            // 自持连接断开即设备离场信号:立即重新同步清单,秒级反映断连。
            self.connectTimeouts.removeValue(forKey: peripheral)?.cancel()
            self.tracked.removeValue(forKey: peripheral)
            self.refreshNow()
        }
    }

    // MARK: - CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        queue.async { [weak self] in
            guard let self, self.tracked[peripheral] != nil else { return }
            let services = peripheral.services ?? []
            if services.isEmpty {
                // 无标准服务缓存(厂商私有协议):保留清单条目,电量留空不伪造。
                return
            }
            for service in services where service.uuid == Self.batteryServiceUUID
                || service.uuid == Self.gapServiceUUID {
                peripheral.discoverCharacteristics(
                    [Self.batteryLevelCharacteristicUUID, Self.appearanceCharacteristicUUID],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        queue.async {
            let characteristics = service.characteristics ?? []
            if let characteristic = characteristics.first(where: { $0.uuid == BLEBatteryReader.batteryLevelCharacteristicUUID }) {
                peripheral.readValue(for: characteristic)
                // 2A19 标准属性含 Notify:订阅后电量变化实时推送,不等轮询。
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if let characteristic = characteristics.first(where: { $0.uuid == BLEBatteryReader.appearanceCharacteristicUUID }) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        queue.async { [weak self] in
            guard let self, self.tracked[peripheral] != nil else { return }
            switch characteristic.uuid {
            case Self.batteryLevelCharacteristicUUID:
                guard let level = characteristic.value?.first else { return }
                self.batteryByIdentifier[peripheral.identifier] = Int(level)
                AppLogger.sampler.info("BLE battery update: \(peripheral.name ?? "?", privacy: .public) = \(level)%")
                self.publishSnapshots()
            case Self.appearanceCharacteristicUUID:
                // Appearance 是 uint16,GATT 特征值统一小端。
                guard let bytes = characteristic.value, bytes.count == 2 else { return }
                self.appearanceByIdentifier[peripheral.identifier] =
                    UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                self.publishSnapshots()
            default:
                break
            }
        }
    }
}
