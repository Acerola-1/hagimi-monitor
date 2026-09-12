import Foundation

/// sysctl 读取辅助。
///
/// 硬件清单要读一批只读的内核参数(`hw.*` / `machdep.cpu.*` / `kern.*`)。
/// 项目里原有三处各写各的 `sysctlbyname`(StatisticsReportBuilder / MemorySampler /
/// UsageReporter),这里抽一份共用的,新代码不再各写一套。
///
/// 语义:读不到一律返 nil,由调用方按「缺失」显示,不用 0 或默认值兜底。
enum HardwareSysctl {
    /// 字符串型(如 `machdep.cpu.brand_string` / `hw.model`)。
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 按 sysctl 自己报的宽度读取,归一成 Int64。
    ///
    /// **不能假定宽度**:实测 `hw.perflevel0.l2cachesize` 是 4 字节,而
    /// `hw.cachelinesize` / `hw.pagesize` / `hw.memsize` 是 8 字节——按固定宽度读
    /// 会因尺寸不符直接拿不到值(第一版就这么踩了,缓存整组为空)。
    ///
    /// 按无符号解释:本清单只读容量、核数、频率、0/1 开关这类非负量。
    static func number(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, (1...8).contains(size) else { return nil }
        var buffer = [UInt8](repeating: 0, count: 8)
        var readSize = size
        let status = buffer.withUnsafeMutableBytes { raw in
            sysctlbyname(name, raw.baseAddress, &readSize, nil, 0)
        }
        guard status == 0, readSize > 0 else { return nil }
        var value: UInt64 = 0
        for index in 0..<min(readSize, 8) {
            value |= UInt64(buffer[index]) << (8 * index)
        }
        return Int64(bitPattern: value)
    }

    /// 已知语义宽度的读取(核数用 Int32、容量用 UInt64 之类),宽度不符返 nil。
    static func integer<T: FixedWidthInteger>(_ name: String, as type: T.Type = T.self) -> T? {
        number(name).flatMap { T(exactly: $0) }
    }

    /// 0/1 开关。读不到返 nil(键不存在),与「关」区分开。
    static func isEnabled(_ name: String) -> Bool? {
        number(name).map { $0 == 1 }
    }

    /// 原始字节型(如 `kern.boottime` 的 timeval)。
    static func raw<T>(_ name: String, into value: inout T) -> Bool {
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0
    }

    /// 枚举某个前缀下的所有子键名(如 `hw.optional` → `hw.optional.arm.FEAT_SVE`)。
    /// 硬件清单要用它列指令集特性,不能用硬编码列表——机型之间差异很大。
    ///
    /// 注意:不能用 `sysctlbyname(prefix)` 读——那取的是值不是子键表。正确做法是
    /// 把前缀转成 MIB,再用 `[CTL_SYSCTL, CTL_SYSCTL_NEXT]` 逐个取下一个 OID、
    /// 用 `[CTL_SYSCTL, CTL_SYSCTL_NAME]` 把 OID 还原成名字,直到 OID 不再以该
    /// 前缀开头。上限 4096 只是防御性的(本机实测 hw.optional 下约 200 项)。
    static func names(under prefix: String) -> [String] {
        var mib = [Int32](repeating: 0, count: 32)
        var mibLength = mib.count
        guard sysctlnametomib(prefix, &mib, &mibLength) == 0, mibLength > 0 else { return [] }
        let root = Array(mib[0..<mibLength])
        var names: [String] = []
        var current = root
        while names.count < 4096 {
            var query = [Int32(0), Int32(2)] + current
            var next = [Int32](repeating: 0, count: 32)
            var nextSize = next.count * MemoryLayout<Int32>.size
            let status = query.withUnsafeMutableBufferPointer { buffer in
                sysctl(buffer.baseAddress, UInt32(buffer.count), &next, &nextSize, nil, 0)
            }
            guard status == 0 else { break }
            let oid = Array(next[0..<(nextSize / MemoryLayout<Int32>.size)])
            guard oid.count > root.count, Array(oid[0..<root.count]) == root else { break }

            var nameQuery = [Int32(0), Int32(1)] + oid
            var nameBuffer = [CChar](repeating: 0, count: 256)
            var nameSize = nameBuffer.count
            let named = nameQuery.withUnsafeMutableBufferPointer { buffer in
                sysctl(buffer.baseAddress, UInt32(buffer.count), &nameBuffer, &nameSize, nil, 0)
            }
            if named == 0 { names.append(String(cString: nameBuffer)) }
            current = oid
        }
        return names
    }

    /// 字节数的可读化,**十进制**(厂商口径):磁盘/卷容量、网络流量用它。
    static func describeBytes(_ bytes: UInt64?) -> String? {
        guard let bytes else { return nil }
        return describe(Double(bytes), base: 1000, units: ["B", "KB", "MB", "GB", "TB", "PB"])
    }

    /// 字节数的可读化,**1024 进制**:缓存、页大小、内存容量用它。
    ///
    /// 两套并存是有意的:macOS 自己就混用——内存写「32 GB」(=1024³),磁盘写
    /// 「1 TB」(=1000⁴)。全用十进制会把 16 KB 的页显示成「16.4 KB」,看起来像算错了。
    static func describeBinaryBytes(_ bytes: UInt64?) -> String? {
        guard let bytes else { return nil }
        return describe(Double(bytes), base: 1024, units: ["B", "KB", "MB", "GB", "TB", "PB"])
    }

    private static func describe(_ value: Double, base: Double, units: [String]) -> String {
        var scaled = value
        var index = 0
        while scaled >= base, index < units.count - 1 {
            scaled /= base
            index += 1
        }
        // 整数就写整数:「16 KB」比「16.0 KB」干净;非整数保留一位。
        let rounded = scaled.rounded()
        let text = abs(rounded - scaled) < 0.05 ? String(Int(rounded)) : String(format: "%.1f", scaled)
        return "\(text) \(units[index])"
    }

    /// 计数器的千分位(与报表一致用空格分组,不跟随语言环境)。
    static func group(_ value: Int) -> String {
        String(value).replacingOccurrences(
            of: #"\B(?=(\d{3})+(?!\d))"#, with: " ", options: .regularExpression)
    }

    /// 频率/字节这类「带单位的整数」统一走这里,保证同一份清单里格式一致。
    static func describeFrequency(_ hertz: Int64?) -> String? {
        guard let hertz else { return nil }
        if hertz >= 1_000_000 {
            return String(format: "%.0f MHz", Double(hertz) / 1_000_000)
        }
        if hertz >= 1_000 {
            return "\(group(Int(hertz / 1_000))) kHz"
        }
        return "\(group(Int(hertz))) Hz"
    }
}
