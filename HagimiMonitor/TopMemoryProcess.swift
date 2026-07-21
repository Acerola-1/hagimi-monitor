import AppKit
import Darwin
import Foundation
import os

struct TopMemoryProcess: Identifiable, Equatable {
    /// 归属进程的 pid(responsible pid)。同一 App 的多个子进程合并后,以宿主进程 pid 为准。
    let pid: pid_t
    let name: String
    /// 进程真实内存占用(phys_footprint),与活动监视器"内存"列口径一致。
    /// 合并后为该 App 全部子进程的内存总和。
    let memoryUsage: UInt64
    /// App 图标。命令行进程或取不到时为 nil,视图侧回退到占位图标。
    let icon: NSImage?

    var id: pid_t { pid }

    // icon 不参与判等:NSImage 非 Equatable,且每次刷新都是新引用;若纳入判等会让
    // SwiftUI 每个周期都认为整行变化而无谓重绘。同 pid、同名、同内存即视为同一行。
    static func == (lhs: TopMemoryProcess, rhs: TopMemoryProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.memoryUsage == rhs.memoryUsage
    }
}

/// 系统进程的可执行文件所在路径前缀。匹配这些前缀的视为系统进程,
/// 在用户关闭"显示系统进程"时过滤掉。参考活动监视器的进程分类。
let systemProcessPathPrefixes: [String] = [
    "/System/",
    "/usr/",
    "/sbin/",
    "/bin/",
    "/private/",
    "/Library/Apple/",
    "/Library/Filesystems/",
]

/// 系统目录下但仍应始终显示的 App(按可执行文件路径片段匹配)。
/// 有意为之的特例:目前仅 Safari。它是用户主动使用的浏览器,网页(WebContent)内存
/// 常占大头,但宿主进程在 /System/ 下会被系统进程规则误杀,导致网页内存完全不计入排名。
/// 此处刻意只放行 Safari,而非用 activationPolicy 放行所有 .regular App——否则 Finder、
/// SystemUIServer 等系统自带 GUI 也会涌入列表,这不符合产品意图(它们仍应受"显示系统
/// 进程"开关控制)。新增白名单需求时在此追加路径片段即可。
let alwaysVisibleSystemAppMarkers: [String] = [
    "/Safari.app/Contents/MacOS/",
]

/// `responsibility_get_pid_responsible_for_pid` 的 C 函数签名。
/// 该 libsystem 私有 API 返回某进程的"负责进程"pid——即 Safari 的 WebContent、
/// Chrome 的 Helper 等子进程真正归属的宿主 App。活动监视器用它做进程分组。
typealias ResponsiblePidFunction = @convention(c) (Int32) -> Int32

/// 进程 -> 负责进程 pid 的解析器。dlsym 拿不到符号时回退为「返回自身」,
/// 退化成不合并的行为,保证功能不崩。
let responsiblePidResolver: ResponsiblePidFunction = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
    else {
        AppLogger.ui.error("responsibility_get_pid_responsible_for_pid 不可用,进程合并将退化为不合并")
        return { $0 }
    }
    return unsafeBitCast(symbol, to: ResponsiblePidFunction.self)
}()

/// 读取进程可执行文件路径。失败返回空串。
func executablePath(for pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
    return length > 0 ? String(cString: buffer) : ""
}

/// 读取进程 phys_footprint(真实物理内存占用,含压缩/置换),口径对齐活动监视器。
/// 失败返回 nil。proc_taskinfo 没有该字段,需用 proc_pid_rusage。
private func physFootprint(for pid: pid_t) -> UInt64? {
    var rusage = rusage_info_current()
    let result = withUnsafeMutablePointer(to: &rusage) { structPtr -> Int32 in
        structPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPtr in
            proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rawPtr)
        }
    }
    guard result == 0 else { return nil }
    return rusage.ri_phys_footprint
}

/// 一个归属分组的累加器:以负责进程(宿主 App)为单位汇总内存。
/// hostPath 在首次遇到该分组时(宿主进程尚存活)即捕获并缓存——若等累加结束后再读,
/// 宿主可能已退出导致路径为空,整组数据被误判为系统进程而丢失。
private struct ProcessGroup {
    let responsiblePid: pid_t
    let hostPath: String
    var totalMemory: UInt64 = 0
}

/// 后台采样阶段的中间结果:只含纯 syscall 能拿到的信息(pid/路径/路径名/内存)。
/// 不含图标和本地化名——那些依赖 NSWorkspace,须在主线程 enrich(见 enrich(_:))。
struct RawMemoryProcess {
    let pid: pid_t
    let path: String
    /// 路径末尾组件做的兜底名,主线程会尝试用本地化名覆盖。
    let fallbackName: String
    let memoryUsage: UInt64
}

