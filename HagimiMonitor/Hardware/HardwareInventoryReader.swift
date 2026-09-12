import Foundation

/// 硬件清单装配器:把 sysctl 与 system_profiler 的原始结果拼成报表要的分类结构。
///
/// 采集是**一次性**的(见 `SystemProfilerRunner`),所以这里不做任何缓存与节流,
/// 每次 `capture()` 都重新装配一份完整的清单。
///
/// 本轮已实现:本机 / CPU / 内存 / 系统与安全——这些都是 sysctl 或单个 DataType
/// 就能拿全的。GPU / 磁盘 / 显示器 / 电源与电池 / 连接 需要 Additional 数据源
/// (Metal、NVMe、CoreWLAN 等),传感器走 SMC 且**仅直连版可读**,分后续增量补。
///
/// 缺失一律写 nil,由渲染端显示 `—`。
final class HardwareInventoryReader {
    /// 共享执行器:缓存跨报表生成复用(见 `SystemProfilerRunner.shared`)。
    private let profiler = SystemProfilerRunner.shared

    /// 采集用到的 DataType 全集。传感器不在此列——它走 SMC,不走 system_profiler。
    ///
    /// 本机实测这 16 个跑完约 2.1 秒;`SPSerialATADataType` / `SPEthernetDataType` /
    /// `SPUSBDataType` 在本机返回空清单(USB 要读 `SPUSBHostDataType`),仍保留读取,
    /// 让换了机器/外接设备后能自然补上。
    private static let dataTypes = [
        "SPHardwareDataType",
        "SPDisplaysDataType",
        "SPMemoryDataType",
        "SPStorageDataType",
        "SPNVMeDataType",
        "SPSerialATADataType",
        "SPPowerDataType",
        "SPNetworkDataType",
        "SPEthernetDataType",
        "SPBluetoothDataType",
        "SPUSBHostDataType",
        "SPThunderboltDataType",
        "SPiBridgeDataType",
        "SPSecureElementDataType",
        "SPSoftwareDataType",
    ]

    /// 模块右栏的分组选择:模块 id → (分类 id, 组 id)。
    ///
    /// 组按 **id 等值**匹配,不按组名——组名已本地化,不能当契约;id 是
    /// `HardwareFactGroup` 的稳定标识,多实例组(多块卷)共享同一 id。
    private static let railSpec: [(module: String, category: String, groupIDs: [String])] = [
        ("cpu", "cpu", ["processor", "cache"]),
        ("gpu", "gpu", ["graphicsMetal"]),
        ("memory", "memory", ["capacityType"]),
        ("network", "connectivity", ["networkInterface", "wifi"]),
        ("disk", "storage", ["volume", "physicalDrive"]),
        ("power", "power", ["battery", "adapter"]),
    ]

    /// 按 `railSpec` 从分类里挑出各模块右栏要展示的分组。选不到就不放进结果
    /// (报表侧于是显示「无可用规格」),而不是产出一个空组。
    func rails(from categories: [HardwareCategory]) -> [String: [HardwareFactGroup]] {
        var result: [String: [HardwareFactGroup]] = [:]
        for spec in Self.railSpec {
            guard let category = categories.first(where: { $0.id == spec.category }) else { continue }
            let groups = category.groups.filter { spec.groupIDs.contains($0.id) }
            if !groups.isEmpty { result[spec.module] = groups }
        }
        return result
    }

    /// 分类顺序即报表「本机」菜单的顺序,与左栏模块顺序对齐。
    func capture() -> HardwareInventory {
        let items = profiler.capture(Self.dataTypes)
        var categories: [HardwareCategory] = [
            thisMac(items["SPHardwareDataType"]?.first),
            cpu(),
            gpuCategory(items["SPDisplaysDataType"]),
            memory(items["SPMemoryDataType"]?.first),
            storageCategory(items),
            displayCategory(items["SPDisplaysDataType"]),
            powerCategory(items),
            connectivityCategory(items),
            system(items["SPSoftwareDataType"]?.first,
                   bridge: items["SPiBridgeDataType"]?.first,
                   secureElement: items["SPSecureElementDataType"]?.first),
        ].compactMap { $0 }

        // 传感器走 SMC,只有直连渠道可读;沙盒下 SMCReader 打不开 AppleSMC,
        // 这里拿到空数组就**整个分类不出现**——与「读不到就显示 —」不同,
        // 一个必然为空的分类留在菜单里只会让人以为坏了。
        if let sensors = sensorsCategory() {
            categories.insert(sensors, at: 7)
        }

        return HardwareInventory(categories: categories,
                                 rails: rails(from: categories),
                                 capturedAt: Date())
    }

