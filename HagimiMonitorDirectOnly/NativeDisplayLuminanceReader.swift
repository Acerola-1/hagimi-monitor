import CoreFoundation
import CoreGraphics
import Foundation
import ObjectiveC
import os

/// 仅按需读取系统报告的面板亮度。调用与实例生命周期均由同一串行队列管理。
private nonisolated final class CoreBrightnessLuminanceClient: @unchecked Sendable {
    private typealias CopyProperty = @convention(c) (NSObject, Selector, NSString, UInt64) -> Unmanaged<NSDictionary>?
    private static let propertySelector = NSSelectorFromString("copyPropertyForKey:andDisplay:")
    private let copyProperty: CopyProperty
    private let client: NSObject

    init?() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard let framework = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              let initializer = class_getInstanceMethod(type, NSSelectorFromString("init")),
              let initEncoding = method_getTypeEncoding(initializer), String(cString: initEncoding) == "@16@0:8",
              let method = class_getInstanceMethod(type, Self.propertySelector),
              let encoding = method_getTypeEncoding(method), String(cString: encoding) == "@32@0:8@16Q24" else {
            dlclose(framework)
            return nil
        }
        // 客户端与框架句柄一起保留至进程退出，避免在 Objective-C 实例存活时卸载框架。
        copyProperty = unsafeBitCast(method_getImplementation(method), to: CopyProperty.self)
        client = type.init()
    }

    func luminance(on displayID: CGDirectDisplayID) -> Double? {
        guard let status = copyProperty(client, Self.propertySelector, "StatusInfo", UInt64(displayID))?.takeRetainedValue(),
              let display = status["Display"] as? NSDictionary,
              let identity = display["CBDisplayInfo"] as? NSDictionary,
              let reportedID = identity["CBDisplayInfoDisplayID"] as? NSNumber,
              reportedID.doubleValue == Double(displayID),
              let nits = display["NitsPhysical"] as? NSNumber,
              CFGetTypeID(nits) != CFBooleanGetTypeID(), (0...10_000).contains(nits.doubleValue) else { return nil }
        return nits.doubleValue
    }
}

nonisolated enum NativeDisplayLuminanceReader {
    private static let queue = DispatchQueue(label: "HagimiMonitor.DisplayLuminance", qos: .utility)
    private static let readInFlight = OSAllocatedUnfairLock(initialState: false)
    private static let client = CoreBrightnessLuminanceClient()
    private static let brightness = DisplayServicesBridge()

    static func read(displayID: CGDirectDisplayID, expectedPercent: Double) async -> Double? {
        guard readInFlight.withLock({ inFlight in
            guard !inFlight else { return false }
            inFlight = true
            return true
        }) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let nits: Double?
                if let level = brightness.getBrightness(displayID: displayID),
                   abs(Double(level) * 100 - expectedPercent) <= 1 {
                    nits = client?.luminance(on: displayID)
                } else {
                    nits = nil
                }
                readInFlight.withLock { $0 = false }
                continuation.resume(returning: nits)
            }
        }
    }
}
