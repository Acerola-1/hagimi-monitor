import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Darwin

final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var lines = ["pts_seconds,status,display_time,content_rect"]
    var finished = false
    var failure: String?
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { print("recording-started") }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { lock.lock(); finished = true; lock.unlock() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { lock.lock(); failure = String(describing: error); finished = true; lock.unlock() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = array.first else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let status = info[.status] as? Int ?? -1
        let display = info[.displayTime] as? UInt64 ?? 0
        let rect = String(describing: info[.contentRect] ?? "").replacingOccurrences(of: ",", with: ";")
        lock.lock(); lines.append("\(pts),\(status),\(display),\"\(rect)\""); lock.unlock()
    }
    func result() -> (Bool, String?) { lock.lock(); defer { lock.unlock() }; return (finished, failure) }
    func save(_ url: URL) throws { lock.lock(); let data = lines.joined(separator: "\n"); lock.unlock(); try data.write(to: url, atomically: true, encoding: .utf8) }
}

@main
struct Capture {
    @MainActor static func main() async {
        do { try await record() }
        catch {
            FileHandle.standardError.write(Data(("capture-failed: \(error)\n").utf8))
            exit(1)
        }
    }
    @MainActor static func record() async throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count >= 4, let pid = Int32(args[1]), let duration = Double(args[3]), duration.isFinite, duration > 0, duration <= 120 else { fatalError("capture PID output.mp4 seconds") }
        guard CGPreflightScreenCaptureAccess() else { throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Screen capture permission unavailable; no permission changes requested"]) }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        var target: SCWindow?
        repeat {
            target = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width >= 300 }
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            if target != nil { break }
            try await Task.sleep(for: .milliseconds(250))
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } while ProcessInfo.processInfo.systemUptime < deadline
        guard let window = target else {
            throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Target panel not visible within 10 seconds"])
        }
        print("window=\(window.windowID) frame=\(window.frame) title=\(window.title ?? "") epoch=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime)")
        for screen in NSScreen.screens {
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let mode = CGDisplayCopyDisplayMode(displayID) {
                print("display=\(displayID) bounds=\(screen.frame) refresh-hz=\(mode.refreshRate)")
            }
        }
        guard let display = content.displays.first(where: { args.count > 4 ? $0.displayID == UInt32(args[4]) : CGDisplayIsBuiltin($0.displayID) != 0 }),
              CGDisplayBounds(display.displayID).contains(window.frame) else {
            throw NSError(domain: "Capture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Target is not wholly on the requested screen; capture refused"])
        }
        print("selected-display=\(display.displayID) cg-bounds=\(CGDisplayBounds(display.displayID)) sc-bounds=\(display.frame)")
        let bounds = CGDisplayBounds(display.displayID)
        let x = max(0, window.frame.minX - bounds.minX - 80)
        let y = max(0, window.frame.minY - bounds.minY - 30)
        let region = CGRect(x: x, y: y, width: min(window.frame.width + 160, bounds.width - x), height: bounds.height - y)
        print("static-display-region=\(region)")
        let config = SCStreamConfiguration()
        config.width = Int(region.width * 2)
        config.height = Int(region.height * 2)
        config.sourceRect = region
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.queueDepth = 5
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        let delegate = Recorder()
        let outputURL = URL(fileURLWithPath: args[2])
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = outputURL
        recordingConfig.videoCodecType = .h264
        recordingConfig.outputFileType = .mp4
        let recording = SCRecordingOutput(configuration: recordingConfig, delegate: delegate)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
        try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue(label: "performance.capture"))
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(duration))
        try await stream.stopCapture()
        for _ in 0..<40 {
            if delegate.result().0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try delegate.save(outputURL.deletingPathExtension().appendingPathExtension("frames.csv"))
        guard delegate.result().0 else {
            throw NSError(domain: "Capture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Recording completion was not confirmed"])
        }
        if let failure = delegate.result().1 { throw NSError(domain: "Capture", code: 3, userInfo: [NSLocalizedDescriptionKey: failure]) }
        print("recording-finished=\(delegate.result().0) file=\(outputURL.path)")
    }
}
