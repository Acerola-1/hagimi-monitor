import Foundation
import Testing
@testable import HagimiMonitorDirect

struct PowerChannelTests {
    @Test func mapsFullM3M4IDsAndRejectsUnknownPlatforms() {
        let m3 = CLPCPowerChannels.reports(bundle: "com.apple.driver.AppleT8122CLPC", majorVersion: 27)
        #expect(m3?.map(\.id) == [0x0000001054b51c99, 0x00000018960afe2f])
        let m3Pro = CLPCPowerChannels.reports(bundle: "com.apple.driver.AppleT6030CLPC", majorVersion: 27)
        #expect(m3Pro?.first?.id == 0x00000010be03a01a)
        #expect(CLPCPowerChannels.reports(bundle: "com.apple.driver.AppleT6031CLPC", majorVersion: 27)?.first?.id == 0x00000010d81e0084)
        #expect(CLPCPowerChannels.reports(bundle: "com.apple.driver.AppleT8132CLPC", majorVersion: 27)?.map(\.id) == [0x000000104a854d94, 0x000000181ff4a9ec])
        #expect(CLPCPowerChannels.reports(bundle: "com.apple.driver.Unknown", majorVersion: 27) == nil)
        #expect(CLPCPowerChannels.reports(bundle: "com.apple.driver.AppleT8132CLPC", majorVersion: 28) == nil)
    }

    @Test func returnedIdentityAndEveryRequiredRailMustMatch() {
        let cpu = PowerChannelDescriptor(driver: 8, channel: 0x104a854d94, name: "CPU Energy", format: 1, unit: CLPCPowerChannels.nanojoules)
        let ane = PowerChannelDescriptor(driver: 8, channel: 0x181ff4a9ec, name: "ANE", format: 1, unit: CLPCPowerChannels.nanojoules)
        let a = PowerChannelRecord(descriptor: cpu, value: 100, timestamp: 1000)
        let b = PowerChannelRecord(descriptor: ane, value: 200, timestamp: 1000)
        let expected: Set = [cpu, ane]
        let good = PowerChannelSnapshot(expected: expected, records: [b, a], generation: 1)
        #expect(good.counters(named: { _ in true })?.count == 2)
        #expect(PowerChannelSnapshot(expected: expected, records: [a], generation: 1).counters(named: { _ in true }) == nil)
        // 独立 CPU 通道仍可读取；每个必需 rail 分别校验。
        #expect(PowerChannelSnapshot(expected: expected, records: [a], generation: 1).counters(named: { $0 == "CPU Energy" })?.count == 1)
        let alias = PowerChannelDescriptor(driver: 8, channel: 0x194a854d94, name: "CPU Energy", format: 1, unit: CLPCPowerChannels.nanojoules)
        #expect(PowerChannelSnapshot(expected: [cpu], records: [.init(descriptor: alias, value: 100, timestamp: 1000)], generation: 1)
            .counters(named: { _ in true }) == nil)
        let wrongUnit = PowerChannelDescriptor(driver: 8, channel: cpu.channel, name: cpu.name, format: 1, unit: 0x0300007c00000000)
        #expect(PowerChannelSnapshot(expected: [cpu], records: [.init(descriptor: wrongUnit, value: 100, timestamp: 1000)], generation: 1)
            .counters(named: { _ in true }) == nil)
        let wrongDriver = PowerChannelDescriptor(driver: 9, channel: cpu.channel, name: cpu.name, format: 1, unit: cpu.unit)
        #expect(PowerChannelSnapshot(expected: [cpu], records: [.init(descriptor: wrongDriver, value: 100, timestamp: 1000)], generation: 1)
            .counters(named: { _ in true }) == nil)
    }

    @Test func rawHeaderMismatchCannotMasqueradeAsUntimedCLPC() {
        let descriptor = PowerChannelDescriptor(driver: 8, channel: 20, name: "CPU Energy", format: 1, unit: CLPCPowerChannels.nanojoules)
        func bytes(driver: UInt64 = 8, channel: UInt64 = 20, timestamp: UInt64 = 0) -> Data {
            var data = Data()
            for word in [driver, channel, UInt64(1), timestamp, UInt64(100), 0, 0, 0] {
                withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
            }
            return data
        }
        #expect(PowerChannelRecord.decode(descriptor: descriptor, bytes: bytes(), value: 100, clock: 2000)?.timestamp == 0)
        #expect(PowerChannelRecord.decode(descriptor: descriptor, bytes: bytes(driver: 9), value: 100, clock: 2000) == nil)
        #expect(PowerChannelRecord.decode(descriptor: descriptor, bytes: bytes(channel: 21), value: 100, clock: 2000) == nil)
        #expect(PowerChannelRecord.decode(descriptor: descriptor, bytes: bytes(timestamp: 3000), value: 100, clock: 2000) == nil)
        #expect(PowerChannelRecord.decode(descriptor: descriptor, bytes: Data(), value: 100, clock: 2000) == nil)
    }
}
