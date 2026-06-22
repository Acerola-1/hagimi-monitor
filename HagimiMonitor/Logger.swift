import Foundation
import OSLog

enum AppLogger {
    static let subsystem = "com.acerola.hagimi-monitor"

    static let sampler = Logger(subsystem: subsystem, category: "Sampler")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")
}
