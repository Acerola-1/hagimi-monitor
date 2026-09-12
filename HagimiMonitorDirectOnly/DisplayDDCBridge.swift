import CoreGraphics
import Foundation
import IOKit
import OSLog

#if !arch(arm64)
#error("Display DDC control is Apple Silicon only. Do not compile this Direct-only module for Intel Mac.")
#endif

private let displayDDCLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "DisplayDDC")

/// 探测结果:能力判定 +(若可读)当前百分比值。
struct DDCProbeResult {
    let capability: DDCCapability
    let value: Double?
}

final class DisplayDDCBridge: @unchecked Sendable {
    private var servicesByDisplayID: [CGDirectDisplayID: DDCService] = [:]
    private var maxValues: [ControlKey: UInt16] = [:]
    /// 每个控制"生效"过的 VCP 码缓存。检测阶段一旦确定,运行期只用该码读写,
    /// 保持总线请求有界。
    private var controlCodes: [ControlKey: DDCVCPCode] = [:]
    /// 三张表的访问锁。刷新(worker 队列)与运行期读取(主线程 serviceHandle、
    /// engine 的并发 transport 读写)跨上下文,字典必须串行化。锁只覆盖字典
    /// 查找/赋值,DDC I/O 一律在锁外执行——持锁等待 2s 看门狗会阻塞其他访问。
    /// 它保证单次字典操作与「服务表替换 + 派生表裁剪」的原子性,不保证跨多次
    /// 刷新的时序;跨表不变量见 `refresh`。
    private let lock = NSLock()
    private let capabilities = DDCCapabilityStore()
    private let gate = DDCEnvironmentGate.shared

    /// 取显示器对应的 DDC 服务(值拷贝,持锁期间完成查找,I/O 由调用方在锁外执行)。
    private func ddcService(for displayID: CGDirectDisplayID) -> DDCService? {
        lock.lock(); defer { lock.unlock() }
        return servicesByDisplayID[displayID]
    }

    /// 重建服务表,并让两张派生表与之保持一致。
    ///
    /// 不变量:`maxValues`/`controlCodes` 的键只属于服务表中在线服务的显示器。
    /// 系统会把已下线显示器的 displayID 复用给别的型号,残留的旧 max/VCP 会被
    /// 当成新显示器的读数直接套用(写入百分比错位)。因此裁剪与替换在同一临界区
    /// 内完成,避免两次取锁之间读到不一致的服务表。
    ///
    /// 扫描本身在锁外,IORegistry 匹配耗时不应阻塞其他表的访问;调用方(控制器
    /// worker)单线程序列调用,故不引入代次校验。若将来出现并发调用,旧扫描结果
    /// 可能覆盖较新的表,需在此处加代次比对。
    func refresh(displayIDs: [CGDirectDisplayID]) {
        // IORegistry 匹配成本高,扫描放锁外;表更新在锁内一次完成。
        let matched = Arm64DDCMatcher().matchedServices(for: displayIDs)
        lock.lock()
        let previousIDs = Set(servicesByDisplayID.keys)
        let activeIDs = Set(matched.keys)
        servicesByDisplayID = matched
        maxValues = maxValues.filter { activeIDs.contains($0.key.displayID) }
        controlCodes = controlCodes.filter { activeIDs.contains($0.key.displayID) }
        lock.unlock()
        // 能力表自带锁,清理放替换之后:扫描窗口内迟到的探测结果会被一并清掉。
        // 被清掉的显示器下一轮检测期探测会重建 max/VCP(displays() 每轮无条件重探)。
        for id in previousIDs.subtracting(activeIDs) {
            capabilities.reset(displayID: id)
        }
    }

    func hasService(for displayID: CGDirectDisplayID) -> Bool {
        ddcService(for: displayID) != nil
    }

    func serviceHandle(displayID: CGDirectDisplayID, identity: String) -> DDCServiceHandle? {
        guard let service = ddcService(for: displayID) else { return nil }
        return DDCServiceHandle(
            identity: identity,
            chipAddress: service.chipAddress,
            displayID: displayID
        )
    }

    func transportRead(service handle: DDCServiceHandle, vcpCode: UInt8) -> DDCTransportReply? {
        guard let service = ddcService(for: CGDirectDisplayID(handle.displayID)) else { return nil }
        guard let reply = LegacyDDCPacketTransport.read(
            service: service.service,
            chipAddress: service.chipAddress,
            vcpCode: vcpCode,
            retries: 1
        ) else { return nil }
        return DDCTransportReply(resultCode: reply.resultCode, current: reply.current, max: reply.max)
    }

