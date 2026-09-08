import Foundation

/// DDC/CI 协议帧解析(6.2)。
///
/// 完整校验帧结构(长度/校验和/opcode/回显 VCP/resultCode),坏帧返回结构化错误;
/// "不支持"(resultCode 0x01)、"坏帧"、"无应答"明确区分,瞬时丢包不会升级为能力禁用;
/// 保留完整 MH/ML/SH/SL raw 值,再按控制属性解释。
nonisolated enum DDCProtocol {
    /// Get VCP Feature Reply 的标准长度(含源地址与校验和)。
    static let replyLength = 11

    /// 结构化帧校验结果。
    nonisolated enum FrameResult: Equatable {
        /// 结构有效,字段就绪。
        case valid(Reply)
        /// 结构损坏(长度/校验和/opcode/回显任一不符)。
        case malformed(reason: MalformedReason)
        /// 无有效应答(未收到或读取失败)。
        case noResponse
    }

    /// 坏帧的具体原因,用于诊断。
    nonisolated enum MalformedReason: Equatable {
        case badLength(actual: Int)
        case badChecksum
        case badOpcode(actual: UInt8)
        case vcpEchoMismatch(requested: UInt8, echoed: UInt8)
    }

    /// 结构上有效的 Get VCP Feature Reply。
    nonisolated struct Reply: Equatable {
        let resultCode: UInt8
        /// 完整 MH/ML/SH/SL 值(MH<<8|ML)。
        let current: UInt16
        let max: UInt16
        /// 原始帧字节(诊断/导出用)。
        let raw: [UInt8]
    }

    /// 解析 Get VCP Feature Reply 帧。
    /// - Parameters:
    ///   - bytes: 读取到的原始字节。
    ///   - requestedVCP: 请求的 VCP 码(校验回显)。
    static func parseGetVCPReply(bytes: [UInt8], requestedVCP: UInt8) -> FrameResult {
        guard bytes.count >= replyLength else {
            return .malformed(reason: .badLength(actual: bytes.count))
        }

        // 帧结构:D[0]=源地址(0x6E),D[1]=长度,D[2]=opcode(0x02),
        // D[3]=resultCode,D[4]=回显 VCP,D[5]=保留,D[6..7]=max,D[8..9]=current,D[10]=checksum。
        guard bytes[2] == 0x02 else {
            return .malformed(reason: .badOpcode(actual: bytes[2]))
        }
        guard bytes[4] == requestedVCP else {
            return .malformed(reason: .vcpEchoMismatch(requested: requestedVCP, echoed: bytes[4]))
        }
        // 校验和:0x50 seed,对 D[0..n-2] XOR。
        let computed = bytes.dropLast().reduce(UInt8(0x50)) { $0 ^ $1 }
        guard computed == bytes[bytes.count - 1] else {
            return .malformed(reason: .badChecksum)
        }

        let maxValue = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
        let currentValue = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        return .valid(Reply(
            resultCode: bytes[3],
            current: currentValue,
            max: maxValue,
            raw: Array(bytes.prefix(replyLength))
        ))
    }
}
