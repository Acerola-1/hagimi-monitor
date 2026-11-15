/*
MIT License

Copyright (c) 2024 vladkens

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
import Foundation

// 映射来源：https://github.com/vladkens/macmon/blob/87c6686b048c97f665d31bc58277845c4f7822c4/src/clpc.rs
// 请求限定在匹配的系统大版本与驱动；实际返回和动态准入分别校验。
nonisolated enum CLPCPowerChannels {
    static let referenceRevision = "87c6686b048c97f665d31bc58277845c4f7822c4"
    static let nanojoules: UInt64 = 0x0300007600000000
    struct Report: Equatable, Sendable {
        let name: String
        let id: UInt64
    }
    static func reports(bundle: String, majorVersion: Int) -> [Report]? {
        guard majorVersion == 27, let keys = keys[bundle] else { return nil }
        return [Report(name: "CPU Energy", id: (16 << 32) | UInt64(keys.cpu)),
                Report(name: "ANE", id: (24 << 32) | UInt64(keys.ane))]
    }

    /// 描述符构造与平台门控共用同一入口；M3 实机依据见 docs/power-topology-m3-macos27.md。
    static func descriptors(bundle: String, majorVersion: Int, driverID: UInt64) -> [NSDictionary] {
        guard let reports = reports(bundle: bundle, majorVersion: majorVersion) else { return [] }
        return reports.compactMap { report in
            let dictionary: NSDictionary = [
                "DriverID": NSNumber(value: driverID), "DriverName": "AppleCLPC",
                "IOReportGroupName": "CLPC", "IOReportSubGroupName": "Energy Counters",
                "IOReportChannelInfo": ["IOReportChannelUnit": NSNumber(value: nanojoules)],
                "LegendChannel": [NSNumber(value: report.id), NSNumber(value: UInt64(1 | (2 << 16) | (1 << 32))), report.name]
            ]
            // IOReport getters 会缓存派生字段，传入可变 CF 字典。
            return CFDictionaryCreateMutableCopy(nil, 0, dictionary as CFDictionary).map { $0 as NSDictionary }
        }
    }

    private static let keys: [String: (cpu: UInt32, ane: UInt32)] = [
        "com.apple.driver.AppleT6000CLPCv3": (cpu: 0x4747_9059, ane: 0x9aaa_17f8),
        "com.apple.driver.AppleT6002CLPC": (cpu: 0xb501_816b, ane: 0x14d5_a574),
        "com.apple.driver.AppleT6020CLPC": (cpu: 0xe301_cd75, ane: 0x7415_fb0f),
        "com.apple.driver.AppleT6022CLPC": (cpu: 0x76f5_fd21, ane: 0x3c09_7307),
        "com.apple.driver.AppleT6030CLPC": (cpu: 0xbe03_a01a, ane: 0xb899_0c38),
        "com.apple.driver.AppleT6031CLPC": (cpu: 0xd81e_0084, ane: 0x313a_3be1),
        "com.apple.driver.AppleT6032CLPC": (cpu: 0xf4a2_1308, ane: 0x63dc_8e25),
        "com.apple.driver.AppleT6041CLPC": (cpu: 0x263c_f1f0, ane: 0x7849_fb5c),
        "com.apple.driver.AppleT6050CLPC": (cpu: 0xd3ab_60bb, ane: 0x8c0f_1c59),
        "com.apple.driver.AppleT6050dCLPC": (cpu: 0x18b3_010e, ane: 0x188b_d883),
        "com.apple.driver.AppleT8103CLPCv3": (cpu: 0x2cdd_31f2, ane: 0x0667_fb81),
        "com.apple.driver.AppleT8112CLPC": (cpu: 0xb543_5137, ane: 0xea08_9c36),
        "com.apple.driver.AppleT8122CLPC": (cpu: 0x54b5_1c99, ane: 0x960a_fe2f),
        "com.apple.driver.AppleT8132CLPC": (cpu: 0x4a85_4d94, ane: 0x1ff4_a9ec),
        "com.apple.driver.AppleT8140CLPC": (cpu: 0x9bf5_4436, ane: 0x569d_941b),
        "com.apple.driver.AppleT8142CLPC": (cpu: 0x4370_8744, ane: 0xbc5e_fdf0),
        "com.apple.driver.AppleT8152CLPC": (cpu: 0x485d_4bfc, ane: 0x9380_c6bb),
    ]
}
