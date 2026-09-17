import CoreGraphics
import Foundation

nonisolated enum DisplayKind: Equatable, Sendable {
    case builtIn
    case appleNative
    case externalDDC
    case virtual
    case dummy
    case unsupported
}

nonisolated struct DisplayClassifier: Sendable {
    let probeNativeBrightness: @Sendable (CGDirectDisplayID) -> Bool

    init(probeNativeBrightness: @escaping @Sendable (CGDirectDisplayID) -> Bool = DisplayClassifier.defaultProbe) {
        self.probeNativeBrightness = probeNativeBrightness
    }

    func classify(displayID: CGDirectDisplayID) -> DisplayKind {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return .builtIn
        }

        let info = CoreDisplay_DisplayCreateInfoDictionary(displayID)?
            .takeRetainedValue() as? [String: Any] ?? [:]

        if (info["kCGDisplayIsVirtualDevice"] as? Bool) == true ||
           (info["kCGDisplayIsAirPlay"] as? Bool) == true {
            return .virtual
        }

        if isDummy(info: info) {
            return .dummy
        }

        if probeNativeBrightness(displayID) {
            return .appleNative
        }

        return .externalDDC
    }

    private func isDummy(info: [String: Any]) -> Bool {
        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        if names.values.contains(where: { $0.lowercased().contains("dummy") }) {
            return true
        }
        if let vendor = info["DisplayVendorID"] as? Int64, vendor == 0xF0F0 {
            return true
        }
        return false
    }

    nonisolated static func defaultProbe(_ id: CGDirectDisplayID) -> Bool {
        var brightness: Float = -1
        let result = DisplayServicesGetBrightness(id, &brightness)
        return result == 0 && brightness >= 0
    }
}