    // MARK: - 本机

    private func thisMac(_ hardware: [String: Any]?) -> HardwareCategory {
        let identity = HardwareFactGroup(id: "identity", name: .key("hwGroupIdentity"), facts: [
            // 设备树的 product-name 带屏幕尺寸与年份,比 SPHardwareDataType 的
            // machine_name(只有「MacBook Pro」)更完整,优先用它。
            HardwareFact(label: .key("hwLabelProductName"),
                         value: HardwareIOKit.productString("product-name") ?? text(hardware, "machine_name")),
            HardwareFact(label: .key("hwLabelModelId"), value: text(hardware, "machine_model") ?? HardwareSysctl.string("hw.model")),
            HardwareFact(label: .key("hwLabelModelNumber"), value: text(hardware, "model_number")),
            HardwareFact(label: .key("hwLabelSerialNumber"), value: text(hardware, "serial_number")),
            HardwareFact(label: .key("hwLabelFirmwareVersion"), value: text(hardware, "boot_rom_version")),
            HardwareFact(label: .key("hwLabelOsLoader"), value: text(hardware, "os_loader_version")),
        ])

        let silicon = HardwareFactGroup(id: "silicon", name: .key("hwGroupSilicon"), facts: [
            HardwareFact(label: .key("hwLabelSoC"),
                         value: HardwareIOKit.productString("product-soc-name")
                             ?? text(hardware, "chip_type")
                             ?? HardwareSysctl.string("machdep.cpu.brand_string")),
            HardwareFact(label: .key("hwLabelProcessor"), value: text(hardware, "number_processors")),
            HardwareFact(label: .key("hwLabelMemory"), value: text(hardware, "physical_memory")
                ?? HardwareSysctl.describeBinaryBytes(HardwareSysctl.integer("hw.memsize", as: UInt64.self))),
            HardwareFact(label: .key("hwLabelMemoryUpgradeable"), value: HardwareIOKit.productBool("upgradeable-memory").map(yesNo)),
            HardwareFact(label: .key("hwLabelDeviceTree"), value: HardwareIOKit.productString("unique-model")),
        ])

        let capabilities = HardwareFactGroup(id: "capabilities", name: .key("hwGroupCapabilities"), facts: [
            HardwareFact(label: .key("hwLabelDisplayMirroring"), value: HardwareIOKit.productBool("display-mirroring").map(yesNo)),
            HardwareFact(label: .key("hwLabelWifiChip"), value: HardwareIOKit.productString("wifi-chipset")),
            HardwareFact(label: .key("hwLabelBtLeAudio"), value: HardwareIOKit.productBool("bluetooth-lea2").map(yesNo)),
            HardwareFact(label: .key("hwLabelVirtualization"), value: HardwareIOKit.productBool("has-virtualization").map(yesNo)),
            HardwareFact(label: .key("hwLabelBuiltinBattery"), value: HardwareIOKit.productBool("builtin-battery").map(yesNo)),
        ])

        return HardwareCategory(
            id: "this-mac", nameKey: "hwCatThisMac", subtitleKey: "hwSubThisMac",
            groups: [identity, silicon, capabilities])
    }

    // MARK: - CPU

