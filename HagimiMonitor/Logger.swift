import Foundation
import OSLog

enum AppLogger {
    static let sampler = Logger(subsystem: "com.acerola.hagimi-monitor", category: "Sampler")
    static let ui = Logger(subsystem: "com.acerola.hagimi-monitor", category: "UI")
    static let settings = Logger(subsystem: "com.acerola.hagimi-monitor", category: "Settings")
}
