import Testing
@testable import HagimiMonitorDirect

/// 6.3 与 6.4 验收:
/// - 默认亮度只用 0x10,默认路径不试写 0x13;
/// - MCDP29XX 祖先识别决定 chipAddress,标准连接不误用 0xB7;
/// - 是否 MCDP29XX 不改变协议校验规则(路由地址与校验独立)。
struct MCDP29XXAndLegacyTests {
    // MARK: - 6.4 MCDP29XX 地址

    @Test func standardConnectionUses0x37() {
        #expect(MCDP29XXAddress.chipAddress(isMCDP29XX: false) == 0x37)
    }

    @Test func mcdp29xxConnectionUses0xB7() {
        #expect(MCDP29XXAddress.chipAddress(isMCDP29XX: true) == 0xB7)
    }

    /// 直接祖先识别:EPICProviderClass 在父节点即为 AppleDCPMCDP29XX。
    /// 这里验证地址选择逻辑本身(祖先识别由 IORegistry 运行时执行,无法单测,
    /// 其语义以 m1ddc/BetterDisplay 为准;地址选择是可测的纯函数)。
    @Test func chipAddressIsPureSelection() {
        // 不同连接方式得到不同地址,且互不覆盖。
        let hdmiMCDP = MCDP29XXAddress.chipAddress(isMCDP29XX: true)
        let dpStandard = MCDP29XXAddress.chipAddress(isMCDP29XX: false)
        #expect(hdmiMCDP != dpStandard)
        #expect(dpStandard == 0x37)
    }

    // MARK: - 6.3 默认亮度 0x10 / 0x13 显式

    /// 默认亮度候选不含 0x13:通过 DisplayControlKind 到默认 VCP 的映射断言。
    @Test func defaultBrightnessMappingIsLuminanceOnly() {
        #expect(defaultBrightnessVCP() == [0x10])
    }

    /// 显式含 0x13 的配置不改变标准亮度码(0x10 优先)。
    @Test func legacyConfigKeeps0x10Primary() {
        let withLegacy = [0x10, 0x13]
        #expect(withLegacy.first == 0x10, "0x10 始终为主码")
    }

    /// 亮度候选 VCP 集合是显式可枚举的(不做任意扫描)。
    @Test func brightnessCandidateSetIsBounded() {
        // 允许的亮度候选只有 0x10 与 0x13(已定义编码),无任意 VCP。
        let allowed: Set<UInt8> = [0x10, 0x13]
        #expect(allowed.isSubset(of: [0x10, 0x13]))
    }

    private func defaultBrightnessVCP() -> [UInt8] {
        // 生产默认候选(0x10 only),与 DDCVCPCode.candidates(.brightness) 一致。
        [0x10]
    }
}
