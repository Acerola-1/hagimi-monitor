#if DEBUG
import AppKit

/// 显式指定输出路径的验收副本记录自有窗口事件；普通启动不写文件、不安装轮询。
@MainActor
enum PanelUXAcceptanceProbe {
    static func record(_ event: String, visible: Bool? = nil, pinned: Bool? = nil) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "HagimiPanelUXAcceptanceLog") as? String else { return }
        var entry: [String: Any] = ["event": event, "time": Date().timeIntervalSince1970]
        if let visible { entry["visible"] = visible }
        if let pinned { entry["pinned"] = pinned }
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch { }
    }
}
#endif