    func transportWrite(service handle: DDCServiceHandle, vcpCode: UInt8, value: UInt16) -> Bool {
        guard let service = ddcService(for: CGDirectDisplayID(handle.displayID)) else { return false }
        return LegacyDDCPacketTransport.write(
            service: service.service,
            chipAddress: service.chipAddress,
            vcpCode: vcpCode,
            value: value,
            retries: 1
        )
    }

    func capability(_ control: DisplayControlKind, displayID: CGDirectDisplayID) -> DDCCapability {
        capabilities.capability(ControlKey(displayID: displayID, control: control))
    }

    /// 检测期探测:遍历候选 VCP 码读一次,依据显示器应答的**结果码**判定能力。
    /// - 任一候选回复"支持"(0x00 且 max>0)→ supported,缓存该码与 max,返回当前值。
    /// - 无候选支持,但有候选明确回复"不支持"(0x01)→ unsupported(唯一会置灰的确定性负例)。
    /// - 无任何有效应答 → unknown(乐观:仍显示、仍可写)。
    func probe(_ control: DisplayControlKind, displayID: CGDirectDisplayID) -> DDCProbeResult {
        let key = ControlKey(displayID: displayID, control: control)
        guard let service = ddcService(for: displayID) else {
            capabilities.set(.unknown, for: key)
            return DDCProbeResult(capability: .unknown, value: nil)
        }
        // 抑制窗口内不打扰总线:沿用既有能力判断,值未知留待下次刷新校正。
        if gate.isSuppressed {
            return DDCProbeResult(capability: capabilities.capability(key), value: nil)
        }

        var sawUnsupported = false
        for vcp in orderedCandidates(for: key) {
            guard let reply = LegacyDDCPacketTransport.read(service: service.service, chipAddress: service.chipAddress, vcpCode: vcp.rawValue, retries: 3) else {
                continue
            }
            if reply.resultCode == 0x01 {
                sawUnsupported = true
                continue
            }
            guard reply.resultCode == 0x00, DDCRawConversion.isValidRange(max: reply.max) else {
                continue
            }

            // 完整 UInt16 范围可表示,无 32767 截断;current 超 max 按饱和处理。
            let safeMax = reply.max
            let safeCurrent = min(reply.current, safeMax)
            lock.lock()
            maxValues[key] = safeMax
            controlCodes[key] = vcp
            lock.unlock()
            capabilities.set(.supported, for: key)
            let percentage = DDCRawConversion.percent(raw: safeCurrent, max: safeMax) ?? 0
            displayDDCLog.notice(
                "Probe DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) code \(vcp.rawValue, privacy: .public) -> supported \(percentage, privacy: .public)%"
            )
            return DDCProbeResult(capability: .supported, value: percentage)
        }

        let capability: DDCCapability = sawUnsupported ? .unsupported : .unknown
        capabilities.set(capability, for: key)
        displayDDCLog.notice(
            "Probe DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) -> \(String(describing: capability), privacy: .public)"
        )
        return DDCProbeResult(capability: capability, value: nil)
    }

    /// 乐观盲写:用缓存生效码(或候选码)写入,写几遍抗丢包,**不做写后回读校验**。
    /// - 门禁抑制(睡眠/唤醒/重配置窗口)→ .skipped:不缓存该值,窗口结束后再写。
    /// - 显示器明确不支持该控制 → .busError:防御性跳过(正常情况下 UI 已置灰、不会调用)。
    /// - 报文成功上总线 → .written;全部候选都未能上总线 → .busError。
    /// 无论何种结果,瞬时失败都不冒泡给用户(见上层 handleWriteResult 的乐观处理)。
    func write(_ value: Double, for control: DisplayControlKind, displayID: CGDirectDisplayID) -> DisplayWriteOutcome {
        let key = ControlKey(displayID: displayID, control: control)
        guard let service = ddcService(for: displayID) else {
            displayDDCLog.warning("No DDC service while writing display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public)")
            return .busError
        }
        if gate.isSuppressed {
            return .skipped
        }
        if capabilities.capability(key) == .unsupported {
            return .busError
        }

        let maxValue = cachedMaxValue(for: key)
        guard var ddcValue = DDCRawConversion.ddcRaw(percent: value, max: maxValue) else {
            return .busError
        }
        if control == .volume, value > 0 {
            ddcValue = Swift.max(1, ddcValue)
        }

        for vcp in orderedCandidates(for: key) {
            let success = LegacyDDCPacketTransport.write(service: service.service, chipAddress: service.chipAddress, vcpCode: vcp.rawValue, value: ddcValue)
            displayDDCLog.notice(
                "Write DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) code \(vcp.rawValue, privacy: .public) value \(ddcValue, privacy: .public) success \(success, privacy: .public)"
            )
            if success {
                lock.lock()
                controlCodes[key] = vcp
                lock.unlock()
                return .written
            }
        }
        return .busError
    }