/// 【后台线程安全】采样内存占用最高的 N 个进程(按宿主 App 合并),仅用 syscall。
/// 不触碰 NSWorkspace,可安全在后台队列调用;图标/本地化名由主线程 enrich(_:) 补齐。
/// - Parameters:
///   - limit: 返回的分组数量上限
///   - includeSystemProcesses: 是否包含系统进程(kernel_task、守护进程等)。
///     默认 false——大多数用户关心的是第三方 App 的内存占用。开启后与活动监视器口径一致。
///
/// 合并逻辑:用 `responsibility_get_pid_responsible_for_pid` 把每个进程归到其宿主 App。
/// Safari 的 WebContent、Chrome 的 Helper 等子进程的 ppid 是 launchd(1),无法靠父子链
/// 归属,但 responsible pid 能正确指向宿主 App。各分组内 phys_footprint 求和,即该 App
/// 的总内存占用,与活动监视器分组口径一致。
func sampleTopMemoryProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawMemoryProcess] {
    // 枚举全部 pid。proc_listallpids 的两个参数语义不对称,是历史踩坑点:
    //   - 第二个参数 buffersize 要的是「字节数」,必须 = 个数 × sizeof(pid_t);
    //   - 但返回值是「写入的 pid 个数」,不是字节数,不能再除以 sizeof(pid_t)。
    // 早期版本把个数当字节数传给 buffersize,缓冲区只够装 1/4 进程,后面的 pid 被
    // 静默截断——这正是大内存进程(如 IDEA)偶尔不显示的根因。
    // 传 nil 返回当前进程数(瞬时值,会波动),两次调用间可能有新进程,故留一倍余量。
    let estimatedCount = proc_listallpids(nil, 0)
    guard estimatedCount > 0 else { return [] }

    let capacity = Int(estimatedCount) * 2
    var pids = [pid_t](repeating: 0, count: capacity)
    let bufferSizeInBytes = Int32(capacity * MemoryLayout<pid_t>.size)
    let pidCount = Int(proc_listallpids(&pids, bufferSizeInBytes))
    guard pidCount > 0 else { return [] }

    // responsiblePid -> 累加分组
    var groups: [pid_t: ProcessGroup] = [:]
    groups.reserveCapacity(pidCount)

    // pidCount 理论上不会超过 capacity,但 proc_listallpids 在极端竞态下可能返回偏大值,
    // 取 min 防越界。
    for i in 0..<min(pidCount, capacity) {
        let pid = pids[i]
        guard pid > 0 else { continue }

        // 该进程的内存。读不到(进程已退出/无权限)就跳过。
        guard let memory = physFootprint(for: pid) else { continue }

        // 归属到宿主 App。responsible pid 即分组键。
        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid

        if groups[groupKey] == nil {
            // 首次见到该宿主:此刻它必然存活,立即捕获路径,避免后续退出导致整组丢失。
            groups[groupKey] = ProcessGroup(responsiblePid: groupKey, hostPath: executablePath(for: groupKey))
        }
        groups[groupKey]?.totalMemory += memory
    }

    // 按系统进程规则过滤,生成中间结果。
    var result: [RawMemoryProcess] = []
    result.reserveCapacity(groups.count)

    for (_, group) in groups {
        let hostPath = group.hostPath

        // 系统进程过滤:以宿主进程路径为准。
        // 路径为空通常是内核级进程(如 kernel_task),也归为系统进程。
        // Safari 等白名单 App 虽在系统目录下,但始终显示(否则网页内存无法计入)。
        if !includeSystemProcesses {
            let isAlwaysVisible = alwaysVisibleSystemAppMarkers.contains { hostPath.contains($0) }
            let isSystem = hostPath.isEmpty || systemProcessPathPrefixes.contains { hostPath.hasPrefix($0) }
            if !isAlwaysVisible, isSystem {
                continue
            }
        }

        // 兜底名:路径末尾组件;路径为空(白名单系统进程才会走到这)回退到 pid。
        let fallbackName = hostPath.isEmpty ? "pid \(group.responsiblePid)" : (hostPath as NSString).lastPathComponent
        guard !fallbackName.isEmpty else { continue }

        result.append(RawMemoryProcess(
            pid: group.responsiblePid,
            path: hostPath,
            fallbackName: fallbackName,
            memoryUsage: group.totalMemory
        ))
    }

    return Array(result.sorted { $0.memoryUsage > $1.memoryUsage }.prefix(limit))
}

/// 用 NSRunningApplication(pid:) 为采样结果补齐本地化名与 App 图标。
/// 可在任意线程调用,不依赖 NSWorkspace.shared.runningApplications 遍历。
func enrich(_ rawProcesses: [RawMemoryProcess]) -> [TopMemoryProcess] {
    return rawProcesses.map { raw in
        let app = NSRunningApplication(processIdentifier: pid_t(raw.pid))

        // 本地化名优先(如"谷歌浏览器"),否则用路径兜底名。
        let name: String
        if let localized = app?.localizedName, !localized.isEmpty {
            name = localized
        } else {
            name = raw.fallbackName
        }

        // 图标:走共享的降采样缓存,产出固定 16pt 小位图,避免持有大图 rep。
        let icon = ProcessIconCache.icon(forPID: pid_t(raw.pid), path: raw.path)

        return TopMemoryProcess(pid: raw.pid, name: name, memoryUsage: raw.memoryUsage, icon: icon)
    }
}
