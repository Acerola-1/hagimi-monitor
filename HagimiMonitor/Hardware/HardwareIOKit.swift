import Foundation
import IOKit

/// IOKit 读取辅助:设备树与平台专家节点。
///
/// 硬件清单里有一部分信息既不在 sysctl 也不在 system_profiler 里——产品名、
/// 内存可升级、显示器镜像、Wi-Fi 芯片、蓝牙 LE Audio 能力在 `IODeviceTree:/product`;
/// 机型标识/序列号/硬件 UUID/地区/制造商在 `IOPlatformExpertDevice`。
///
/// 全部只读,不做任何写入。读不到一律返 nil。
enum HardwareIOKit {
    /// `IODeviceTree:/product` 下的一项(键名见 Apple 设备树约定)。
    static func productProperty(_ key: String) -> Any? {
        registryProperty(path: "IODeviceTree:/product", key: key)
    }

    /// 同名键在多个机型上类型不同(字符串/Data/整数),统一成字符串。
    static func productString(_ key: String) -> String? {
        stringValue(productProperty(key))
    }

    static func productBool(_ key: String) -> Bool? {
        guard let raw = productProperty(key) else { return nil }
        if let number = raw as? NSNumber { return number.intValue != 0 }
        if let text = raw as? String { return text == "yes" || text == "1" }
        return nil
    }

    /// 平台专家服务(`IOPlatformExpertDevice`)的属性。
    static func platformProperty(_ key: String) -> Any? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return property(of: service, key: key)
    }

    /// 神经网络引擎节点(Apple Silicon 才存在)。
    static func aneProperty(_ key: String) -> Any? {
        registryProperty(path: "IODeviceTree:/arm-io/ane", key: key)
    }

    /// 按 IORegistry 路径取属性。
    static func registryProperty(path: String, key: String) -> Any? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return property(of: entry, key: key)
    }

    private static func property(of entry: io_registry_entry_t, key: String) -> Any? {
        // 四参数版的 `IORegistryEntryCreateCFProperty` 直接返回 CFTypeRef(失败为 nil),
        // 不是 kern_return_t —— 别按返回值判错。
        guard let value = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value
    }

    /// CFTypeRef → 字符串。设备树里同一语义的字段在不同机型上可能是 String 或 Data。
    static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let text as String:
            return trim(text)
        case let data as Data:
            // 设备树的 Data 多为 C 串:末尾带 NUL 填充(如 product-name 长 32 字节),
            // 必须把 NUL 一并去掉,否则会带进一串不可见字符。
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return trim(text)
        case let number as NSNumber:
            // JSON/CF 的布尔要还原成是/否,否则会渲染成 "1" / "0"。
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "是" : "否"
            }
            return number.stringValue
        default:
            return nil
        }
    }

    private static func trim(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