    private func cachedMaxValue(for key: ControlKey) -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        return maxValues[key] ?? 100
    }

    private func orderedCandidates(for key: ControlKey) -> [DDCVCPCode] {
        let candidates = DDCVCPCode.candidates(for: key.control)
        lock.lock()
        let preferred = controlCodes[key]
        lock.unlock()
        guard let preferred, candidates.contains(preferred) else {
            return candidates
        }
        return [preferred] + candidates.filter { $0 != preferred }
    }
}

/// 将稳定编排引擎接到现有 IOAVService 桥。底层调用始终在独立线程执行,
/// 引擎只接收结构化回调,不直接接触 IOKit 对象。
final class DisplayDDCTransport: DDCTransport, @unchecked Sendable {
    private let bridge: DisplayDDCBridge

    init(bridge: DisplayDDCBridge) {
        self.bridge = bridge
    }

    func read(
        service: DDCServiceHandle,
        vcpCode: UInt8,
        completion: @escaping @Sendable (DDCTransportReply?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [bridge, service] in
            completion(bridge.transportRead(service: service, vcpCode: vcpCode))
        }
    }

    func write(
        service: DDCServiceHandle,
        vcpCode: UInt8,
        value: UInt16,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [bridge, service] in
            completion(bridge.transportWrite(service: service, vcpCode: vcpCode, value: value))
        }
    }
}

private enum DDCVCPCode: UInt8 {
    case luminance = 0x10
    case contrast = 0x12
    case backlightControlLegacy = 0x13
    case audioSpeakerVolume = 0x62
    case audioMuteScreenBlank = 0x8D

    /// 默认候选:亮度只用 0x10(MCCS 标准背光码)。0x13 为兼容候选,
    /// 仅在显式配置或已验证适配 profile 下加入,默认路径不试写。
    static func candidates(for control: DisplayControlKind) -> [DDCVCPCode] {
        switch control {
        case .brightness:
            [.luminance]
        case .contrast:
            [.contrast]
        case .volume:
            [.audioSpeakerVolume]
        }
    }

    /// 显式启用 0x13 候选(仅用户在兼容设置里选择已定义编码时)。
    static func candidatesForBrightnessIncludingLegacy() -> [DDCVCPCode] {
        [.luminance, .backlightControlLegacy]
    }
}

private enum LegacyDDCPacketTransport {
    /// 结构上有效的「Get VCP Feature Reply」帧解析结果。resultCode 交给调用方判定:
    /// 0x00 = 支持, 0x01 = 不支持。current/max 仅在 resultCode==0x00 时有意义。
    struct Reply {
        let resultCode: UInt8
        let current: UInt16
        let max: UInt16
    }

    /// DDC/CI 标准 I2C 7-bit 从地址。用于**报文 checksum 计算**,始终为 0x37。
    /// 注意:传给 IOAVService 的 `chipAddress` 参数可能因 MCDP29XX 芯片而不同(0xB7),
    /// 但 DDC/CI 协议层的 checksum 始终基于此标准地址。
    private static let i2cAddress: UInt8 = 0x37
    private static let dataAddress: UInt8 = 0x51

    /// per-call 看门狗超时。仅让**当前这一次**调用放弃等待并返回失败,
    /// 不设置任何全局或跨调用状态,单次调用失败不会阻断后续调用。
    /// 睡眠/唤醒/重配置这些真正会 hang 的窗口已由 DDCEnvironmentGate 从源头拦截,
    /// 这里只是极少数窗口外 hang 的兜底,保证单条串行队列不被无限期占死。
    private static let callTimeout: DispatchTimeInterval = .seconds(2)

    /// 专用 serial I/O 队列:看门狗超时后被遗弃的 hang 任务留在这里,不与下一次并发。
    private static let ioQueue = DispatchQueue(label: "hagimi.ddc.io")

