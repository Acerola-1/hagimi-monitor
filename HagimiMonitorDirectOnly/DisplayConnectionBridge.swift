import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit

/// 按需记录真实拔插期间的原始枚举，正常运行不产生诊断流量。
nonisolated enum DisplayConnectionDiagnostics {
    static func trace(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["HAGIMI_DISPLAY_CONNECTION_TRACE"] == "1" else { return }
        let line = "[DisplayConnection \(Date().timeIntervalSince1970)] \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

nonisolated enum DisplayConnectionCommand: Sendable {
    case enabled(DisplayConnectionIdentity, Bool)
    case mirror(DisplayConnectionIdentity, DisplayConnectionIdentity?)
}

nonisolated protocol DisplayConnectionBackend: Sendable {
    var isAvailable: Bool { get }
    /// 合盖时不做电源重建，避免在包里点亮内置屏。未知合盖状态仍允许救援。
    var lidAllowsRecovery: Bool { get }
    func screens() throws -> [DisplayConnectionScreen]
    func configure(_ commands: [DisplayConnectionCommand]) throws
    func rediscoverPhysicalDisplays() async -> Bool
    /// 仅接受本会话见过、且当前没有被另一台设备占用的编号。
    func forceEnableRemembered(_ ids: [CGDirectDisplayID])
}

nonisolated extension DisplayConnectionBackend {
    var lidAllowsRecovery: Bool { true }
    func rediscoverPhysicalDisplays() async -> Bool { false }
    func forceEnableRemembered(_ ids: [CGDirectDisplayID]) {}
}

nonisolated struct DisplayConnectionAPIError: Error, Sendable {
    var stage: String
    var code: Int32
}

/// 函数表在初始化后不变；实际调用由协调器的串行执行器承载。
nonisolated struct DisplayConnectionSystemAPI: @unchecked Sendable {
    typealias List = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    typealias Enable = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    var list: List?
    /// 生产路径包一层系统符号；测试可换成会捕获状态的普通闭包。
    var enable: ((CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError)?
    var begin: (inout CGDisplayConfigRef?) -> CGError = { CGBeginDisplayConfiguration(&$0) }
    var complete: (CGDisplayConfigRef) -> CGError = { CGCompleteDisplayConfiguration($0, .forSession) }
    var cancel: (CGDisplayConfigRef) -> CGError = { CGCancelDisplayConfiguration($0) }
    var mirror: (CGDisplayConfigRef, CGDirectDisplayID, CGDirectDisplayID) -> CGError = { CGConfigureDisplayMirrorOfDisplay($0, $1, $2) }

    /// 不卸载句柄：函数指针的有效期与应用一致。
    static let live: Self = {
        let handles = ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                       "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"].compactMap { path in
            path.withCString { dlopen($0, RTLD_LAZY) }
        }
        func symbol(_ names: [String]) -> UnsafeMutableRawPointer? {
            for name in names {
                for handle in handles {
                    if let pointer = name.withCString({ dlsym(handle, $0) }) { return pointer }
                }
            }
            return nil
        }
        return Self(list: symbol(["SLSGetDisplayList", "CGSGetDisplayList"]).map { unsafeBitCast($0, to: List.self) },
                    enable: symbol(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"]).map { pointer in
                        let function = unsafeBitCast(pointer, to: Enable.self)
                        return { function($0, $1, $2) }
                    })
    }()
}

nonisolated final class DisplayConnectionBridge: DisplayConnectionBackend, @unchecked Sendable {
    private let api: DisplayConnectionSystemAPI
    private let snapshotProvider: (@Sendable () throws -> [DisplayConnectionScreen])?
    private let rediscovery = DisplayConnectionRediscovery()

    init(api: DisplayConnectionSystemAPI = .live, snapshotProvider: (@Sendable () throws -> [DisplayConnectionScreen])? = nil) {
        self.api = api
        self.snapshotProvider = snapshotProvider
    }

    var isAvailable: Bool {
        #if arch(arm64)
        api.list != nil && api.enable != nil
        #else
        false
        #endif
    }

    var lidAllowsRecovery: Bool { Self.lidIsClosed() != true }

    func screens() throws -> [DisplayConnectionScreen] {
        if let snapshotProvider { return try snapshotProvider() }
        guard let list = api.list else { throw DisplayConnectionIssue.unavailable }
        let ids = try Self.enumerate(list)
        let lidClosed = Self.lidIsClosed()
        let screens = ids.compactMap { Self.screen($0, lidClosed: lidClosed) }
        DisplayConnectionDiagnostics.trace("enumerated=\(ids) lid=\(String(describing: lidClosed)) screens=\(screens)")
        return screens
    }

    func rediscoverPhysicalDisplays() async -> Bool {
        await rediscovery.recover { [self] in
            guard !DDCEnvironmentGate.shared.isSystemSleeping,
                  !DDCEnvironmentGate.shared.isShuttingDown, lidAllowsRecovery,
                  let current = try? screens() else { return false }
            return !current.contains(where: \.isUsable)
        }
    }

    func forceEnableRemembered(_ ids: [CGDirectDisplayID]) {
        var seen = Set<CGDirectDisplayID>()
        let unique = ids.filter { seen.insert($0).inserted }
        guard isAvailable, let enable = api.enable, !unique.isEmpty else { return }
        var config: CGDisplayConfigRef?
        let begin = api.begin(&config)
        guard begin == .success, let config else {
            DisplayConnectionDiagnostics.trace("force-enable begin failed \(begin.rawValue)")
            return
        }
        for id in unique {
            let code = enable(config, id, true)
            DisplayConnectionDiagnostics.trace("force-enable id=\(id) code=\(code.rawValue)")
        }
        // 拓扑异常时提交码经常是非法参数，屏幕却已经亮了；成败由随后的枚举确认。
        let complete = api.complete(config)
        DisplayConnectionDiagnostics.trace("force-enable complete code=\(complete.rawValue)")
    }

    static func enumerate(_ list: DisplayConnectionSystemAPI.List) throws -> [CGDirectDisplayID] {
        var capacity = 16
        while capacity <= 4096 {
            var ids = [CGDirectDisplayID](repeating: 0, count: capacity)
            var count: UInt32 = 0
            let error = list(UInt32(capacity), &ids, &count)
            guard error == .success else { throw DisplayConnectionAPIError(stage: "enumerate", code: error.rawValue) }
            if count < capacity {
                return Array(ids.prefix(Int(count)))
            }
            capacity *= 2
        }
        throw DisplayConnectionIssue.unconfirmed
    }

    func configure(_ commands: [DisplayConnectionCommand]) throws {
        guard isAvailable, let enable = api.enable else { throw DisplayConnectionIssue.unavailable }
        var topology = try screens()
        var operations: [(CGDisplayConfigRef) -> CGError] = []
        for command in commands {
            switch command {
            case let .enabled(identity, value):
                guard let screen = DisplayConnectionPolicy.resolve(identity, in: topology) else { throw DisplayConnectionIssue.ambiguous }
                if value == (screen.isOnline && screen.hasDesktop) { continue }
                if !value, !DisplayConnectionPolicy.canDisable(screen, in: topology) { throw DisplayConnectionIssue.lastScreen }
                operations.append { enable($0, screen.id, value) }
                if let i = topology.firstIndex(where: { $0.id == screen.id }) {
                    topology[i].isOnline = value
                    topology[i].hasDesktop = value
                }
            case let .mirror(identity, targetIdentity):
                guard let screen = DisplayConnectionPolicy.resolve(identity, in: topology) else { throw DisplayConnectionIssue.ambiguous }
                let target: CGDirectDisplayID
                if let targetIdentity {
                    guard let match = DisplayConnectionPolicy.resolve(targetIdentity, in: topology), match.isOnline else { throw DisplayConnectionIssue.waiting }
                    target = match.id
                } else { target = kCGNullDirectDisplay }
                if screen.mirrorTarget == (target == 0 ? nil : target) { continue }
                operations.append { self.api.mirror($0, screen.id, target) }
            }
        }
        guard !operations.isEmpty else { return }
        var config: CGDisplayConfigRef?
        let begin = api.begin(&config)
        guard begin == .success, let config else { throw DisplayConnectionAPIError(stage: "begin", code: begin.rawValue) }
        for operation in operations {
            let error = operation(config)
            guard error == .success else {
                _ = api.cancel(config)
                throw DisplayConnectionAPIError(stage: "configure", code: error.rawValue)
            }
        }
        let complete = api.complete(config)
        guard complete == .success else { throw DisplayConnectionAPIError(stage: "complete", code: complete.rawValue) }
    }

    private static func screen(_ id: CGDirectDisplayID, lidClosed: Bool?) -> DisplayConnectionScreen? {
        let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id)
        DisplayConnectionDiagnostics.trace("raw id=\(id) builtin=\(CGDisplayIsBuiltin(id)) vendor=\(vendor) model=\(model) serial=\(CGDisplaySerialNumber(id)) online=\(CGDisplayIsOnline(id)) active=\(CGDisplayIsActive(id))")
        guard vendor != 0 || model != 0 else { return nil }
        let info = CoreDisplay_DisplayCreateInfoDictionary(id)?.takeRetainedValue() as? [String: Any] ?? [:]
        DisplayConnectionDiagnostics.trace("info id=\(id) count=\(info.count)")
        let builtIn = CGDisplayIsBuiltin(id) == 1
        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        let name = names[Locale.current.identifier] ?? names["en_US"] ?? names.values.sorted().first
            ?? (builtIn ? String(localized: "display.built-in-display") : String(localized: "display.external-display"))
        let virtual = (info["kCGDisplayIsVirtualDevice"] as? Bool) == true || (info["kCGDisplayIsAirPlay"] as? Bool) == true
        let dummy = vendor == 0xF0F0 || names.values.contains { $0.lowercased().contains("dummy") }
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        let bounds = CGDisplayBounds(id)
        let target = CGDisplayMirrorsDisplay(id)
        return DisplayConnectionScreen(id: id,
            identity: .init(uuid: uuid, vendor: vendor, model: model, serial: CGDisplaySerialNumber(id), isBuiltIn: builtIn),
            name: name, isPhysical: !virtual && !dummy && !info.isEmpty,
            isOnline: CGDisplayIsOnline(id) == 1,
            hasDesktop: CGDisplayIsActive(id) == 1 || CGDisplayIsInMirrorSet(id) == 1,
            isVisible: !builtIn || lidClosed == false,
            mirrorTarget: target == 0 ? nil : target,
            bounds: .init(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height))
    }

    static func identity(for id: CGDirectDisplayID) -> DisplayConnectionIdentity {
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        return .init(uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                     serial: CGDisplaySerialNumber(id), isBuiltIn: CGDisplayIsBuiltin(id) == 1)
    }

    static func lidIsClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
