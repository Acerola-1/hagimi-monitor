import AppKit
import SwiftUI

// 独立预览只提供编译所需的类型，不连接监控源；视觉直接使用正式调色板与常量。
enum MonitorColorSchemePreference { case balanced, vibrant }
enum MonitorSeverity { case calm, warning, critical }
enum MonitorKind { case cpu, gpu, memory, storage, network, battery, fan, bluetooth }
enum MenuBarComputeLoadLevel {
    case placeholder
    func coreColor(darkMode: Bool) -> NSColor { .controlAccentColor }
}
