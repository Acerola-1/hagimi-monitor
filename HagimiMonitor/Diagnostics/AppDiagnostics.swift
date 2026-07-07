import Foundation
import OSLog

// MARK: - Diagnostics Support

enum DiagnosticsDirectories {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("HagimiMonitor", isDirectory: true)
    }
}

extension JSONEncoder {
    static var hagimiDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var hagimiDiagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - App Log Store

final class AppLogStore {
    enum Level: String {
        case info
        case warning
        case error
    }

    static let shared = AppLogStore()

    private let logsDirectory: URL
    private let currentLogURL: URL
    private let rotatedLogURL: URL
    private let maxFileSize: UInt64
    private let dateProvider: () -> Date
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.app-log")
    private let formatter: ISO8601DateFormatter

    init(
        baseDirectory: URL? = nil,
        maxFileSize: UInt64 = 1_048_576,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        let root = baseDirectory ?? DiagnosticsDirectories.applicationSupport
        self.logsDirectory = root.appendingPathComponent("Logs", isDirectory: true)
        self.currentLogURL = logsDirectory.appendingPathComponent("app.log")
        self.rotatedLogURL = logsDirectory.appendingPathComponent("app.1.log")
        self.maxFileSize = maxFileSize
        self.dateProvider = dateProvider
        self.formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createLogsDirectoryIfNeeded()
    }

    func info(_ message: String, category: String) {
        write(level: .info, category: category, message: message)
    }

    func warning(_ message: String, category: String) {
        write(level: .warning, category: category, message: message)
    }

    func error(_ message: String, category: String) {
        write(level: .error, category: category, message: message)
    }

    func flush() {
        queue.sync {}
    }

    func logFileURLs() -> [URL] {
        flush()
        return [currentLogURL, rotatedLogURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func write(level: Level, category: String, message: String) {
        let timestamp = formatter.string(from: dateProvider())
        let normalizedMessage = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(normalizedMessage)\n"

        queue.async { [currentLogURL, logsDirectory, maxFileSize, rotatedLogURL] in
            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                try AppLogStore.rotateIfNeeded(currentLogURL: currentLogURL, rotatedLogURL: rotatedLogURL, maxFileSize: maxFileSize)
                if FileManager.default.fileExists(atPath: currentLogURL.path) {
                    let handle = try FileHandle(forWritingTo: currentLogURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: currentLogURL, atomically: true, encoding: .utf8)
                }
            } catch {
                // Logging must never affect app behavior.
            }
        }
    }

    private func createLogsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private static func rotateIfNeeded(currentLogURL: URL, rotatedLogURL: URL, maxFileSize: UInt64) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: currentLogURL.path),
              let size = attributes[.size] as? UInt64,
              size >= maxFileSize else {
            return
        }

        if FileManager.default.fileExists(atPath: rotatedLogURL.path) {
            try FileManager.default.removeItem(at: rotatedLogURL)
        }
        try FileManager.default.moveItem(at: currentLogURL, to: rotatedLogURL)
    }
}

// MARK: - Crash Handler

/// Global log file path, set once at launch.
/// Must be a plain global so the signal/exception handlers (C function pointers) can access it.
private var _crashLogPathCString: [CChar] = []
private var _crashLogPath: String = ""

/// C function for signal handling — no Swift context capture allowed.
///
/// Critical: this handler MUST NOT return normally for trap-style signals (SIGTRAP/SIGILL/SIGFPE
/// on arm64 are raised by a `brk`/trap instruction that does not advance past itself). If we just
/// log and return, the CPU resumes at the very same faulting instruction and re-raises the same
/// signal immediately — an infinite retrap loop that pegs the CPU and freezes the main thread
/// forever without ever actually crashing (observed in the wild: millions of repeated log lines,
/// UI completely unresponsive, yet the process never dies). So after logging, restore the default
/// disposition and re-raise: this lets the OS actually terminate the process, which is far better
/// than a silent, unkillable hang.
private func handleSignal(_ sig: Int32) {
    defer {
        signal(sig, SIG_DFL)
        raise(sig)
    }

    guard !_crashLogPathCString.isEmpty else { return }

    let sigName: String
    switch sig {
    case SIGABRT: sigName = "SIGABRT"
    case SIGSEGV: sigName = "SIGSEGV"
    case SIGBUS:  sigName = "SIGBUS"
    case SIGILL:  sigName = "SIGILL"
    case SIGFPE:  sigName = "SIGFPE"
    case SIGTERM: sigName = "SIGTERM"
    case SIGTRAP: sigName = "SIGTRAP"
    default:      sigName = "UNKNOWN"
    }

    let prefix = "FATAL [crash] Caught signal: "
    let suffix = "\n"

    _crashLogPathCString.withUnsafeBufferPointer { pathBuf in
        guard let pathPtr = pathBuf.baseAddress else { return }
        let fd = open(pathPtr, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        _ = prefix.withCString { write(fd, $0, strlen($0)) }
        _ = sigName.withCString { write(fd, $0, strlen($0)) }
        _ = suffix.withCString { write(fd, $0, strlen($0)) }
        close(fd)
    }
}

/// Captures fatal signals and uncaught exceptions so that the crash reason
/// appears in `app.log` even when `willTerminate` is never called.
///
/// Signal handlers are constrained to async-signal-safe calls only,
/// so we bypass `AppLogStore` and write directly via POSIX `write(2)`.
enum CrashHandler {
    static let logPath: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("HagimiMonitor/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log").path
    }()

    /// Install signal + exception handlers. Call once at app launch.
    static func install() {
        // Cache the log path in globals so C function pointer handlers can access it.
        _crashLogPath = logPath
        _crashLogPathCString = logPath.cString(using: .utf8) ?? []
        installSignalHandlers()
        installExceptionHandler()
    }

    // MARK: - Signal Handlers

    private static let caughtSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTERM, SIGTRAP]

    private static func installSignalHandlers() {
        for sig in caughtSignals {
            _ = signal(sig, handleSignal)
        }
    }

    // MARK: - Uncaught Exception Handler

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "no reason"
            let message = "FATAL [crash] Uncaught exception: \(name) — \(reason)\n"

            // This handler runs on the throwing thread before the process dies.
            // AppLogStore's async write may not flush in time, so write directly.
            // Use the global path since C function pointers cannot capture context.
            if let data = message.data(using: .utf8) {
                if let handle = FileHandle(forWritingAtPath: _crashLogPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: URL(fileURLWithPath: _crashLogPath), options: .atomic)
                }
            }
        }
    }
}