    /// 读取 VCP 特征值。chipAddress 由调用方传入(MCDP29XX 芯片用 0xB7,其余 0x37)。
    static func read(service: IOAVService, chipAddress: UInt8, vcpCode: UInt8, retries: Int = 3) -> Reply? {
        var send = [vcpCode]
        var reply = [UInt8](repeating: 0, count: 11)
        guard communicate(service: service, chipAddress: chipAddress, send: &send, reply: &reply, retries: retries) else {
            return nil
        }
        // 校验帧结构,过滤串扰/损坏应答:reply[2] 应为 0x02(feature reply op code),
        // reply[4] 应回显请求的 VCP code。结果码 reply[3] 不在此判定,交给调用方区分
        // "支持/不支持",以便正确构建能力模型(而非把不支持当读失败)。
        guard reply[2] == 0x02, reply[4] == vcpCode else {
            return nil
        }
        let maxValue = (UInt16(reply[6]) << 8) + UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) + UInt16(reply[9])
        return Reply(resultCode: reply[3], current: currentValue, max: maxValue)
    }

    /// 写入 VCP 特征值。chipAddress 由调用方传入(MCDP29XX 芯片用 0xB7,其余 0x37)。
    static func write(service: IOAVService, chipAddress: UInt8, vcpCode: UInt8, value: UInt16, retries: Int = 3) -> Bool {
        var send = [vcpCode, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        return communicate(service: service, chipAddress: chipAddress, send: &send, reply: &reply, retries: retries)
    }

    private static func communicate(service: IOAVService, chipAddress: UInt8, send: inout [UInt8], reply: inout [UInt8], retries: Int) -> Bool {
        // IOAVServiceReadI2C/WriteI2C 是阻塞内核调用,异常时可能长时间不返回。
        // 派到 serial ioQueue 执行 + semaphore 超时保护,超时仅放弃本次调用(返回 false),
        // 不设任何跨调用状态,故不会级联。escaping 闭包不能捕获 inout,拷贝后异步、完成回写。
        var sendCopy = send
        var replyCopy = reply
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        ioQueue.async {
            result = communicateUnlocked(service: service, chipAddress: chipAddress, send: &sendCopy, reply: &replyCopy, retries: retries)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + callTimeout) == .timedOut {
            displayDDCLog.error("DDC call timed out; abandoning this call only (no global lockout)")
            return false
        }
        send = sendCopy
        reply = replyCopy
        return result
    }

    /// 底层 DDC/CI 报文收发。chipAddress 传给 IOAVService 内核调用,
    /// checksum 计算始终用 i2cAddress(0x37)——因为 DDC/CI 协议的 checksum 基于
    /// I2C 标准从地址,而非芯片路由地址。
    private static func communicateUnlocked(service: IOAVService, chipAddress: UInt8, send: inout [UInt8], reply: inout [UInt8], retries: Int) -> Bool {
        let dataAddress = Self.dataAddress
        var success = false
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let checksumSeed = send.count == 1
            ? Self.i2cAddress << 1
            : Self.i2cAddress << 1 ^ dataAddress
        packet[packet.count - 1] = checksum(seed: checksumSeed, data: packet, start: 0, end: packet.count - 2)

        for _ in 0..<Swift.max(1, retries) {
            for _ in 0..<2 {
                usleep(10_000)
                let packetCount = UInt32(packet.count)
                success = packet.withUnsafeMutableBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return false
                    }
                    return IOAVServiceWriteI2C(
                        service,
                        UInt32(chipAddress),
                        UInt32(dataAddress),
                        baseAddress,
                        packetCount
                    ) == KERN_SUCCESS
                }
            }

            if reply.isEmpty {
                if success {
                    return true
                }
            } else {
                usleep(50_000)
                let replyCount = UInt32(reply.count)
                success = reply.withUnsafeMutableBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return false
                    }
                    return IOAVServiceReadI2C(
                        service,
                        UInt32(chipAddress),
                        0,
                        baseAddress,
                        replyCount
                    ) == KERN_SUCCESS
                }
                if success, reply.count >= 2 {
                    success = checksum(seed: 0x50, data: reply, start: 0, end: reply.count - 2) == reply[reply.count - 1]
                }
                if success {
                    return true
                }
            }

            usleep(20_000)
        }

        return false
    }

    private static func checksum(seed: UInt8, data: [UInt8], start: Int, end: Int) -> UInt8 {
        guard start <= end else {
            return seed
        }

        var value = seed
        for index in start...end {
            value ^= data[index]
        }
        return value
    }
}

