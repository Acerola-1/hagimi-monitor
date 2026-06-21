import CoreGraphics
import Foundation
import IOKit
import OSLog

#if !arch(arm64)
#error("Display DDC control is Apple Silicon only. Do not compile this Direct-only module for Intel Mac.")
#endif

private let displayDDCLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "DisplayDDC")

final class DisplayDDCBridge {
    private var servicesByDisplayID: [CGDirectDisplayID: DDCService] = [:]
    private var maxValues: [ControlKey: UInt16] = [:]
    private var controlCodes: [ControlKey: DDCVCPCode] = [:]
    private let registry = DDCFaultRegistry()

    func refresh(displayIDs: [CGDirectDisplayID]) {
        let knownIDs = Set(servicesByDisplayID.keys)
        for id in knownIDs.subtracting(displayIDs) {
            registry.reset(displayID: id)
        }
        servicesByDisplayID = Arm64DDCMatcher().matchedServices(for: displayIDs)
    }

    func hasService(for displayID: CGDirectDisplayID) -> Bool {
        servicesByDisplayID[displayID] != nil
    }

    func read(_ control: DisplayControlKind, displayID: CGDirectDisplayID, fastFail: Bool = false) -> Double? {
        guard let service = servicesByDisplayID[displayID] else {
            displayDDCLog.debug("No DDC service for display \(displayID, privacy: .public)")
            return nil
        }

        let key = ControlKey(displayID: displayID, control: control)
        if registry.isDisabled(key) {
            return nil
        }

        for vcp in orderedCandidates(for: key) {
            let useLongDelay = registry.shouldUseLongerDelay(key)
            let retries = fastFail ? 2 : 5
            guard let values = DDCTransport.read(service: service.service, vcpCode: vcp.rawValue, longerDelay: useLongDelay, maxRetries: retries),
                  values.max > 0
            else {
                continue
            }

            let safeMax = DDCRawConversion.sanitize(max: values.max)
            let safeCurrent = min(values.current, safeMax)
            maxValues[key] = safeMax
            controlCodes[key] = vcp
            registry.recordReadSuccess(key)

            let percentage = DDCRawConversion.percent(raw: safeCurrent, max: safeMax)

            displayDDCLog.notice(
                "Read DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) code \(vcp.rawValue, privacy: .public) raw \(values.current, privacy: .public)/\(values.max, privacy: .public) safe \(safeCurrent, privacy: .public)/\(safeMax, privacy: .public) percentage \(percentage, privacy: .public)"
            )
            return percentage
        }

        displayDDCLog.warning("Failed to read DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public)")
        registry.recordReadFailure(key)
        return nil
    }

    func write(_ value: Double, for control: DisplayControlKind, displayID: CGDirectDisplayID) -> Bool {
        guard let service = servicesByDisplayID[displayID] else {
            displayDDCLog.warning("No DDC service while writing display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public)")
            return false
        }

        let key = ControlKey(displayID: displayID, control: control)
        if registry.isDisabled(key) {
            return false
        }

        let maxValue = maxValues[key] ?? 100
        var ddcValue = DDCRawConversion.ddcRaw(percent: value, max: maxValue)
        if control == .volume, value > 0 {
            ddcValue = Swift.max(1, ddcValue)
        }

        // 音量降到 0 时不再写 0x8D(audioMuteScreenBlank):很多显示器不支持
        // 这条 VCP,写失败会让本次 mute 完全失效,且后续 markControlUnsupported
        // 会把整个音量控制禁用掉。
        // 对齐 MonitorControl 默认行为(prefs.enableMuteUnmute = false):
        // mute 直接写 audioSpeakerVolume(0x62) = 0,绝大多数显示器都支持。
        for vcp in orderedCandidates(for: key) {
            let success = DDCTransport.write(service: service.service, vcpCode: vcp.rawValue, value: ddcValue)
            displayDDCLog.notice(
                "Write DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) code \(vcp.rawValue, privacy: .public) value \(ddcValue, privacy: .public) success \(success, privacy: .public)"
            )
            if success {
                controlCodes[key] = vcp
                registry.recordWriteSuccess(key)
                return true
            }
        }

        registry.recordWriteFailure(key)
        return false
    }

    private func orderedCandidates(for key: ControlKey) -> [DDCVCPCode] {
        let candidates = DDCVCPCode.candidates(for: key.control)
        guard let preferred = controlCodes[key], candidates.contains(preferred) else {
            return candidates
        }
        return [preferred] + candidates.filter { $0 != preferred }
    }
}

private enum DDCVCPCode: UInt8 {
    case luminance = 0x10
    case contrast = 0x12
    case backlightControlLegacy = 0x13
    case audioSpeakerVolume = 0x62
    case audioMuteScreenBlank = 0x8D

    static func candidates(for control: DisplayControlKind) -> [DDCVCPCode] {
        switch control {
        case .brightness:
            [.luminance, .backlightControlLegacy]
        case .contrast:
            [.contrast]
        case .volume:
            [.audioSpeakerVolume]
        }
    }
}

private enum DDCTransport {
    private static let sevenBitAddress: UInt8 = 0x37
    private static let dataAddress: UInt8 = 0x51

