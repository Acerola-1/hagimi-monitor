import AppKit
import Foundation
import SwiftUI

/// 报表专用的应用图标与符号提供者。
/// 直接解码 PNG 数据并在窗口打开期间缓存，避免在 SwiftUI 视图重绘中重复解码，
/// 关窗时调用 `clear()` 立即释放所有图标位图。
@MainActor
final class ReportIconProvider {
    static let shared = ReportIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 128
    }

    /// 获取指定应用图标。优先从内存缓存中取，未命中则通过 `Data` 解码。
    func icon(forAppKey key: String, data: Data?) -> NSImage? {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        guard let data, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: nsKey)
        return image
    }

    /// 根据进程名或 Bundle ID 获取对齐 MonitorKind / 系统契约的兜底 SF Symbol (R13)
    func fallbackSymbol(forAppKey key: String) -> String {
        let lower = key.lowercased()
        if lower.contains("windowserver") {
            return "display"
        }
        if lower.hasPrefix("com.apple.") || lower.contains("daemon") || lower.contains("helper") || !lower.contains(".") {
            return "terminal"
        }
        return "app.fill"
    }

    /// 清空图标缓存，供报表关窗时释放。
    func clear() {
        cache.removeAllObjects()
    }
}
