import Foundation
import IOKit

final class SMCReader: FanSMCReading {
    private var conn: io_connect_t = 0
    private static let temperatureKeys = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"
    ]

    init?() {
        var iterator: io_iterator_t = 0
        let matchingDictionary = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)
        guard result == kIOReturnSuccess else { return nil }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return nil }

        let openResult = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        guard openResult == kIOReturnSuccess else { return nil }
    }

    deinit {
        _ = IOServiceClose(conn)
    }

    func cpuTemperature() -> Double? {
        var temperatures: [Double] = []
        for key in Self.temperatureKeys {
            if let value = readValue(key) {
                temperatures.append(value)
            }
        }
        guard !temperatures.isEmpty else { return nil }
        return temperatures.reduce(0, +) / Double(temperatures.count)
    }

    /// 读取 SMC key `PSTR`（整机系统总负载，flt 类型，单位 W）。读取失败返回 nil。
    func systemPower() -> Double? {
        readValue("PSTR")
    }

    /// 读取 SMC key `PDTR`（DC 输入轨功率，flt 类型，单位 W）。
    func dcInputPower() -> Double? {
        readValue("PDTR")
    }

    /// 读取 SMC key `FNum`,返回机器物理风扇数。无风扇机型或读取失败时返回 nil。
    /// FNum 是机器静态属性,启动时读一次缓存即可,无需每次采样都读。
    func fanCount() -> Int? {
        guard let raw = readValue("FNum") else { return nil }
        let count = Int(raw)
        return count > 0 ? count : nil
    }

    /// 读取所有风扇的当前 RPM,返回最大 RPM。任一风扇读取失败跳过(不抛错);
    /// 全 0 或全失败时返回 nil,UI 应降级为 unavailable 占位。
    func maxFanRPM() -> Int? {
        guard let count = fanCount() else { return nil }
        var maxRPM = 0
        for i in 0..<count {
            let key = "F\(i)Ac"
            if let raw = readValue(key) {
                let rpm = Int(raw)
                if rpm > maxRPM { maxRPM = rpm }
            }
        }
        return maxRPM > 0 ? maxRPM : nil
    }

    /// 读取所有风扇的当前 RPM 与 min/max 范围(供面板展开用)。
    /// 任一字段失败用 0 占位;返回数组长度 = fanCount。
    func allFans() -> [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)] {
        guard let count = fanCount() else { return [] }
        var result: [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)] = []
        for i in 0..<count {
            let current = Int(readValue("F\(i)Ac") ?? 0)
            let min = Int(readValue("F\(i)Mn") ?? 0)
            let max = Int(readValue("F\(i)Mx") ?? 0)
            result.append((id: i, currentRPM: current, minRPM: min, maxRPM: max))
        }
        return result
    }

    private func readValue(_ key: String) -> Double? {
        guard conn != 0 else { return nil }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        input.key = fourCharCode(key)
        input.data8 = 9 // readKeyInfo

        var result = call(2, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType

        input.data8 = 5 // readBytes
        input.keyInfo.dataSize = dataSize
        result = call(2, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return nil }

        return parseValue(bytes: output.bytes, dataSize: dataSize, dataType: dataType)
    }

    private func parseValue(bytes: SMCKeyData_t.SMCBytes_t, dataSize: IOByteCount32, dataType: UInt32) -> Double? {
        guard dataSize > 0 else { return nil }

        let byteArray = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5,
                         bytes.6, bytes.7, bytes.8, bytes.9, bytes.10, bytes.11,
                         bytes.12, bytes.13, bytes.14, bytes.15, bytes.16, bytes.17,
                         bytes.18, bytes.19, bytes.20, bytes.21, bytes.22, bytes.23,
                         bytes.24, bytes.25, bytes.26, bytes.27, bytes.28, bytes.29,
                         bytes.30, bytes.31]

        if byteArray.first(where: { $0 != 0 }) == nil {
            return nil
        }

        let typeString = fourCharCodeToString(dataType)

        switch typeString {
        case "sp78":
            let intValue = Int(byteArray[0]) * 256 + Int(byteArray[1])
            return Double(intValue) / 256.0
        case "sp87":
            let intValue = Int(byteArray[0]) * 256 + Int(byteArray[1])
            return Double(intValue) / 128.0
        case "sp96":
            let intValue = Int(byteArray[0]) * 256 + Int(byteArray[1])
            return Double(intValue) / 64.0
        case "ui16 ":
            return Double(UInt16(byteArray[0]) * 256 + UInt16(byteArray[1]))
        case "ui8 ":
            // 无符号 8-bit 单字节整数。FNum(风扇数)即此类型,dataSize=1。
            return Double(byteArray[0])
        case "ui32":
            // #KEY(键总数)是此类型。硬件清单要靠它做全量枚举。
            return Double(UInt32(byteArray[0]) << 24 | UInt32(byteArray[1]) << 16
                | UInt32(byteArray[2]) << 8 | UInt32(byteArray[3]))
        case "flt ":
            // byteArray 是 [UInt8](仅 1 字节对齐),load(as: Float.self) 假定 4 字节对齐属未定义
            // 行为;用 loadUnaligned 从任意偏移安全读取。
            let floatValue: Float = byteArray.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Float.self) }
            return Double(floatValue)
        case "ioft":
            // `ioft` **不是 IEEE float**,是 16.16 定点数(小端 u32 ÷ 65536)。
            // 当成 float 读会得到 1e-39 量级的垃圾,再被硬件清单的 1–130 ℃ 门限滤掉——
            // 本机实测 12 个键(TG0B/TG0C/TG0H/TG0V/TG1B/TG2B/TR0Z/TR1d/TR2d/TR3d/TR4d/TR5d)
            // 就是这样整组静默丢失的;按定点解读得到 36–52 ℃ 的合理温度。
            let raw = UInt32(byteArray[0]) | UInt32(byteArray[1]) << 8
                | UInt32(byteArray[2]) << 16 | UInt32(byteArray[3]) << 24
            return Double(raw) / 65536.0
        default:
            // 其余类型(如 `si32`)不解码。本机实测两个 si32 键(TVDi/TVVi)读数为 13 与 0,
            // 不是温度量级、也猜不出确定语义——宁可判为「读不出」由上层显示缺失,
            // 也不要硬套一个可能错的公式。将来确认语义再补分支。
            return nil
        }
    }

    private func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        str.utf8.reduce(0) { sum, character in
            sum << 8 | UInt32(character)
        }
    }

    private func fourCharCodeToString(_ code: UInt32) -> String {
        String(describing: UnicodeScalar(code >> 24 & 0xff)!) +
        String(describing: UnicodeScalar(code >> 16 & 0xff)!) +
        String(describing: UnicodeScalar(code >> 8 & 0xff)!) +
        String(describing: UnicodeScalar(code & 0xff)!)
    }
}