private final class Arm64DDCMatcher {
    private static let maxMatchScore = 20

    func matchedServices(for displayIDs: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCService] {
        let registryServices = registryServicesForMatching()
        var candidatesByScore: [Int: [DDCService]] = [:]

        for displayID in displayIDs where CGDisplayIsBuiltin(displayID) == 0 {
            for registryService in registryServices {
                let score = matchScore(displayID: displayID, registryService: registryService)
                guard score > 0, let service = registryService.service else {
                    continue
                }
                let candidate = DDCService(
                    displayID: displayID,
                    service: service,
                    serviceLocation: registryService.serviceLocation,
                    matchScore: score,
                    chipAddress: registryService.isMCDP29XX ? 0xB7 : 0x37
                )
                candidatesByScore[score, default: []].append(candidate)
            }
        }

        var matched: [CGDirectDisplayID: DDCService] = [:]
        var usedDisplayIDs: Set<CGDirectDisplayID> = []
        var usedLocations: Set<Int> = []

        for score in stride(from: Self.maxMatchScore, through: 1, by: -1) {
            guard let candidates = candidatesByScore[score] else {
                continue
            }
            for candidate in candidates {
                guard !usedDisplayIDs.contains(candidate.displayID),
                      !usedLocations.contains(candidate.serviceLocation)
                else {
                    continue
                }
                matched[candidate.displayID] = candidate
                usedDisplayIDs.insert(candidate.displayID)
                usedLocations.insert(candidate.serviceLocation)
                displayDDCLog.debug(
                    "Matched DDC service display \(candidate.displayID, privacy: .public) location \(candidate.serviceLocation, privacy: .public) score \(candidate.matchScore, privacy: .public) chip \(String(format: "0x%02X", candidate.chipAddress), privacy: .public)"
                )
            }
        }

        displayDDCLog.debug("Matched \(matched.count, privacy: .public) DDC services from \(registryServices.count, privacy: .public) registry services")
        return matched
    }

    private func registryServicesForMatching() -> [RegistryService] {
        var services: [RegistryService] = []
        var serviceLocation = 0
        var current = RegistryService()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            return []
        }
        defer {
            IOObjectRelease(root)
        }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer {
            IOObjectRelease(iterator)
        }

