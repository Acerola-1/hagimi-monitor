import AppKit
import Darwin
import IOKit

// 累计 CPU 计数的差分由采集脚本计算；失败的跨进程读数保留 status，不记为零。
let arguments = CommandLine.arguments.dropFirst()
let pids = arguments.compactMap(Int32.init)
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
var records: [[String: Any]] = []
for pid in pids {
    var usage = rusage_info_current()
    let status = withUnsafeMutablePointer(to: &usage) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
        }
    }
    var row: [String: Any] = ["pid": pid, "status": status]
    if status == 0 {
        row["user_ticks"] = usage.ri_user_time
        row["system_ticks"] = usage.ri_system_time
        row["resident_bytes"] = usage.ri_resident_size
        row["footprint_bytes"] = usage.ri_phys_footprint
        row["process_start"] = usage.ri_proc_start_abstime
    }
    records.append(row)
}
var accelerators: [[String: Any]] = []
var iterator: io_iterator_t = 0
if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        if let value = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
            accelerators.append(value.filter { $0.key.contains("Utilization") })
        }
    }
}
let screens: [[String: Any]] = NSScreen.screens.compactMap { screen in
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
          let mode = CGDisplayCopyDisplayMode(id) else { return nil }
    return ["id": id, "builtin": CGDisplayIsBuiltin(id) != 0,
        "bounds": NSStringFromRect(CGDisplayBounds(id)), "visible_frame": NSStringFromRect(screen.visibleFrame),
        "width": mode.width, "height": mode.height, "pixel_width": mode.pixelWidth,
        "pixel_height": mode.pixelHeight, "refresh_hz": mode.refreshRate,
        "scale": screen.backingScaleFactor]
}
var cpu = host_cpu_load_info()
var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
let host = mach_host_self()
let cpuStatus = withUnsafeMutablePointer(to: &cpu) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
    }
}
mach_port_deallocate(mach_task_self_, host)
let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
let result: [String: Any] = ["epoch": Date().timeIntervalSince1970,
    "uptime": ProcessInfo.processInfo.systemUptime, "processes": records,
    "gpu": accelerators, "screens": screens,
    "screen_capture_permission": CGPreflightScreenCaptureAccess(),
    "system_cpu_status": cpuStatus, "system_cpu_ticks": ticks,
    "timebase_numer": timebase.numer, "timebase_denom": timebase.denom,
    "active_processors": ProcessInfo.processInfo.activeProcessorCount]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
