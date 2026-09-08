import Foundation

// MARK: - 逐 VCP 能力证据(D5/6.1)

/// 单个 VCP 码的证据:有效应答证明支持、明确不支持、或未定论。
/// 按具体控制码记录证据,一个备用码的结果不会覆盖另一个码的既有证据。
nonisolated enum VCPCapabilityEvidence: Equatable, Sendable {
    /// 有效读应答(resultCode 0x00 且 max>0)证明支持该码。
    case supported
    /// 明确回复不支持(resultCode 0x01)。
    case unsupported
    /// 未收到有效应答(无应答/坏帧)——保留既有证据,不升级为不支持。
    case unknown
}

/// 逐属性能力证据表:记录每个 (连接, 属性) 下每个候选 VCP 码的证据与当前有效范围。
/// 瞬时通信失败只更新"最近通信"状态,不翻转能力证据。
nonisolated final class DisplayCapabilityEvidenceStore {
    /// key = 连接 token + 属性 + VCP 码。
    private var evidence: [EvidenceKey: VCPCapabilityEvidence] = [:]
    private let lock = NSLock()

    private struct EvidenceKey: Hashable {
        let token: UUID
        let control: DisplayControlKind
        let vcp: UInt8
    }

    func evidence(for token: UUID, control: DisplayControlKind, vcp: UInt8) -> VCPCapabilityEvidence {
        lock.lock(); defer { lock.unlock() }
        return evidence[EvidenceKey(token: token, control: control, vcp: vcp)] ?? .unknown
    }

    func setEvidence(_ value: VCPCapabilityEvidence, for token: UUID, control: DisplayControlKind, vcp: UInt8) {
        lock.lock(); defer { lock.unlock() }
        let key = EvidenceKey(token: token, control: control, vcp: vcp)
        // 单次无应答(unknown)不覆盖既有的确定性证据(supported/unsupported):
        // supported 来自显示器明确应答,瞬时丢包不翻转能力。这是"逐 VCP 证据
        // 保留有效支持证据"的核心——探测再次明确应答时才更新。
        if value == .unknown, let existing = evidence[key], existing != .unknown {
            return
        }
        evidence[key] = value
    }

    func reset(token: UUID) {
        lock.lock(); defer { lock.unlock() }
        for key in evidence.keys where key.token == token {
            evidence.removeValue(forKey: key)
        }
    }

    /// 汇总属性能力:所有已配置候选明确不支持 → unsupported;有 supported → supported;
    /// 有 unknown → unknown(保留未知,不乐观默认可用)。
    func aggregatedCapability(for token: UUID, control: DisplayControlKind, candidateVCPs: [UInt8]) -> VCPCapabilityEvidence {
        lock.lock(); defer { lock.unlock() }
        var sawSupported = false
        var sawUnknown = false
        var sawUnsupported = false
        for vcp in candidateVCPs {
            switch evidence[EvidenceKey(token: token, control: control, vcp: vcp)] ?? .unknown {
            case .supported: sawSupported = true
            case .unsupported: sawUnsupported = true
            case .unknown: sawUnknown = true
            }
        }
        if sawSupported { return .supported }
        if sawUnknown { return .unknown }
        if sawUnsupported { return .unsupported }
        return .unknown
    }
}

// MARK: - 后端选择(D5/6.5)

/// 控制后端:每属性独立选择,亮度软件调光不影响音量和对比度的 DDC 控制。
nonisolated enum ControlBackend: Equatable, Sendable {
    case ddc
    case appleNative
    case gamma
    case unavailable
}

/// 按属性选择后端:亮度可软件/DDC/原生;音量/对比度仅 DDC。
nonisolated enum BackendSelection {
    static func backend(
        for control: DisplayControlKind,
        dimmingMode: DimmingMode,
        capability: VCPCapabilityEvidence,
        isBuiltIn: Bool
    ) -> ControlBackend {
        switch control {
        case .brightness:
            if dimmingMode == .gamma {
                return .gamma
            }
            if isBuiltIn {
                return .appleNative
            }
            return capability == .supported ? .ddc : .unavailable
        case .volume, .contrast:
            // 音量/对比度不因亮度软件模式而禁用:独立走 DDC。
            return capability == .supported ? .ddc : .unavailable
        }
    }
}

// MARK: - 兼容配置模型(D5/6.6)

/// 逐屏兼容配置:亮度模式、读取策略、通信速度、max 覆盖、候选码配置。
/// 设置按稳定身份隔离并校验输入。
nonisolated struct DisplayCompatibilityConfig: Equatable, Sendable {
    enum BrightnessMode: String, Sendable {
        case auto
        case hardwareWriteOnly
        case software
        case disabled
    }

    enum ReadPolicy: String, Sendable {
        case auto
        case off
    }

    enum TimingProfile: String, Sendable {
        case normal
        case slow
    }

    var brightnessMode: BrightnessMode = .auto
    var readPolicy: ReadPolicy = .auto
    var timingProfile: TimingProfile = .normal
    /// 可选 max 覆盖(用户指定合法范围)。
    var rangeOverride: UInt16?
    /// 候选 VCP 码覆盖(仅限有已定义编码的码,不做任意扫描)。
    var vcpOverride: [UInt8]?

    static func validate(rangeOverride: UInt16?) -> Bool {
        guard let rangeOverride else { return true }
        return rangeOverride > 0
    }
}
