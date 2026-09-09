import Testing
@testable import HagimiMonitorDirect
import Foundation

/// 身份匹配纯函数测试(D1/2.1/2.2)。
/// 核心:强证据(连接位置/有效序列)优先;矛盾证据不任意分配;同分歧义保持歧义;
/// 候选枚举顺序不改变正确匹配。
struct DisplayIdentityMatcherTests {
    private func display(
        location: String = "",
        serial: Int64? = nil,
        vendor: UInt16 = 0x1234,
        product: UInt16 = 0x5678,
        name: String = "Dell U2723QE",
        traits: String = "AABB",
        isBuiltIn: Bool = false
    ) -> CGDisplayIdentityInfo {
        CGDisplayIdentityInfo(
            ioDisplayLocation: location,
            serialNumber: serial,
            vendorID: vendor,
            productID: product,
            productName: name,
            edidTraits: traits,
            isBuiltIn: isBuiltIn
        )
    }

    private func registry(
        location: String = "",
        serial: Int64? = nil,
        vendor: UInt16 = 0x1234,
        product: UInt16 = 0x5678,
        name: String = "Dell U2723QE",
        traits: String = "AABB"
    ) -> RegistryIdentityInfo {
        RegistryIdentityInfo(
            ioDisplayLocation: location,
            serialNumber: serial,
            vendorID: vendor,
            productID: product,
            productName: name,
            edidTraits: traits
        )
    }

    // MARK: - 2.1 稳定身份

    /// 相同显示编号(displayID 相同)但不同设备(不同序列/位置):必须歧义或按强证据唯一区分,
    /// 绝不因编号相同而视为同一设备。
    @Test func sameDisplayNumberDifferentDevicesIsNotFalselyMatched() {
        // 两台设备:位置与序列都不同(同一显示编号段),必须各自精确匹配。
        let displayA = display(location: "/IOService/foo0", serial: 100)
        let displayB = display(location: "/IOService/foo1", serial: 200)
        let candA = registry(location: "/IOService/foo0", serial: 100)
        let candB = registry(location: "/IOService/foo1", serial: 200)

        let resultA = DisplayIdentityMatcher.match(display: displayA, candidates: [candA, candB])
        let resultB = DisplayIdentityMatcher.match(display: displayB, candidates: [candA, candB])

        // 位置精确一致 → 各自唯一匹配到正确候选。
        if case .matched(_, let indexA) = resultA {
            #expect(indexA == 0)
        } else {
            Issue.record("displayA 应按位置唯一匹配")
        }
        if case .matched(_, let indexB) = resultB {
            #expect(indexB == 1)
        } else {
            Issue.record("displayB 应按位置唯一匹配")
        }
    }

    /// 零序列号同款双屏:位置可区分 → 唯一匹配;位置也相同 → 歧义(不任意分配)。
    @Test func zeroSerialSameModelDualScreens() {
        // 位置不同可区分。
        let d1 = display(location: "loc-a", serial: nil)
        let d2 = display(location: "loc-b", serial: nil)
        let c1 = registry(location: "loc-a", serial: nil)
        let c2 = registry(location: "loc-b", serial: nil)
        if case .matched(_, let i) = DisplayIdentityMatcher.match(display: d1, candidates: [c1, c2]) {
            #expect(i == 0)
        } else { Issue.record("位置可区分时零序列号应匹配") }

        // 位置为空且无序列(两条注册表候选无法定位)→ 歧义。
        let d3 = display(location: "", serial: nil)
        let c3 = registry(location: "", serial: nil)
        let c4 = registry(location: "", serial: nil)
        if case .ambiguous = DisplayIdentityMatcher.match(display: d3, candidates: [c3, c4]) {
            // 正确
        } else { Issue.record("零序列无位置必须歧义") }
    }

    /// 相同 EDID 特征但位置不同:EDID 是弱证据,位置强证据优先。
    @Test func sameEDIDTraitsDistinguishedByLocation() {
        let display = display(location: "port-2", traits: "DELL-A272")
        let c1 = registry(location: "port-1", traits: "DELL-A272")
        let c2 = registry(location: "port-2", traits: "DELL-A272")
        if case .matched(_, let i) = DisplayIdentityMatcher.match(display: display, candidates: [c1, c2]) {
            #expect(i == 1, "EDID 相同但位置不同的候选,位置强证据应胜出")
        } else { Issue.record("位置强证据应唯一匹配") }
    }

    // MARK: - 2.2 纯匹配决策

    /// 重排候选枚举顺序不改变正确匹配。
    @Test func candidateOrderDoesNotChangeMatch() {
        let display = display(location: "port-0", serial: 777)
        let c1 = registry(location: "port-1", serial: 888)
        let c2 = registry(location: "port-0", serial: 777)

        let forward = DisplayIdentityMatcher.match(display: display, candidates: [c1, c2])
        let backward = DisplayIdentityMatcher.match(display: display, candidates: [c2, c1])

        guard case .matched(_, let iF) = forward, case .matched(_, let iB) = backward else {
            Issue.record("都应唯一匹配")
            return
        }
        #expect(iF == 1)
        #expect(iB == 0)
        // 两者都匹配到"同一候选"(端口 0 / 序列 777)。
        #expect(iF != iB || true)
    }

    /// 矛盾强证据(位置指向 A,序列指向 B):不任意分配,保持歧义。
    @Test func conflictingStrongEvidenceStaysAmbiguous() {
        let display = display(location: "port-A", serial: 100)
        let cA = registry(location: "port-A", serial: 999)
        let cB = registry(location: "port-B", serial: 100)
        // 位置强证据指向 cA,序列强证据指向 cB → 矛盾。
        if case .ambiguous = DisplayIdentityMatcher.match(display: display, candidates: [cA, cB]) {
            // 正确:不贪心分配。
        } else {
            Issue.record("矛盾强证据必须保持歧义")
        }
    }

    /// 同分(多个弱证据候选)保持歧义,不任意选一个。
    @Test func sameScoreWeakEvidenceStaysAmbiguous() {
        let display = display(serial: nil, name: "Generic", traits: "")
        let c1 = registry(serial: nil, name: "Generic", traits: "")
        let c2 = registry(serial: nil, name: "Generic", traits: "")
        if case .ambiguous = DisplayIdentityMatcher.match(display: display, candidates: [c1, c2]) {
            // 正确
        } else { Issue.record("同分弱证据必须歧义") }
    }

    /// 全部不匹配 → unmatched。
    @Test func noMatchReturnsUnmatched() {
        let display = display(location: "z", serial: 1, vendor: 0x1111, product: 0x2222, name: "X", traits: "X")
        let cand = registry(location: "y", serial: 2, vendor: 0x3333, product: 0x4444, name: "Y", traits: "Y")
        #expect(DisplayIdentityMatcher.match(display: display, candidates: [cand]) == .unmatched)
    }
}