// MARK: - 全量温度枚举(硬件清单用)

extension SMCReader {
    /// 一个可读的温度键。`key` 是 SMC 的四字符键名,原样保留——
    /// 它既是稳定标识(不同机型的键集合不同,不能硬编码列表),也是详情里要展示的内容。
    struct TemperatureReading {
        let key: String
        let celsius: Double
    }

    /// 温度域。语义分组沿用既有认知(CPU P/E 核、GPU 集群、机身……),
    /// 未归类的键统一进 `other`,由展示层折叠成「N 个 · 最热 X ℃」而不是铺满一栏
    /// ——本机实测 187 个可读温度键里有 67 个落在未归类(TPD*/TD*/TRD* 等新机型键)。
    ///
    /// 域名不内嵌在枚举里:`nameKey` 指向报表文案键(`stats.r.<key>`),
    /// 由展示层经 `hwText` 解析——枚举保持纯语义。
    enum TemperatureDomain: CaseIterable {
        case cpuPerformance, cpuEfficiency, gpuCluster, storage, battery
        case airflow, chassis, wireless, voltageRail, other

        var nameKey: String {
            switch self {
            case .cpuPerformance: return "hwDomainCpuPerformance"
            case .cpuEfficiency: return "hwDomainCpuEfficiency"
            case .gpuCluster: return "hwDomainGpuCluster"
            case .storage: return "hwDomainStorage"
            case .battery: return "hwDomainBattery"
            case .airflow: return "hwDomainAirflow"
            case .chassis: return "hwDomainChassis"
            case .wireless: return "hwDomainWireless"
            case .voltageRail: return "hwDomainVoltageRail"
            case .other: return "hwDomainOther"
            }
        }

        /// 按 SMC 键前缀归类。实测前缀与域的对应见硬件数据源文档。
        static func of(_ key: String) -> TemperatureDomain {
            let two = String(key.prefix(2))
            let three = String(key.prefix(3))
            switch two {
            case "Tp": return .cpuPerformance
            case "Te": return .cpuEfficiency
            case "Tg": return .gpuCluster
            case "TB": return .battery
            case "TW": return .wireless
            case "TV": return .voltageRail
            case "Ts", "Th": return .chassis
            case "Ta": return three == "Ta0" ? .other : .airflow
            case "TH": return .storage
            default: return .other
            }
        }
    }

    /// 枚举 `#KEY` 全量键,取 4 字符且以 `T` 开头、读数落在 1–130 ℃ 的键,按域分组。
    ///
    /// 一次全量扫描在本机约 2800 个键上耗时可控(<1s),但**不是每秒做的事**——
    /// 硬件清单只在打开报表/手动刷新时采集一次。
    func temperatureInventory() -> [(domain: TemperatureDomain, readings: [TemperatureReading])] {
        guard let rawCount = readValue("#KEY") else { return [] }
        let count = Int(rawCount)
        guard count > 0 else { return [] }

        var byDomain: [TemperatureDomain: [TemperatureReading]] = [:]
        for index in 0..<count {
            guard let key = keyAt(index), key.count == 4, key.hasPrefix("T") else { continue }
            guard let value = readValue(key), value >= 1, value <= 130 else { continue }
            byDomain[TemperatureDomain.of(key), default: []].append(
                TemperatureReading(key: key, celsius: value))
        }
        // 输出顺序按枚举声明固定,保证同一台机器每次采集的域顺序一致。
        return TemperatureDomain.allCases.compactMap { domain in
            guard let readings = byDomain[domain], !readings.isEmpty else { return nil }
            return (domain, readings.sorted { $0.celsius > $1.celsius })
        }
    }

    /// 枚举 `#KEY` 里的第 `index` 个键名。SMC 的键表接口:
    /// `data8 = 8` 是「按键序号取键名」,`data8 = 9` 是「按键名取键信息」。
    func keyAt(_ index: Int) -> String? {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.data8 = 8
        input.data32 = UInt32(index)
        guard call(2, input: &input, output: &output) == kIOReturnSuccess, output.key != 0 else {
            return nil
        }
        return fourCharCodeToString(output.key)
    }
}

private struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = (major: CUnsignedChar(0), minor: CUnsignedChar(0), build: CUnsignedChar(0), reserved: CUnsignedChar(0), release: CUnsignedShort(0))
    var pLimitData = (version: UInt16(0), length: UInt16(0), cpuPLimit: UInt32(0), gpuPLimit: UInt32(0), memPLimit: UInt32(0))
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}
