import Foundation

/// Apple 0x07 广播中的精确分部电量。只接收已知双耳型号的 29 字节格式，
/// 未验证的型号/格式不猜测；0xff 为缺失，充电位与真实 0% 分开处理。
nonisolated struct AirPodsAdvertisement: Equatable, Sendable {
    let identifier: UUID
    let name: String?
    let observedAt: TimeInterval
    let components: [BluetoothBatteryComponent]

    static let freshnessInterval: TimeInterval = 90

    static func decode(_ data: Data, identifier: UUID, name: String?, observedAt: TimeInterval, isDecrypted: Bool) -> Self? {
        let bytes = Array(data)
        guard isDecrypted, bytes.count == 29, Array(bytes.prefix(4)) == [0x4c, 0x00, 0x07, 0x19] else { return nil }
        let model = UInt16(bytes[5]) | UInt16(bytes[6]) << 8
        // AirPods 1/2/3、Pro/Pro 2；Max 等单体形态不使用双耳字段。
        guard [UInt16(0x2002), 0x200f, 0x2013, 0x200e, 0x2014].contains(model) else { return nil }
        let swapped = bytes[7] & 0x20 == 0
        let fields: [(BluetoothBatteryComponent.Kind, Int)] = [(.left, swapped ? 15 : 14), (.right, swapped ? 14 : 15), (.case, 16)]
        let components = fields.compactMap { kind, index -> BluetoothBatteryComponent? in
            let byte = bytes[index]
            let level = Int(byte & 0x7f)
            guard byte != 0xff, level <= 100 else { return nil }
            return BluetoothBatteryComponent(kind: kind, level: level, isCharging: byte & 0x80 != 0)
        }
        return Self(identifier: identifier, name: name, observedAt: observedAt, components: components)
    }
}