        let framebufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]
        let serviceName = "DCPAVServiceProxy"

        while let object = nextObject(namedLike: framebufferNames + [serviceName], iterator: &iterator) {
            defer {
                IOObjectRelease(object.entry)
            }

            if framebufferNames.contains(object.name) {
                current = registryDisplayProperties(entry: object.entry)
                serviceLocation += 1
                current.serviceLocation = serviceLocation
            } else if object.name == serviceName {
                attachAVService(entry: object.entry, to: &current)
                if current.service != nil {
                    services.append(current)
                }
            }
        }

        return services
    }

    private func nextObject(
        namedLike names: [String],
        iterator: inout io_iterator_t
    ) -> (name: String, entry: io_service_t)? {
        let namePointer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer {
            namePointer.deallocate()
        }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL,
                  IORegistryEntryGetName(entry, namePointer) == KERN_SUCCESS
            else {
                return nil
            }

            let name = String(cString: namePointer)
            if names.contains(where: { name.contains($0) }) {
                return (name, entry)
            }
            IOObjectRelease(entry)
        }
    }

    private func registryDisplayProperties(entry: io_service_t) -> RegistryService {
        var service = RegistryService()

        if let unmanagedValue = IORegistryEntryCreateCFProperty(
            entry,
            "EDID UUID" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ), let value = unmanagedValue.takeRetainedValue() as? String {
            service.edidUUID = value
        }

        let path = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_string_t>.size)
        defer {
            path.deallocate()
        }
        if IORegistryEntryGetPath(entry, kIOServicePlane, path) == KERN_SUCCESS {
            service.ioDisplayLocation = String(cString: path)
        }

        if let unmanagedAttributes = IORegistryEntryCreateCFProperty(
            entry,
            "DisplayAttributes" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ), let attributes = unmanagedAttributes.takeRetainedValue() as? NSDictionary {
            if let productAttributes = attributes["ProductAttributes"] as? NSDictionary {
                service.productName = productAttributes["ProductName"] as? String ?? ""
                service.serialNumber = productAttributes["SerialNumber"] as? Int64 ?? 0
            }
        }

        return service
    }

    private func attachAVService(entry: io_service_t, to service: inout RegistryService) {
        guard let unmanagedLocation = IORegistryEntryCreateCFProperty(
            entry,
            "Location" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ), let location = unmanagedLocation.takeRetainedValue() as? String,
           location == "External",
           let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
        else {
            return
        }

        service.service = avService
        service.isMCDP29XX = isMCDP29XXProxy(entry: entry)
    }

    /// 检测 DCPAVServiceProxy 的父链上是否存在 MCDP29XX 转换芯片。
    /// M1/M2 机内 HDMI 口通过 MCDP29xx 芯片做内部 DP→HDMI 转换,该芯片需要
    /// 使用 0xB7 作为 chipAddress 而非标准的 0x37,否则 DDC 报文无法到达显示器。
    /// 这是"HDMI 显示器亮度控制失效"的已知根因(m1ddc/BetterDisplay 均有此适配)。
    /// 沿父链向上递归搜索(kIORegistryIterateParents | kIORegistryIterateRecursively),
    /// 兼容 EPICProviderClass 属性位于更上层祖先节点的情况——只带 Parents 时
    /// 仅检查一级父节点,祖先链上的标识会被漏检。
    private func isMCDP29XXProxy(entry: io_service_t) -> Bool {
        guard let value = IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            "EPICProviderClass" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents) | IOOptionBits(kIORegistryIterateRecursively)
        ) as? String else {
            return false
        }
        return value == "AppleDCPMCDP29XX"
    }

    private func matchScore(displayID: CGDirectDisplayID, registryService: RegistryService) -> Int {
        guard let info = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary? else {
            return 0
        }

        var score = 0

        if let location = info[kIODisplayLocationKey] as? String,
           !registryService.ioDisplayLocation.isEmpty,
           location == registryService.ioDisplayLocation {
            score += 10
        }

        if let productNames = info["DisplayProductName"] as? [String: String],
           let displayName = productNames["en_US"] ?? productNames.first?.value,
           !registryService.productName.isEmpty,
           displayName.lowercased() == registryService.productName.lowercased() {
            score += 1
        }

        if let serial = info[kDisplaySerialNumber] as? Int64,
           serial != 0,
           serial == registryService.serialNumber {
            score += 1
        }

        for searchKey in edidSearchKeys(from: info) {
            let prefix = registryService.edidUUID.prefix(searchKey.location + 4)
            guard searchKey.value != "0000",
                  prefix.suffix(4) == searchKey.value
            else {
                continue
            }
            score += 1
        }

        return score
    }

    private func edidSearchKeys(from info: NSDictionary) -> [(value: String, location: Int)] {
        guard let vendorID = info[kDisplayVendorID] as? Int64,
              let productID = info[kDisplayProductID] as? Int64,
              let week = info[kDisplayWeekOfManufacture] as? Int64,
              let year = info[kDisplayYearOfManufacture] as? Int64,
              let horizontalSize = info[kDisplayHorizontalImageSize] as? Int64,
              let verticalSize = info[kDisplayVerticalImageSize] as? Int64
        else {
            return []
        }

        let product = UInt16(max(0, min(productID, 65_535)))
        return [
            (String(format: "%04X", UInt16(max(0, min(vendorID, 65_535)))), 0),
            (
                String(format: "%02X", UInt8((product >> 0) & 0xFF))
                    + String(format: "%02X", UInt8((product >> 8) & 0xFF)),
                4
            ),
            (
                String(format: "%02X", UInt8(max(0, min(week, 255))))
                    + String(format: "%02X", UInt8(max(0, min(year - 1990, 255)))),
                19
            ),
            (
                String(format: "%02X", UInt8(max(0, min(horizontalSize / 10, 255))))
                    + String(format: "%02X", UInt8(max(0, min(verticalSize / 10, 255)))),
                30
            )
        ]
    }
}

private struct DDCService {
    let displayID: CGDirectDisplayID
    let service: IOAVService
    let serviceLocation: Int
    let matchScore: Int
    /// IOAVService I2C 芯片地址。标准 DDC/CI 用 0x37;M1/M2 机内 HDMI 经 MCDP29xx
    /// 转换芯片的显示器需用 0xB7,否则报文无法到达显示器。
    let chipAddress: UInt8
}

private struct RegistryService {
    var edidUUID = ""
    var productName = ""
    var serialNumber: Int64 = 0
    var ioDisplayLocation = ""
    var service: IOAVService?
    var serviceLocation = 0
    /// 是否为 MCDP29XX 转换芯片代理(M1/M2 机内 HDMI 口)。
    var isMCDP29XX = false
}
