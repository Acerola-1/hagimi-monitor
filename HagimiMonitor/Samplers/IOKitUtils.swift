import Foundation
import IOKit
import OSLog

func registryDictionaryValue(_ service: io_service_t, _ key: String) -> [String: Any]? {
    let result = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
    guard let value = result?.takeRetainedValue() else {
        AppLogger.sampler.error("IORegistryEntryCreateCFProperty failed for key: \(key, privacy: .public)")
        return nil
    }
    guard let dict = value as? [String: Any] else {
        AppLogger.sampler.error("IORegistryEntryCreateCFProperty returned non-dictionary for key: \(key, privacy: .public)")
        return nil
    }
    return dict
}

func registryStringValue(_ service: io_service_t, _ key: String) -> String? {
    guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
        AppLogger.sampler.debug("IORegistryEntryCreateCFProperty returned nil for key: \(key, privacy: .public)")
        return nil
    }
    if let string = value as? String {
        return string
    }
    if let data = value as? Data {
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }
    return nil
}