// MARK: - Launch State

struct AppLaunchState: Codable {
    var launchID: String
    var launchDate: Date
    var lastCleanExitDate: Date?
    var previousRunEndedUnexpectedly: Bool
}

final class AppLaunchStateTracker {
    static let shared = AppLaunchStateTracker()

    private let stateURL: URL
    private let dateProvider: () -> Date
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.launch-state")
    private var currentState: AppLaunchState?

    init(baseDirectory: URL? = nil, dateProvider: @escaping () -> Date = Date.init) {
        let root = baseDirectory ?? DiagnosticsDirectories.applicationSupport
        self.stateURL = root.appendingPathComponent("run-state.json")
        self.dateProvider = dateProvider
    }

    @discardableResult
    func markLaunch() -> Bool {
        queue.sync {
            let previous = loadState()
            let previousUnexpected = previous.map { $0.lastCleanExitDate == nil } ?? false
            let state = AppLaunchState(
                launchID: UUID().uuidString,
                launchDate: dateProvider(),
                lastCleanExitDate: nil,
                previousRunEndedUnexpectedly: previousUnexpected
            )
            currentState = state
            saveState(state)
            return previousUnexpected
        }
    }

    func markCleanExit() {
        queue.sync {
            var state = currentState ?? loadState() ?? AppLaunchState(
                launchID: UUID().uuidString,
                launchDate: dateProvider(),
                lastCleanExitDate: nil,
                previousRunEndedUnexpectedly: false
            )
            state.lastCleanExitDate = dateProvider()
            state.previousRunEndedUnexpectedly = false
            currentState = state
            saveState(state)
        }
    }

    func stateSnapshot() -> AppLaunchState? {
        queue.sync { currentState ?? loadState() }
    }

    func stateFileURL() -> URL? {
        queue.sync {
            FileManager.default.fileExists(atPath: stateURL.path) ? stateURL : nil
        }
    }

    private func loadState() -> AppLaunchState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder.hagimiDiagnostics.decode(AppLaunchState.self, from: data)
    }

    private func saveState(_ state: AppLaunchState) {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.hagimiDiagnostics.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // Diagnostics state must never affect app behavior.
        }
    }
}

// MARK: - Health Monitor

/// Periodically logs memory usage and main-thread responsiveness.
/// Helps diagnose SIGKILL kills that leave no crash handler output
/// (typically memory jetsam or watchdog timeout).
final class HealthMonitor {
    static let shared = HealthMonitor()

    private var timer: DispatchSourceTimer?
    private var pingTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.health", qos: .utility)
    private let interval: TimeInterval

    /// Main-thread liveness ping — written by the main thread, read by the monitor.
    /// Note: intentionally accessed from two queues without lock (diagnostic flag, race is harmless).
    private var mainThreadAlive: Bool = true

    init(interval: TimeInterval = 300) { // 5 minutes
        self.interval = interval
    }

    func start() {
        // Install a main-thread run-loop observer so we can detect hangs.
        installMainThreadPing()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        self.timer = timer
    }

    private func installMainThreadPing() {
        // A repeating timer on the main run loop proves the thread is alive.
        let ping = DispatchSource.makeTimerSource(queue: .main)
        ping.schedule(deadline: .now(), repeating: 60) // ping every 60s
        ping.setEventHandler { [weak self] in
            self?.mainThreadAlive = true
        }
        ping.resume()
        self.pingTimer = ping
    }

    private func checkHealth() {
        let memMB = currentMemoryMB()
        let alive = mainThreadAlive
        mainThreadAlive = false // reset; main thread has 60s to set it back

        let status = alive ? "ok" : "UNRESPONSIVE"
        AppLogStore.shared.info(
            "Health: memory=\(memMB)MB, mainThread=\(status)",
            category: "health"
        )

        if memMB > 500 {
            AppLogStore.shared.warning(
                "High memory usage: \(memMB)MB — risk of jetsam kill",
                category: "health"
            )
        }
    }

