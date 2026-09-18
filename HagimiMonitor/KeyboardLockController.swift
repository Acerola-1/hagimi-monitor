import CoreGraphics
import Foundation
import IOKit.hid
import os

/// CGEventType.systemDefined 的共享常量。kCGEventSystemDefined ==
/// NX_SYSDEFINED == 14,该 case 在当前 SDK 对 Swift 不公开;
/// 媒体键与键盘锁两个事件 tap 都拦截此通道,统一定义避免裸值漂移。
nonisolated enum SystemDefinedEventType {
    static let rawValue: UInt32 = 14
    static let maskBit: CGEventMask = 1 << rawValue
}

/// 键盘锁定范围(引擎侧口径,由 UI 的两个开关映射而来):
/// - internalOnly: 只拦内置键盘,外接键盘照常输入(设置页「外接键盘」子开关关)。
/// - all: 内置与外接一起拦(子开关开)。
public enum KeyboardLockScope: String, CaseIterable, Codable, Sendable {
    case internalOnly
    case all
}

/// 「仅内置」范围的事件归因器:把 tap 侧收到的键盘事件判定为来自内置或外接,
/// 控制器据此放行(.external)或拦截(.builtIn)。
///
/// 证据链从强到弱:
/// 1. **按键级记账**:新按下(keyDown)经时间窗判定后,把结论按 CG 键码记账;
///    自动重复与抬起必须跟随按下时的结论,保证一颗键从按下到抬起归属一致。
///    自动重复若按"哪一侧存在按下键"判定,同侧其他键的按下态会把内置长按键
///    的重复误判成外接输入(手掌压住内置键、同时在外接键盘打字是常态场景)。
/// 2. **时间窗**:最近 100ms 内哪一侧 HID 有活动、且更近者胜。HID 报告先于
///    对应 CG 事件到达,新按下几乎总能在此命中真实来源;两侧同窗打平时判
///    外接——归因存疑时放行外接,代价小于吞掉正常打字。
/// 3. **按下态兜底**:两窗皆陈旧时,哪一侧仍有键按着判哪一侧(覆盖长按
///    修饰键的组合输入、tap 启用前已按下的键)。仅用于新按下/抬起——
///    自动重复的兜底不走按下集合:长按键自身不产生新 HID 报告,"另一侧
///    有键按着"与本次重复无关,按集合兜底会把内置长按的重复混进外接
///    打字流。
/// 4. 默认判内置(拦截)。归因存疑时宁可拦截:放行即锁定失效,而误拦
///    在下一次按键自愈。
///
/// 修饰键(flagsChanged)与媒体键(systemDefined)不走记账:前者的 HID
/// 报告刚刷新过对应侧时间戳,时间窗足够;后者键码字段是 NX 子系统私有
/// 载荷,不可作键码记账。
///
/// 线程模型:HID 回调(hidQueue)与 tap 回调(主线程)并发访问,内部
/// os_unfair_lock 串行化,锁内只做集合/字典增删与时间戳写入。
nonisolated final class KeyboardEventAttribution {
    enum Side: Sendable { case external, builtIn }
    /// tap 侧事件种类,与 CGEventType 一一对应(自动重复并入 keyDown)。
    enum EventKind: Sendable { case keyDown, keyUp, flagsChanged, systemDefined }

    /// 归因时间窗(毫秒):某侧 HID 在此窗口内的活动视为该侧"正在输入"。
    static let toleranceMilliseconds: UInt64 = 100

    private var lock = os_unfair_lock()
    /// 各侧当前按下的 HID usage 集合(含修饰键;内置键盘 consumer 页不匹配
    /// GD/Keyboard,不在此列)。
    private var externalKeysDown = Set<UInt32>()
    private var builtInKeysDown = Set<UInt32>()
    /// 各侧最近一次 HID 活动时刻(mach 绝对时间,按下与抬起都算)。
    private var lastExternalActivity: UInt64 = 0
    private var lastBuiltInActivity: UInt64 = 0
    /// 按键级结论记账:CG 键码 → 按下时的归属。抬起即销账。
    /// CG 键码字段是 Int64,直接用其类型避免转换;不同键码不同键,互不干扰。
    private var verdicts: [Int64: Side] = [:]

    private let ticksPerMillisecond: UInt64

    /// 测试可注入固定时间基准;缺省用真实 mach 绝对时间刻度。
    init(ticksPerMillisecond: UInt64? = nil) {
        if let ticksPerMillisecond {
            self.ticksPerMillisecond = ticksPerMillisecond
            return
        }
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        self.ticksPerMillisecond = info.numer > 0
            ? UInt64(1_000_000.0 * Double(info.denom) / Double(info.numer))
            : 1_000_000
    }

    /// 记录一条 HID 输入报告(键盘页或 consumer 页,按下或抬起)。
    func recordHIDReport(usage: UInt32, isDown: Bool, side: Side, now: UInt64) {
        os_unfair_lock_lock(&lock)
        switch side {
        case .external:
            lastExternalActivity = now
            if isDown { externalKeysDown.insert(usage) } else { externalKeysDown.remove(usage) }
        case .builtIn:
            lastBuiltInActivity = now
            if isDown { builtInKeysDown.insert(usage) } else { builtInKeysDown.remove(usage) }
        }
        os_unfair_lock_unlock(&lock)
    }

    /// 归因一个 tap 事件。返回 .external 表示放行,.builtIn 表示拦截。
    func decide(
        kind: EventKind,
        keyCode: Int64,
        isAutorepeat: Bool = false,
        now: UInt64
    ) -> Side {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        switch kind {
        case .keyDown where isAutorepeat:
            // 记账优先;缺失时只信时间窗,不看按下集合——长按键自身不产生
            // 新 HID 报告,而"另一侧有键按着"与本次重复无关,按集合兜底会把
            // 内置长按的重复混进外接打字流(主 bug 场景)。
            if let side = verdicts[keyCode] { return side }
            return resolveByWindow(now: now) ?? .builtIn
        case .keyDown:
            let side = resolveByEvidence(now: now)
            verdicts[keyCode] = side
            return side
        case .keyUp:
            let side = verdicts[keyCode] ?? resolveByEvidence(now: now)
            verdicts[keyCode] = nil
            return side
        case .flagsChanged, .systemDefined:
            return resolveByWindow(now: now) ?? .builtIn
        }
    }

    /// 清空全部证据与记账。锁定开始/停止/热切换范围时调用:
    /// 跨轮的按下态与陈旧结论不可作为下一轮证据。
    func reset() {
        os_unfair_lock_lock(&lock)
        externalKeysDown.removeAll()
        builtInKeysDown.removeAll()
        lastExternalActivity = 0
        lastBuiltInActivity = 0
        verdicts.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    /// 新按下/抬起的兜底归因:时间窗优先,再看按下态,默认判内置。
    private func resolveByEvidence(now: UInt64) -> Side {
        if let side = resolveByWindow(now: now) { return side }
        if !externalKeysDown.isEmpty { return .external }
        if !builtInKeysDown.isEmpty { return .builtIn }
        return .builtIn
    }

    private func resolveByWindow(now: UInt64) -> Side? {
        let tolerance = Self.toleranceMilliseconds * ticksPerMillisecond
        let sinceExternal = now >= lastExternalActivity ? now - lastExternalActivity : .max
        let sinceBuiltIn = now >= lastBuiltInActivity ? now - lastBuiltInActivity : .max
        if sinceExternal <= tolerance, sinceBuiltIn > tolerance || sinceExternal <= sinceBuiltIn {
            return .external
        }
        if sinceBuiltIn <= tolerance { return .builtIn }
        return nil
    }
}

/// 键盘锁定引擎:
/// - 纯用户态协同过滤:通过 IOHIDManager 监听底层物理输入源(区分内置 SPI/FIFO 键盘与外接 USB/蓝牙键盘),
///   结合会话级 CGEventTap 按锁定范围(全部锁定 / 仅锁定内置)精准拦截或放行。
/// - 权限:辅助功能用于创建事件 tap;输入监控用于打开键盘类 HID 设备
///   (macOS 27 起键盘 collection 带 RequiresTCCAuthorization)并接收键盘
///   按键事件与 HID 输入值。Direct 双授权,App Store 沙盒走输入监控通道。
/// - 线程模型:非隔离类,owner(`QuickToolsStore`,MainActor)在主线程调用 start/stop;
///   回调经 refcon 取回实例,无静态全局桥。
nonisolated final class KeyboardLockController {
    /// 自动解锁可选档位(分钟):防"锁了就忘"的兜底时长,由用户在设置页选。
    /// 0 表示"永不"——不启动兜底计时,锁定持续到用户手动关闭。
    static let autoUnlockMinuteOptions: [Int] = [10, 20, 30, 60, 0]

    /// 自动解锁默认时长(分钟)。
    static let defaultAutoUnlockMinutes = 20

    /// 本轮锁定的兜底时长。在 `start` 时按用户设置确定,一轮锁定内不变:
    /// 锁定中改档位只影响下一轮(避免静默缩短正在生效的锁定)。
    private(set) var autoUnlockInterval: TimeInterval = TimeInterval(defaultAutoUnlockMinutes * 60)

    /// 自动解锁触发(主线程回调),owner 负责同步 UI 状态。
    var onAutoUnlock: (@Sendable () -> Void)?

    /// 在仅锁定内置键盘模式下,外接键盘被拔出/断开时触发(主线程回调),避免用户陷入无键盘可用状态。
    var onExternalKeyboardDisconnected: (@Sendable () -> Void)?

    /// 外接键盘连接状态发生变化(插拔)时触发(主线程回调),owner 同步刷新 UI。
    var onExternalKeyboardsChanged: (@Sendable () -> Void)?

    /// 当前这轮锁定的自动解锁截止时刻,未锁定为 nil。供 owner 转发
    /// 给 UI 做逐秒倒计时;与 autoUnlockTimer 同源,读值即真相。
    private(set) var autoUnlockDeadline: Date?

    /// 当前激活的锁定范围。
    private(set) var activeScope: KeyboardLockScope = .internalOnly

    /// 当前检测到的已连接外接键盘名称列表。
    private(set) var connectedExternalKeyboards: [String] = []

    /// HID 监听是否真的拿到了键盘设备(open 成功且有匹配设备)。置 false
    /// 时来源归因无从建立,所有事件都会按"内置"兜底——owner 据此提示用户
    /// 「仅内置」已退化为全拦,而不是让用户看到键盘无输入却毫无解释。
    private(set) var hidMonitoringHealthy = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var autoUnlockTimer: DispatchSourceTimer?

    private var hidManager: IOHIDManager?

    /// 「仅内置」范围的事件归因器:tap 回调据此放行或拦截。
    private let attribution = KeyboardEventAttribution()

    // MARK: - 启动与停止

    /// 安装拦截 tap 并按范围配置 HID 监听。重复调用同范围幂等,异范围平滑热切换。
    /// - Parameters:
    ///   - scope: 锁定范围(.internalOnly 仅锁定内置,.all 锁定全部)。
    ///   - autoUnlockMinutes: 本轮锁定的兜底时长(分钟),取用户设置。
    /// - Returns: 是否成功(未授权时 tapCreate 失败返回 false)。
    func start(
        scope: KeyboardLockScope = .internalOnly,
        autoUnlockMinutes: Int = KeyboardLockController.defaultAutoUnlockMinutes
    ) -> Bool {
        if eventTap != nil {
            if activeScope == scope { return true }
            activeScope = scope
            resetTrackingState()
            if scope == .internalOnly {
                setupHIDMonitoring()
                refreshConnectedKeyboards()
            } else {
                teardownHIDMonitoring()
            }
            return true
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | SystemDefinedEventType.maskBit

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        activeScope = scope
        resetTrackingState()

        if scope == .internalOnly {
            setupHIDMonitoring()
            refreshConnectedKeyboards()
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        autoUnlockInterval = TimeInterval(autoUnlockMinutes * 60)
        if autoUnlockMinutes > 0 {
            autoUnlockDeadline = Date().addingTimeInterval(autoUnlockInterval)
            startAutoUnlockTimer()
        } else {
            // 「永不」:无兜底计时,deadline 保持 nil,UI 不显示倒计时。
            autoUnlockDeadline = nil
        }
        return true
    }

    /// 解除拦截并清理 HID 监听与自动解锁计时。重复调用幂等。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        autoUnlockDeadline = nil
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil

        teardownHIDMonitoring()
        resetTrackingState()
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        autoUnlockTimer?.cancel()
        teardownHIDMonitoring()
    }

    // MARK: - HID 监控与外接键盘感知

    private func setupHIDMonitoring() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, Self.hidInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.hidDeviceMatchingCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.hidDeviceRemovalCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // 缺输入监控时受限键盘设备打不开(RequiresTCCAuthorization),open
        // 会失败且设备集合为空;结果必须检查,否则证据链静默为空、锁会在
        // 「仅内置」下错误地全拦,而用户没有任何可诊断的信号。
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchedCount = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
        hidMonitoringHealthy = openResult == KERN_SUCCESS && matchedCount > 0
        hidManager = manager
    }

    private func teardownHIDMonitoring() {
        guard let manager = hidManager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        hidMonitoringHealthy = true
    }

    /// 重建 HID 监听(仅「仅内置」范围持有监听)。权限状态变化后调用:
    /// 受限设备在打开失败后不会自动重试,补授输入监控后重建才能拿到键盘
    /// 设备与 HID 输入值,用户无需重启应用。重建同时清空归因证据——跨轮
    /// 的按下态与结论不可复用。
    func refreshHIDMonitoring() {
        guard eventTap != nil, activeScope == .internalOnly else { return }
        teardownHIDMonitoring()
        setupHIDMonitoring()
        refreshConnectedKeyboards()
        resetTrackingState()
    }

    private func resetTrackingState() {
        attribution.reset()
    }

    private func refreshConnectedKeyboards() {
        guard let manager = hidManager else { return }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            connectedExternalKeyboards = []
            return
        }
        connectedExternalKeyboards = Self.classify(devices).externalNames
    }

    /// 一次 HID 扫描得到的键盘拓扑:外接键盘名称(已去重)与本机是否存在
    /// 内置键盘。桌面机型没有内置键盘,「仅内置」范围在其上不生效,UI 据此
    /// 说明而不是让用户以为设置起了作用。
    struct KeyboardTopology: Sendable {
        var externalNames: [String] = []
        var hasBuiltIn = false
    }

    /// 扫描当前连接的键盘拓扑(供 UI 与防呆检查使用)。
    static func scanKeyboardTopology() -> KeyboardTopology {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchDicts: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchDicts as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return KeyboardTopology()
        }
        return classify(devices)
    }

    /// 扫描当前连接的所有外接键盘名称(与 `scanKeyboardTopology` 同源,
    /// 保持既有调用点与测试不变)。
    static func scanExternalKeyboards() -> [String] {
        scanKeyboardTopology().externalNames
    }

    /// 把一批 HID 设备按内置/外接/指向性设备分类。内置键盘只标记存在性,
    /// 不进入外接列表(键盘锁按「外接键盘在不在」决定放行)。
    private static func classify(_ devices: Set<IOHIDDevice>) -> KeyboardTopology {
        var topology = KeyboardTopology()
        for dev in devices {
            if isBuiltInKeyboard(dev) {
                topology.hasBuiltIn = true
                continue
            }
            guard isExternalKeyboard(dev) else { continue }
            let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "External Keyboard"
            if !topology.externalNames.contains(product) {
                topology.externalNames.append(product)
            }
        }
        return topology
    }

    /// 判定指定 HID 设备是否为鼠标、触控板、轨迹球等指向性输入设备。
    /// 解决无线游戏鼠标/复合设备(如 VXE、罗技等)因注册侧键宏而声称包含键盘接口,被误判为外接键盘的问题。
    static func isPointingDevice(_ device: IOHIDDevice) -> Bool {
        // 1. HID 标准分类:是否显式遵循 Mouse 或 Pointer
        if IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) ||
           IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Pointer)) {
            return true
        }

        // 2. 检查设备描述中的 DeviceUsagePairs
        if let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] {
            for pair in pairs {
                let page = (pair["DeviceUsagePage"] as? Int) ?? (pair[kIOHIDDeviceUsagePageKey as String] as? Int) ?? 0
                let usage = (pair["DeviceUsage"] as? Int) ?? (pair[kIOHIDDeviceUsageKey as String] as? Int) ?? 0
                if page == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer) {
                    return true
                }
            }
        }

        // 3. 检查物理元素:是否存在相对坐标位移轴 (X / Y 相对坐标是鼠标/轨迹球的物理本质特征,打字键盘绝无相对坐标轴)
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        for el in elements {
            let page = IOHIDElementGetUsagePage(el)
            let usage = IOHIDElementGetUsage(el)
            if page == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y) && IOHIDElementIsRelative(el) {
                return true
            }
        }

        // 4. 名称特征过滤 (防呆备选)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let lower = product.lowercased()
        if lower.contains("mouse") || lower.contains("trackpad") || lower.contains("trackball") || lower.contains("touchpad") {
            return true
        }

        return false
    }

    /// 判定指定 HID 设备是否为真正的外接打字键盘。
    static func isExternalKeyboard(_ device: IOHIDDevice) -> Bool {
        // 1. 必须不是内置键盘
        guard !isBuiltInKeyboard(device) else { return false }

        // 2. 必须不是指向性设备(排除带宏侧键的各类无线/有线鼠标)
        guard !isPointingDevice(device) else { return false }

        // 3. 必须符合键盘或数字小键盘规范
        let conformsToKeyboard = IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) ||
                                 IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keypad))
        guard conformsToKeyboard else { return false }

        return true
    }

    /// 判定指定 HID 设备是否为 Mac 笔记本自带内置键盘。
    static func isBuiltInKeyboard(_ device: IOHIDDevice) -> Bool {
        if let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString) {
            if CFGetTypeID(builtIn) == CFBooleanGetTypeID() {
                return CFBooleanGetValue((builtIn as! CFBoolean))
            } else if let num = builtIn as? NSNumber {
                return num.boolValue
            }
        }
        let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
        if transport == "FIFO" || transport == "SPI" || transport == "AppleSPU" || transport == "UART" {
            return true
        }
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        if product.localizedCaseInsensitiveContains("Internal") {
            return true
        }
        return false
    }

    // MARK: - 自动解锁

    private func startAutoUnlockTimer() {
        autoUnlockTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + autoUnlockInterval)
        timer.setEventHandler { [weak self] in
            self?.stop()
            self?.onAutoUnlock?()
        }
        autoUnlockTimer = timer
        timer.resume()
    }

    // MARK: - HID 回调

    private static let hidInputValueCallback: IOHIDValueCallback = { context, result, sender, value in
        guard let context else { return }
        let controller = Unmanaged<KeyboardLockController>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        guard usagePage == kHIDPage_KeyboardOrKeypad || usagePage == UInt32(kHIDPage_Consumer) else { return }
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        guard let sender else { return }
        let dev = unsafeBitCast(sender, to: IOHIDDevice.self)
        let side: KeyboardEventAttribution.Side = KeyboardLockController.isBuiltInKeyboard(dev)
            ? .builtIn : .external
        controller.attribution.recordHIDReport(
            usage: usage,
            isDown: intValue != 0,
            side: side,
            now: mach_absolute_time()
        )
    }

    private static let hidDeviceMatchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context else { return }
        let controller = Unmanaged<KeyboardLockController>.fromOpaque(context).takeUnretainedValue()
        controller.refreshConnectedKeyboards()
        let notify = controller.onExternalKeyboardsChanged
        DispatchQueue.main.async {
            notify?()
        }
    }

    private static let hidDeviceRemovalCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context else { return }
        let controller = Unmanaged<KeyboardLockController>.fromOpaque(context).takeUnretainedValue()
        let wasExternal = KeyboardLockController.isExternalKeyboard(device)
        controller.refreshConnectedKeyboards()
        let notifyKeyboards = controller.onExternalKeyboardsChanged
        DispatchQueue.main.async {
            notifyKeyboards?()
        }
        if wasExternal && controller.activeScope == .internalOnly && controller.connectedExternalKeyboards.isEmpty {
            let notify = controller.onExternalKeyboardDisconnected
            DispatchQueue.main.async {
                notify?()
            }
        }
    }

    // MARK: - Tap 回调与过滤

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<KeyboardLockController>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = controller.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if controller.activeScope == .all {
            return nil
        }

        return controller.filterInternalOnlyEvent(event, type: type)
    }

    private func filterInternalOnlyEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let kind: KeyboardEventAttribution.EventKind
        let keyCode: Int64
        switch type {
        case .keyDown:
            kind = .keyDown
            keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        case .keyUp:
            kind = .keyUp
            keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        case .flagsChanged:
            kind = .flagsChanged
            keyCode = 0
        default:
            // systemDefined(媒体键/顶排键):键码字段是 NX 子系统私有载荷,
            // 不可当键码记账,只按时间窗归因。
            kind = .systemDefined
            keyCode = 0
        }
        let isAutorepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let side = attribution.decide(
            kind: kind,
            keyCode: keyCode,
            isAutorepeat: isAutorepeat,
            now: mach_absolute_time()
        )
        return side == .external ? Unmanaged.passUnretained(event) : nil
    }
}