    private func cpu() -> HardwareCategory {
        let levels = performanceLevels()
        let performance = levels.first { $0.index == 0 }
        let efficiency = levels.first { $0.index == 1 }

        let coreGroup = HardwareFactGroup(id: "processor", name: .key("hwGroupProcessor"), facts: [
            HardwareFact(label: .key("hwLabelChip"), value: HardwareSysctl.string("machdep.cpu.brand_string")),
            HardwareFact(label: .key("hwLabelArchitecture"), value: HardwareSysctl.string("hw.machine")),
            HardwareFact(label: .key("hwLabelPhysicalCores"), value: int("hw.physicalcpu").map(String.init)),
            HardwareFact(label: .key("hwLabelLogicalCores"), value: int("hw.logicalcpu").map(String.init)),
            HardwareFact(label: .key("hwLabelPeCores"), value: clusterCount(performance, efficiency)),
            HardwareFact(label: .key("hwLabelCacheLine"), value: int("hw.cachelinesize").map { "\($0) 字节" }),
            HardwareFact(label: .key("hwLabelPageSize"), value: HardwareSysctl.describeBinaryBytes(
                HardwareSysctl.integer("hw.pagesize", as: UInt64.self))),
            HardwareFact(label: .key("hwLabelTimebase"), value: HardwareSysctl.describeFrequency(
                HardwareSysctl.number("hw.tbfrequency"))),
            HardwareFact(label: .key("hwLabelCpuFamily"), value: HardwareSysctl.integer("hw.cpufamily", as: UInt32.self)
                .map { String(format: "0x%08x", $0) }),
            HardwareFact(label: .key("hwLabel64Bit"), value: HardwareSysctl.isEnabled("hw.cpu64bit_capable").map(yesNo)),
            HardwareFact(label: .key("hwLabelHypervisor"), value: HardwareSysctl.isEnabled("kern.hv_support").map(yesNo)),
        ])

        let cacheGroup = HardwareFactGroup(id: "cache", name: .key("hwGroupCache"), facts: [
            HardwareFact(label: .key("hwLabelL1I"), value: pair(performance?.l1i, efficiency?.l1i,
                                                            transform: HardwareSysctl.describeBinaryBytes)),
            HardwareFact(label: .key("hwLabelL1D"), value: pair(performance?.l1d, efficiency?.l1d,
                                                            transform: HardwareSysctl.describeBinaryBytes)),
            HardwareFact(label: .key("hwLabelL2"), value: pair(performance?.l2, efficiency?.l2,
                                                       transform: HardwareSysctl.describeBinaryBytes)),
        ])

        return HardwareCategory(
            id: "cpu", nameKey: "hwCatCpu", subtitleKey: "hwSubCpu",
            groups: [coreGroup, cacheGroup, instructionSetGroup()])
    }

    private struct PerformanceLevel {
        let index: Int
        let name: String?
        let cores: Int?
        let l1i: UInt64?
        let l1d: UInt64?
        let l2: UInt64?
    }

    /// `hw.nperflevels` 给出簇数(Apple Silicon 通常 2:性能核簇 + 能效核簇)。
    /// 每簇的前缀是 `hw.perflevel{n}.`,字段名在各机型上一致,不需要硬编码键名。
    private func performanceLevels() -> [PerformanceLevel] {
        guard let count = HardwareSysctl.integer("hw.nperflevels", as: Int32.self), count > 0 else {
            return []
        }
        return (0..<Int(count)).map { level in
            let prefix = "hw.perflevel\(level)."
            return PerformanceLevel(
                index: level,
                name: HardwareSysctl.string(prefix + "name"),
                cores: HardwareSysctl.integer(prefix + "physicalcpu", as: Int32.self).map(Int.init),
                l1i: HardwareSysctl.integer(prefix + "l1icachesize", as: UInt64.self),
                l1d: HardwareSysctl.integer(prefix + "l1dcachesize", as: UInt64.self),
                l2: HardwareSysctl.integer(prefix + "l2cachesize", as: UInt64.self))
        }
    }

    /// 「4 · 6」这种两簇并列的写法;只有一簇时退化为单值。
    private func clusterCount(_ performance: PerformanceLevel?, _ efficiency: PerformanceLevel?) -> String? {
        let values = [performance?.cores, efficiency?.cores].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.map(String.init).joined(separator: " · ")
    }

