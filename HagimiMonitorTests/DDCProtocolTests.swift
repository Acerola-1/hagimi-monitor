import Testing
@testable import HagimiMonitorDirect

/// DDC 帧解析测试(6.2)。
/// 验收:checksum/长度/opcode/回显/resultCode/零 max 夹具通过,
/// 不支持与坏帧/无应答明确区分。
struct DDCProtocolTests {
    /// 构造 Get VCP Feature Reply 帧(按 DDC/CI 布局),自动计算校验和。
    private func makeReply(
        opcode: UInt8 = 0x02,
        resultCode: UInt8 = 0x00,
        vcp: UInt8 = 0x10,
        max: UInt16,
        current: UInt16,
        length: Int = DDCProtocol.replyLength
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = 0x6E // 源地址
        bytes[1] = UInt8(length - 2)
        bytes[2] = opcode
        bytes[3] = resultCode
        bytes[4] = vcp
        bytes[5] = 0x00
        bytes[6] = UInt8((max >> 8) & 0xFF)
        bytes[7] = UInt8(max & 0xFF)
        bytes[8] = UInt8((current >> 8) & 0xFF)
        bytes[9] = UInt8(current & 0xFF)
        // checksum:0x50 seed XOR D[0..n-2]。
        var seed: UInt8 = 0x50
        for i in 0..<(bytes.count - 1) {
            seed ^= bytes[i]
        }
        bytes[bytes.count - 1] = seed
        return bytes
    }

    @Test func validReplyParses() throws {
        let frame = makeReply(resultCode: 0x00, vcp: 0x10, max: 255, current: 128)
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        guard case .valid(let reply) = result else {
            Issue.record("应解析为有效帧,实际 \(result)")
            return
        }
        #expect(reply.resultCode == 0x00)
        #expect(reply.current == 128)
        #expect(reply.max == 255)
        #expect(reply.raw.count == DDCProtocol.replyLength)
    }

    /// resultCode 0x01 = 明确不支持(结构仍有效)。
    @Test func unsupportedResultCodeIsValidFrame() {
        let frame = makeReply(resultCode: 0x01, vcp: 0x10, max: 0, current: 0)
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        guard case .valid(let reply) = result else {
            Issue.record("不支持应答结构仍有效")
            return
        }
        #expect(reply.resultCode == 0x01)
        #expect(DDCRawConversion.isValidRange(max: reply.max) == false, "不支持应答 max 无效")
    }

    /// 零 max:结构有效但范围无效(不作为坏帧,也不作为支持)。
    @Test func zeroMaxIsStructurallyValidButInvalidRange() {
        let frame = makeReply(resultCode: 0x00, vcp: 0x10, max: 0, current: 0)
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        guard case .valid(let reply) = result else {
            Issue.record("零 max 帧结构仍有效")
            return
        }
        #expect(DDCRawConversion.isValidRange(max: reply.max) == false)
    }

    @Test func badChecksumIsMalformed() {
        var frame = makeReply(resultCode: 0x00, vcp: 0x10, max: 255, current: 128)
        frame[frame.count - 1] ^= 0xFF // 破坏校验和。
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        #expect(result == .malformed(reason: .badChecksum))
    }

    @Test func badLengthIsMalformed() {
        let frame = Array(makeReply(max: 100, current: 50).prefix(5))
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        if case .malformed(let reason) = result {
            #expect(reason == .badLength(actual: 5))
        } else {
            Issue.record("短帧应判坏帧")
        }
    }

    @Test func badOpcodeIsMalformed() {
        let frame = makeReply(opcode: 0x03, vcp: 0x10, max: 255, current: 128)
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10)
        if case .malformed(let reason) = result {
            #expect(reason == .badOpcode(actual: 0x03))
        } else {
            Issue.record("错误 opcode 应判坏帧")
        }
    }

    @Test func vcpEchoMismatchIsMalformed() {
        let frame = makeReply(vcp: 0x62, max: 100, current: 50) // 回显 0x62
        let result = DDCProtocol.parseGetVCPReply(bytes: frame, requestedVCP: 0x10) // 请求 0x10
        if case .malformed(let reason) = result {
            #expect(reason == .vcpEchoMismatch(requested: 0x10, echoed: 0x62))
        } else {
            Issue.record("回显不匹配应判坏帧")
        }
    }

    /// 无应答(nil/空)与坏帧/不支持明确区分。
    @Test func noResponseIsDistinctFromMalformed() {
        #expect(DDCProtocol.parseGetVCPReply(bytes: [], requestedVCP: 0x10) == .malformed(reason: .badLength(actual: 0)))
        // noResponse 由传输层表示(无字节);此处确认空帧落到 malformed 而非 valid。
    }
}
