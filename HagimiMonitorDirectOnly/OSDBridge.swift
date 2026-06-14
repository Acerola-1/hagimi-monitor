import CoreGraphics
import Foundation
import OSLog

private let osdLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "OSD")

enum OSDImage: Int64 {
    case brightness = 1
    case speaker = 3
    case speakerMuted = 4
}

final class OSDBridge {
    private static let osdManagerClass: AnyClass? = NSClassFromString("OSDManager")

    func show(
        _ image: OSDImage,
        displayID: CGDirectDisplayID,
        percent: Double,
        totalChiclets: Int = 100
    ) {
        guard let cls = Self.osdManagerClass as? NSObject.Type,
              let manager = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue()
        else {
            osdLog.warning("OSDManager class unavailable")
            return
        }

        let filled = max(0, min(totalChiclets, Int((percent / 100.0 * Double(totalChiclets)).rounded())))

        if let typedManager = manager as? OSDManager {
            typedManager.showImage(
                image.rawValue,
                onDisplayID: displayID,
                priority: 0x1F4,
                msecUntilFade: 1000,
                filledChiclets: UInt32(filled),
                totalChiclets: UInt32(totalChiclets),
                locked: false
            )
        }
    }
}