    static func read(service: IOAVService, vcpCode: UInt8, longerDelay: Bool = false, maxRetries: Int = 5) -> (current: UInt16, max: UInt16)? {
        var send = [vcpCode]
        var reply = [UInt8](repeating: 0, count: 11)
        guard communicate(service: service, send: &send, reply: &reply, longerDelay: longerDelay, maxRetries: maxRetries) else {
            return nil
        }
        let maxValue = (UInt16(reply[6]) << 8) + UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) + UInt16(reply[9])
        return (currentValue, maxValue)
    }

    static func write(service: IOAVService, vcpCode: UInt8, value: UInt16, maxRetries: Int = 5) -> Bool {
        var send = [vcpCode, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        return communicate(service: service, send: &send, reply: &reply, maxRetries: maxRetries)
    }

    private static func communicate(service: IOAVService, send: inout [UInt8], reply: inout [UInt8], longerDelay: Bool = false, maxRetries: Int = 5) -> Bool {
        // IOAVServiceReadI2C 是阻塞内核调用,异常时(热插拔/唤醒)可能长时间不返回。
        // 派到 serial ioQueue 执行 + semaphore 超时保护,避免拖死调用方的 hagimi.ddc.global 队列连累 UI。
        // 超时后开启熔断(circuit breaker):冷却期内直接 fast-fail,不再往可能已被 hang 任务
        // 占死的 ioQueue 派活,把"后续每次调用都白等到超时"降为"每个冷却周期仅探测一次"。
        if circuitIsOpen() {
            return false
        }

        // escaping 闭包不能捕获 inout,故拷贝 send/reply 后异步、完成回写(报文仅十几字节)。
        var sendCopy = send
        var replyCopy = reply
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        Self.ioQueue.async {
            result = communicateUnlocked(
                service: service,
                send: &sendCopy,
                reply: &replyCopy,
                longerDelay: longerDelay,
                maxRetries: maxRetries
            )
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + Self.communicateTimeout) == .timedOut {
            tripCircuit()
            displayDDCLog.error("DDC communicate timed out after \(Self.communicateTimeoutSeconds, privacy: .public)s; circuit opened for \(Self.circuitCooldownSeconds, privacy: .public)s to avoid queue starvation")
            return false
        }
        resetCircuit()
        send = sendCopy
        reply = replyCopy
        return result
    }

    // MARK: - Circuit Breaker

    private static let circuitLock = NSLock()
    private nonisolated(unsafe) static var circuitOpenUntil: DispatchTime?

    /// 熔断冷却时长。> communicateTimeout,确保上一个 hang 任务大概率已退出再放行探测。
    private static let circuitCooldownSeconds: Int = 10

    private static func circuitIsOpen() -> Bool {
        circuitLock.lock()
        defer { circuitLock.unlock() }
        guard let until = circuitOpenUntil else { return false }
        if DispatchTime.now() >= until {
            circuitOpenUntil = nil
            return false
        }
        return true
    }

    private static func tripCircuit() {
        circuitLock.lock()
        circuitOpenUntil = .now() + .seconds(circuitCooldownSeconds)
        circuitLock.unlock()
    }

    private static func resetCircuit() {
        circuitLock.lock()
        circuitOpenUntil = nil
        circuitLock.unlock()
    }

    /// 专用 serial I/O 队列,保证一次只跑一个 I/O(被遗弃的超时 I/O 不会与下次并发)。
    private static let ioQueue = DispatchQueue(label: "hagimi.ddc.io")

    /// 超时熔断阈值。覆盖正常最坏情况(多 VCP 候选码 × maxRetries ≈ 0.95s)留足余量。
    private static let communicateTimeoutSeconds: Int = 3
    private static var communicateTimeout: DispatchTimeInterval { .seconds(communicateTimeoutSeconds) }

    private static func communicateUnlocked(service: IOAVService, send: inout [UInt8], reply: inout [UInt8], longerDelay: Bool, maxRetries: Int) -> Bool {
        let dataAddress = Self.dataAddress
        var success = false
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let checksumSeed = send.count == 1
            ? Self.sevenBitAddress << 1
            : Self.sevenBitAddress << 1 ^ dataAddress
        packet[packet.count - 1] = checksum(seed: checksumSeed, data: packet, start: 0, end: packet.count - 2)

        for _ in 0..<maxRetries {
            for _ in 0..<2 {
                usleep(10_000)
                let packetCount = UInt32(packet.count)
                success = packet.withUnsafeMutableBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return false
                    }
                    return IOAVServiceWriteI2C(
                        service,
                        UInt32(Self.sevenBitAddress),
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
                usleep(longerDelay ? 150_000 : 50_000)
                let replyCount = UInt32(reply.count)
                success = reply.withUnsafeMutableBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return false
                    }
                    return IOAVServiceReadI2C(
                        service,
                        UInt32(Self.sevenBitAddress),
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
                    matchScore: score
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
                    "Matched DDC service display \(candidate.displayID, privacy: .public) location \(candidate.serviceLocation, privacy: .public) score \(candidate.matchScore, privacy: .public)"
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
}

private struct RegistryService {
    var edidUUID = ""
    var productName = ""
    var serialNumber: Int64 = 0
    var ioDisplayLocation = ""
    var service: IOAVService?
    var serviceLocation = 0
}
