import CoreGraphics
import Foundation

// MARK: - 稳定身份(D1)

/// 显示器稳定身份:基于厂商/型号/有效序列/EDID 线索,替代裸 CGDirectDisplayID
/// 贯穿持久化与异步请求。显示编号会被系统复用,断开重接后同编号可能是另一台设备。
nonisolated struct DisplayIdentity: Hashable, Sendable {
    let vendorID: UInt16
    let productID: UInt16
    /// 有效序列号(非零)。nil 表示无序列证据(零序列号设备)。
    let serialNumber: String?
    /// 注册表 EDID UUID(有则作为附加证据)。
    let edidUUID: String?
    let isBuiltIn: Bool

    /// 持久化命名空间的稳定键。无序列号的同型号设备共享同一 stableKey——
    /// 这正是歧义场景:持久化读取方必须先做唯一性校验(见 IdentityLedger)。
    var stableKey: String {
        let serial = serialNumber ?? "noserial"
        let role = isBuiltIn ? "builtIn" : "ext"
        return "\(role).\(vendorID).\(productID).\(serial)"
    }
}

/// 单条匹配证据及其强度。强证据(连接位置精确一致、有效序列一致)足以单独确定唯一匹配;
/// 弱证据(名称相似、EDID 派生特征吻合)只能构成候选,歧义由唯一性校验处理。
nonisolated enum DisplayMatchEvidence: Hashable, Sendable {
    /// IORegistry 显示位置字符串逐字符一致(同一物理端口)。
    case exactLocation
    /// 有效序列号一致(同型号多屏中可唯一区分)。
    case exactSerial
    /// 厂商/型号一致 + 名称一致(弱)。
    case productName
    /// EDID 派生特征(产品码/制造周)吻合(弱)。
    case edidTrait

    var isStrong: Bool {
        switch self {
        case .exactLocation, .exactSerial: true
        case .productName, .edidTrait: false
        }
    }
}

/// 匹配决策输出。证据不足时保留歧义,不按候选枚举顺序强行分配。
nonisolated enum DisplayMatchResult: Equatable, Sendable {
    case matched(identity: DisplayIdentity, serviceIndex: Int)
    case ambiguous(candidates: [Int])
    case unmatched
}

/// 把 CG 显示信息与注册表候选做纯函数匹配:先处理全部强证据,
/// 剩余候选若仍多于一个则输出歧义,绝不贪心分配。
/// 输入候选顺序不影响结果(歧义候选按位置稳定排序)。
nonisolated enum DisplayIdentityMatcher {
    /// - Parameters:
    ///   - display: CG 侧身份信息(位置/序列/厂商型号/名称)。
    ///   - candidates: 注册表侧候选服务信息。
    static func match(
        display: CGDisplayIdentityInfo,
        candidates: [RegistryIdentityInfo]
    ) -> DisplayMatchResult {
        // 每个候选收集证据;强证据候选 > 1 → 歧义;强证据唯一 → 匹配;
        // 无强证据时,弱证据唯一 → 仍为候选歧义(不任意写)。
        var strongMatch: Int?
        var weakCandidates: [Int] = []
        for (index, candidate) in candidates.enumerated() {
            var strong = false
            var weak = false
            if !display.ioDisplayLocation.isEmpty,
               display.ioDisplayLocation == candidate.ioDisplayLocation {
                strong = true
            }
            if let serial = display.serialNumber, let candidateSerial = candidate.serialNumber,
               serial != 0, candidateSerial != 0, serial == candidateSerial {
                strong = true
            }
            if display.vendorID == candidate.vendorID,
               display.productID == candidate.productID,
               !display.productName.isEmpty,
               display.productName.lowercased() == candidate.productName.lowercased() {
                weak = true
            }
            if display.edidTraits == candidate.edidTraits, !display.edidTraits.isEmpty {
                weak = true
            }

            if strong {
                if strongMatch != nil, candidates[strongMatch!].ioDisplayLocation != candidate.ioDisplayLocation {
                    // 两个候选同时具备强证据:通常因位置与序列各指向不同候选,
                    // 属矛盾证据,不任意选择。
                    return .ambiguous(candidates: [strongMatch!, index].sorted())
                }
                strongMatch = index
            } else if weak {
                weakCandidates.append(index)
            }
        }

        if let strongMatch {
            return .matched(identity: displayIdentity(from: display), serviceIndex: strongMatch)
        }
        if weakCandidates.count == 1 {
            return .matched(identity: displayIdentity(from: display), serviceIndex: weakCandidates[0])
        }
        if weakCandidates.count > 1 {
            return .ambiguous(candidates: weakCandidates.sorted())
        }
        return .unmatched
    }

    private static func displayIdentity(from display: CGDisplayIdentityInfo) -> DisplayIdentity {
        DisplayIdentity(
            vendorID: display.vendorID,
            productID: display.productID,
            serialNumber: display.serialNumber.map { String($0) },
            edidUUID: nil,
            isBuiltIn: display.isBuiltIn
        )
    }
}