    private func pair(_ performance: UInt64?, _ efficiency: UInt64?,
                      transform: (UInt64?) -> String?) -> String? {
        let values = [performance, efficiency].compactMap { transform($0) }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " · ")
    }

    /// 指令集特性不铺满一栏:参考项目会列出 60+ 行,在本项目里没有阅读价值。
    /// 只给一行「支持 N 项 · 部分支持 …」,完整清单留给需要时再展开。
    private func instructionSetGroup() -> HardwareFactGroup {
        let names = HardwareSysctl.names(under: "hw.optional")
            .filter { !$0.contains("_max_svl") }  // 这类是尺寸参数,不是特性开关
        let supported = names.compactMap { name -> String? in
            guard let value = HardwareSysctl.integer(name, as: Int32.self), value == 1 else { return nil }
            return name
                .replacingOccurrences(of: "hw.optional.arm.", with: "")
                .replacingOccurrences(of: "hw.optional.", with: "")
        }
        return HardwareFactGroup(id: "instructionSet", name: .key("hwGroupInstructionSet"), facts: [
            HardwareFact(label: .key("hwLabelSupportedItems"),
                         value: supported.isEmpty ? nil
                             : String(format: hwText("hwValueCountItems"), "\(supported.count)")),
            HardwareFact(label: .key("hwLabelPartialSupport"), value: supported.filter { $0.hasPrefix("FEAT_") }
                .prefix(6).joined(separator: " · ")),
        ])
    }

    // MARK: - 内存

    private func memory(_ dimm: [String: Any]?) -> HardwareCategory {
        let type = [text(dimm, "dimm_type"), text(dimm, "dimm_manufacturer")]
            .compactMap { $0 }.joined(separator: " · ")
        return HardwareCategory(
            id: "memory", nameKey: "hwCatMemory", subtitleKey: "hwSubMemory",
            groups: [HardwareFactGroup(id: "capacityType", name: .key("hwGroupCapacityType"), facts: [
                HardwareFact(label: .key("hwLabelInstalled"), value: HardwareSysctl.describeBinaryBytes(
                    HardwareSysctl.integer("hw.memsize", as: UInt64.self))),
                HardwareFact(label: .key("hwLabelUsableMemory"), value: HardwareSysctl.describeBinaryBytes(
                    HardwareSysctl.integer("hw.memsize_usable", as: UInt64.self))),
                HardwareFact(label: .key("hwLabelType"), value: type.isEmpty ? nil : type),
                HardwareFact(label: .key("hwLabelPageSize"), value: HardwareSysctl.describeBinaryBytes(
                    HardwareSysctl.integer("hw.pagesize", as: UInt64.self))),
                HardwareFact(label: .key("hwLabelEcc"), value: HardwareSysctl.isEnabled("hw.optional.ecc").map(yesNo)),
            ])])
    }

    // MARK: - 系统与安全

    private func system(_ software: [String: Any]?, bridge: [String: Any]?,
                        secureElement: [String: Any]?) -> HardwareCategory {
        let runtime = bootUptime()
        let systemGroup = HardwareFactGroup(id: "system", name: .key("hwGroupSystem"), facts: [
            HardwareFact(label: .key("hwLabelOsVersion"), value: text(software, "os_version")),
            HardwareFact(label: .key("hwLabelKernel"), value: text(software, "kernel_version")),
            HardwareFact(label: .key("hwLabelBootVolume"), value: text(software, "boot_volume")),
            HardwareFact(label: .key("hwLabelBootMode"), value: bootMode(text(software, "boot_mode"))),
            HardwareFact(label: .key("hwLabelHostname"), value: text(software, "local_host_name")),
            HardwareFact(label: .key("hwLabelUptime"), value: runtime),
            HardwareFact(label: .key("hwLabelBootArgs"),
                         value: HardwareSysctl.string("kern.bootargs") ?? hwText("hwValueNone")),
            HardwareFact(label: .key("hwLabelSafeMode"), value: HardwareSysctl.isEnabled("kern.safeboot").map(yesNo)),
            HardwareFact(label: .key("hwLabelSecureKernel"), value: HardwareSysctl.isEnabled("kern.secure_kernel").map(yesNo)),
            HardwareFact(label: .key("hwLabelMaxProcesses"), value: int("kern.maxproc").map(HardwareSysctl.group)),
            HardwareFact(label: .key("hwLabelMaxOpenFiles"), value: int("kern.maxfiles").map(HardwareSysctl.group)),
            HardwareFact(label: .key("hwLabelRosetta"),
                         value: rosettaInstalled() ? hwText("hwValueRosettaInstalled") : hwText("hwValueRosettaNotInstalled")),
            HardwareFact(label: .key("hwLabelActiveProcessors"), value: "\(ProcessInfo.processInfo.activeProcessorCount)"),
        ])

        // SPiBridgeDataType 的值**系统已经本地化过**(本机 zh-Hans 下直接是「已启用」「完整安全性」「否」),
        // 所以不做枚举映射、原样透出;只在「否」这类需要还原语义的地方做最小改写。
        let securityGroup = HardwareFactGroup(id: "security", name: .key("hwGroupSecurity"), facts: [
            HardwareFact(label: .key("hwLabelSecureBoot"), value: text(bridge, "ibridge_secure_boot")),
            HardwareFact(label: .key("hwLabelSip"), value: text(bridge, "ibridge_sb_sip")),
            HardwareFact(label: .key("hwLabelSsv"), value: text(bridge, "ibridge_sb_ssv")),
            HardwareFact(label: .key("hwLabelCtrr"), value: text(bridge, "ibridge_sb_ctrr")),
            HardwareFact(label: .key("hwLabelDeviceMdm"), value: enrollState(text(bridge, "ibridge_sb_device_mdm"))),
            HardwareFact(label: .key("hwLabelManualMdm"), value: enrollState(text(bridge, "ibridge_sb_manual_mdm"))),
            HardwareFact(label: .key("hwLabelUserApprovedKexts"), value: noneWhenNegative(text(bridge, "ibridge_sb_other_kext"))),
            HardwareFact(label: .key("hwLabelBootArgsRestriction"), value: text(bridge, "ibridge_sb_boot_args")),
            HardwareFact(label: .key("hwLabelBuildVersion"), value: text(bridge, "ibridge_build")),
        ])

        // 安全隔区只取可读的控制器版本号;`se_device` / `se_fw` / `se_hw` / `se_id` / `se_plt`
        // 是十六进制寄存器值与不透明 ID(实测形如 `0x37` / `N5E00000018E0000`),对用户没有意义,不列。
        let elementGroup = HardwareFactGroup(id: "secureElement", name: .key("hwGroupSecureElement"), facts: [
            HardwareFact(label: .key("hwLabelControllerFirmware"), value: text(secureElement, "ctl_fw")),
            HardwareFact(label: .key("hwLabelControllerHardware"), value: text(secureElement, "ctl_hw")),
            HardwareFact(label: .key("hwLabelControllerMiddleware"), value: text(secureElement, "ctl_mw")),
            HardwareFact(label: .key("hwLabelOsVersion"), value: text(secureElement, "se_os_version")),
            HardwareFact(label: .key("hwLabelProductionSigned"), value: text(secureElement, "se_prod_signed")),
            HardwareFact(label: .key("hwLabelRestrictedMode"), value: text(secureElement, "se_in_restricted_mode")),
        ])

        return HardwareCategory(
            id: "system", nameKey: "hwCatSystem", subtitleKey: "hwSubSystem",
            groups: [systemGroup, securityGroup, elementGroup])
    }

    // MARK: - 取值与本地化辅助

    /// 从 system_profiler 的条目里取值。值可能是 String / NSNumber / Bool / 字符串数组。
    /// 键含 `.` 时按嵌套字典下钻(如 `physical_drive.protocol`)。
    func text(_ item: [String: Any]?, _ key: String) -> String? {
        guard let item else { return nil }
        if key.contains(".") {
            var current: Any? = item
            for part in key.split(separator: ".").map(String.init) {
                current = (current as? [String: Any])?[part]
            }
            return HardwareIOKit.stringValue(current)
        }
        guard let raw = item[key] else { return nil }
        if let list = raw as? [String] {
            return list.isEmpty ? nil : list.joined(separator: " · ")
        }
        return HardwareIOKit.stringValue(raw)
    }

    private func int(_ name: String) -> Int? {
        HardwareSysctl.number(name).map(Int.init)
    }

    /// 统一「是 / 否」。开关类读数一律走它,别用支持/不支持——
    /// 那是能力标记的语义,`kern.safeboot = 0` 是「没开安全模式」而不是「不支持」。
    private func yesNo(_ value: Bool) -> String {
        value ? hwText("hwValueYes") : hwText("hwValueNo")
    }

    /// 「否」= 未注册管理(device MDM / manual MDM 的语义),不是「不支持」。
    private func enrollState(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw == "否" || raw.lowercased() == "no" ? hwText("hwValueNotEnrolled") : raw
    }

    /// 「否」= 没有任何用户批准的内核扩展。
    private func noneWhenNegative(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw == "否" || raw.lowercased() == "no" ? hwText("hwValueNone") : raw
    }

    /// `SPSoftwareDataType.boot_mode` 的值系统**不做本地化**(实测就是 `normal_boot`),
    /// 与 `SPiBridgeDataType` 那批不一样,所以要自己映射已知枚举。
    private func bootMode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case "normal_boot": return hwText("hwValueBootNormal")
        case "safe_boot": return hwText("hwValueBootSafe")
        default: return raw
        }
    }

    /// `kern.boottime` 是 `timeval`,换算成「N 天 N 小时 N 分」。
    private func bootUptime() -> String? {
        var boot = timeval()
        guard HardwareSysctl.raw("kern.boottime", into: &boot), boot.tv_sec > 0 else { return nil }
        let seconds = Int(Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec))
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return String(format: hwText("hwValueUptimeDays"), "\(days)", "\(hours)", "\(minutes)")
        }
        if hours > 0 {
            return String(format: hwText("hwValueUptimeHours"), "\(hours)", "\(minutes)")
        }
        return String(format: hwText("hwValueUptimeMinutes"), "\(minutes)")
    }

    private func rosettaInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }
}
