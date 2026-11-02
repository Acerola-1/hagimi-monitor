import Darwin
import Foundation

/// 从 container-runtime-linux 的启动参数取出容器 ID。
/// `--uuid` 优先；没有时用 `--root` 的最后一段。两者都没有则返回空串。
/// 不返回根目录全路径，避免把用户目录露进行名。
nonisolated func containerIdentifier(in arguments: [String]) -> String {
    if let uuid = argumentValue(in: arguments, names: ["--uuid", "-u"]),
       !uuid.isEmpty, !uuid.hasPrefix("-") {
        return uuid
    }
    if let root = argumentValue(in: arguments, names: ["--root", "-r"]), !root.isEmpty {
        let name = (root as NSString).lastPathComponent
        if !name.isEmpty, name != "/", !name.hasPrefix("-") {
            return name
        }
    }
    return ""
}

/// 仅当可执行文件是 container-runtime-linux 时用容器 ID 替换兜底名。
/// 参数缺失或读不到 ID 时保留兜底名。输入几行就返回几行，不另造合计行。
nonisolated func containerRowLabel(path: String, arguments: [String]?, fallbackName: String) -> String {
    guard (path as NSString).lastPathComponent == "container-runtime-linux" else { return fallbackName }
    guard let arguments else { return fallbackName }
    let identifier = containerIdentifier(in: arguments)
    return identifier.isEmpty ? fallbackName : identifier
}

/// TOP 榜展示名。普通进程仍是本地化名，其次是可执行文件名。
/// Direct 上已经进入展示结果的 container-runtime-linux 行改用容器 ID；
/// App Store 不读取其他进程的参数。
nonisolated func topProcessDisplayName(
    pid: pid_t,
    path: String,
    fallbackName: String,
    localizedName: String?
) -> String {
    let ordinary = (localizedName?.isEmpty == false) ? localizedName! : fallbackName
    #if DIRECT_DISTRIBUTION
    if (path as NSString).lastPathComponent == "container-runtime-linux" {
        return containerRowLabel(
            path: path,
            arguments: processArguments(for: pid),
            fallbackName: fallbackName
        )
    }
    #endif
    return ordinary
}

private nonisolated func argumentValue(in arguments: [String], names: [String]) -> String? {
    let nameSet = Set(names)
    for (index, argument) in arguments.enumerated() {
        if nameSet.contains(argument) {
            guard index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        for name in names where argument.hasPrefix(name + "=") {
            return String(argument.dropFirst(name.count + 1))
        }
    }
    return nil
}

#if DIRECT_DISTRIBUTION
/// 读取进程启动参数。只给已经要显示的 container runtime 调用，不扫全表。
/// KERN_PROCARGS2 的布局是 argc、可执行路径、填充的 NUL，然后才是 argv。
nonisolated func processArguments(for pid: pid_t) -> [String]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
    if buffer.count > size {
        buffer.removeLast(buffer.count - size)
    }
    return parseKERNProcArgs2(buffer)
}

nonisolated func parseKERNProcArgs2(_ buffer: [UInt8]) -> [String]? {
    guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
    let argc = buffer.withUnsafeBytes { raw in
        raw.loadUnaligned(as: Int32.self)
    }
    guard argc > 0, argc < 4096 else { return nil }

    var index = MemoryLayout<Int32>.size
    while index < buffer.count, buffer[index] != 0 { index += 1 }
    while index < buffer.count, buffer[index] == 0 { index += 1 }

    var arguments: [String] = []
    arguments.reserveCapacity(Int(argc))
    for _ in 0..<argc {
        guard index < buffer.count else { break }
        let start = index
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        let bytes = buffer[start..<index]
        if let argument = String(bytes: bytes, encoding: .utf8) {
            arguments.append(argument)
        }
        index += 1
    }
    return arguments
}
#endif