/// CG 侧(Callback 显示信息字典派生)的身份输入。
nonisolated struct CGDisplayIdentityInfo: Sendable {
    let ioDisplayLocation: String
    let serialNumber: Int64?
    let vendorID: UInt16
    let productID: UInt16
    let productName: String
    /// EDID 派生特征串(产品码+制造周年的十六进制拼接),弱证据。
    let edidTraits: String
    let isBuiltIn: Bool
}

/// 注册表侧候选服务的身份输入。
nonisolated struct RegistryIdentityInfo: Sendable {
    let ioDisplayLocation: String
    let serialNumber: Int64?
    let vendorID: UInt16
    let productID: UInt16
    let productName: String
    let edidTraits: String
}

// MARK: - 连接代次(D1)

/// 一条物理连接(服务对象)的登记。断开、服务替换、身份不一致都会产生新的 token,
/// 失效 token 上的回调、待写目标与能力缓存均不再作用于当前连接。
nonisolated struct DisplayConnection: Equatable, Sendable {
    let token: UUID
    let displayID: CGDirectDisplayID
    let identity: DisplayIdentity
    /// 服务句柄(fake 或真实 IOAVService 包装)。
    let service: DDCServiceHandle
    /// 用户显式绑定:拓扑证据变化后绑定失效转待绑定。
    let isUserBound: Bool
}

// MARK: - MCDP29XX 芯片地址(6.4)

/// MCDP29XX 转换芯片地址选择。M1/M2 机内 HDMI 口经 MCDP29xx 做内部 DP→HDMI 转换,
/// 该芯片的 IOAVService 需用 0xB7 作为 chipAddress,否则 DDC 报文无法到达显示器。
/// 标准连接用 0x37。传输路由地址与 DDC 源地址/校验和是独立概念:是否 MCDP29XX
/// 只决定 chipAddress,不改变协议层校验规则。
nonisolated enum MCDP29XXAddress {
    static let standardChipAddress: UInt8 = 0x37
    static let mcdp29XXChipAddress: UInt8 = 0xB7

    static func chipAddress(isMCDP29XX: Bool) -> UInt8 {
        isMCDP29XX ? mcdp29XXChipAddress : standardChipAddress
    }
}

// MARK: - 显式连接绑定(D1/2.4)

/// 用户显式把音频 UID 或候选服务绑定到稳定身份。绑定只在身份证据保持一致的
/// 前提下有效——拓扑变化(换口/服务替换)导致证据变化时失效,需重新绑定。
nonisolated struct DisplayBindingLedger {
    /// audioUID → DisplayIdentity 的显式绑定。
    private var audioBindings: [String: DisplayIdentity] = [:]
    /// 候选服务索引 → DisplayIdentity 的手动绑定。
    private var serviceBindings: [Int: DisplayIdentity] = [:]

    /// 绑定显式音频目标(仅用户主动执行时)。
    mutating func bind(audioUID: String, to identity: DisplayIdentity) {
        audioBindings[audioUID] = identity
    }

    func audioIdentity(for uid: String) -> DisplayIdentity? {
        audioBindings[uid]
    }

    /// 绑定候选服务(消歧时用户选定)。
    mutating func bind(serviceIndex: Int, to identity: DisplayIdentity) {
        serviceBindings[serviceIndex] = identity
    }

    func identity(forServiceIndex index: Int) -> DisplayIdentity? {
        serviceBindings[index]
    }

    /// 连接建立后校验绑定是否仍成立:身份证据必须一致,否则失效转待绑定。
    func isValid(audioUID: String, for identity: DisplayIdentity) -> Bool {
        audioBindings[audioUID] == identity
    }

    /// 清除全部绑定(拓扑大变化/用户重置)。
    mutating func removeAll() {
        audioBindings.removeAll()
        serviceBindings.removeAll()
    }
}
