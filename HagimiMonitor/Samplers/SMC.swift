import Foundation
import IOKit

final class SMCReader {
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
        case "flt ":
            // byteArray 是 [UInt8](仅 1 字节对齐),load(as: Float.self) 假定 4 字节对齐属未定义
            // 行为;用 loadUnaligned 从任意偏移安全读取。
            let floatValue: Float = byteArray.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Float.self) }
            return Double(floatValue)
        default:
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