    private func currentMemoryMB() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int64(info.resident_size) / 1_048_576
    }
}

// MARK: - App Log Exporter

struct AppLogExporter {
    struct Configuration {
        var outputDirectory: URL
        var appLogStore: AppLogStore
        var launchStateTracker: AppLaunchStateTracker
        var dateProvider: () -> Date
        var compress: Bool

        static var `default`: Configuration {
            Configuration(
                outputDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("HagimiMonitor", isDirectory: true)
                    .appendingPathComponent("Diagnostics", isDirectory: true),
                appLogStore: .shared,
                launchStateTracker: .shared,
                dateProvider: Date.init,
                compress: true
            )
        }
    }

    private struct Metadata: Codable {
        let generatedAt: Date
        let appName: String
        let appVersion: String
        let buildNumber: String
        let bundleIdentifier: String
        let osVersion: String
        let architecture: String
        let locale: String
        let previousRunEndedUnexpectedly: Bool
    }

    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func export() throws -> URL {
        configuration.appLogStore.flush()

        let generatedAt = configuration.dateProvider()
        let folderName = "hagimi-monitor-diagnostics-\(timestampString(from: generatedAt))"
        let stagingRoot = configuration.outputDirectory
        let folderURL = stagingRoot.appendingPathComponent(folderName, isDirectory: true)
        let logsURL = folderURL.appendingPathComponent("logs", isDirectory: true)
        let stateURL = folderURL.appendingPathComponent("state", isDirectory: true)

        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        try writeReadme(to: folderURL.appendingPathComponent("README.txt"), generatedAt: generatedAt)
        try writeMetadata(to: folderURL.appendingPathComponent("metadata.json"), generatedAt: generatedAt)
        try copyAppLogs(to: logsURL)
        try copyLaunchState(to: stateURL)
        writeUnifiedLog(to: logsURL)

        guard configuration.compress else {
            return folderURL
        }

        let zipURL = stagingRoot.appendingPathComponent("\(folderName).zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        do {
            try createZip(from: folderURL, to: zipURL)
            return zipURL
        } catch {
            configuration.appLogStore.warning("Failed to create diagnostics zip: \(error.localizedDescription)", category: "diagnostics")
            return folderURL
        }
    }

    private func writeReadme(to url: URL, generatedAt: Date) throws {
        let text = """
        \(String(localized: "diagnostics.readme.title"))

        \(String(localized: "diagnostics.readme.description"))

        Generated At: \(ISO8601DateFormatter().string(from: generatedAt))

        \(String(localized: "diagnostics.readme.privacy"))

        \(String(localized: "diagnostics.readme.feedback"))
        https://github.com/Acerola-1/hagimi-monitor/issues
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMetadata(to url: URL, generatedAt: Date) throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let state = configuration.launchStateTracker.stateSnapshot()
        let metadata = Metadata(
            generatedAt: generatedAt,
            appName: (info["CFBundleName"] as? String) ?? "HagimiMonitor",
            appVersion: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
            buildNumber: (info["CFBundleVersion"] as? String) ?? "unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: DiagnosticsSystemInfo.architecture,
            locale: Locale.current.identifier,
            previousRunEndedUnexpectedly: state?.previousRunEndedUnexpectedly ?? false
        )
        let data = try JSONEncoder.hagimiDiagnostics.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private func copyAppLogs(to logsURL: URL) throws {
        for sourceURL in configuration.appLogStore.logFileURLs() {
            let destinationURL = logsURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func copyLaunchState(to stateDirectory: URL) throws {
        guard let sourceURL = configuration.launchStateTracker.stateFileURL() else { return }
        let destinationURL = stateDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func writeUnifiedLog(to logsURL: URL) {
        let destinationURL = logsURL.appendingPathComponent("unified.log")
        do {
            let text = try recentUnifiedLogText()
            try text.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            let fallbackURL = logsURL.appendingPathComponent("unified-log-unavailable.txt")
            let message = String(localized: "diagnostics.unified-log-unavailable")
                + "\n\n"
                + error.localizedDescription
            try? message.write(to: fallbackURL, atomically: true, encoding: .utf8)
        }
    }

    private func recentUnifiedLogText() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let startDate = configuration.dateProvider().addingTimeInterval(-24 * 60 * 60)
        let position = store.position(date: startDate)
        let predicate = NSPredicate(format: "subsystem == %@", "com.acerola.hagimi-monitor")
        let entries = try store.getEntries(at: position, matching: predicate)

        var lines: [String] = []
        for entry in entries.prefix(2_000) {
            guard let log = entry as? OSLogEntryLog else { continue }
            lines.append("\(ISO8601DateFormatter().string(from: log.date)) [\(log.category)] \(log.composedMessage)")
        }
        return lines.joined(separator: "\n")
    }

    private func createZip(from folderURL: URL, to zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            folderURL.path,
            zipURL.path
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private enum DiagnosticsSystemInfo {
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
