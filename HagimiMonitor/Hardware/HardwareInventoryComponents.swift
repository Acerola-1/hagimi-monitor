import CoreWLAN
import Foundation
import Metal

/// 硬件清单:GPU / 显示器 / 磁盘 / 电源与电池 / 连接 / 传感器 六类的装配。
///
/// 与 `HardwareInventoryReader` 同属一次采集流程,拆开只为文件体积——两处的
/// 取值语义(缺什么写 nil、枚举原样透出、值不本地化)完全一致。
///
/// **传感器一类的渠道差异**:温度与风扇走 SMC,沙盒渠道 `IOServiceOpen(AppleSMC)`
/// 被拒(SMCReader 的 init 直接返 nil),因此本类在 App Store 版自然为空、
/// 整个分类不会出现在菜单里;直连版才看得到。这是有意为之,不是漏做。
extension HardwareInventoryReader {

    // MARK: - GPU

    func gpuCategory(_ displays: [[String: Any]]?) -> HardwareCategory {
        let gpu = displays?.first

        // 只取一次:MTLCreateSystemDefaultDevice() 每次调用都新建对象,不是白拿的。
        let device = MTLCreateSystemDefaultDevice()
        var specs: [HardwareFact] = [
            HardwareFact(label: .key("hwLabelGpu"), value: device?.name ?? text(gpu, "sppci_model")),
            HardwareFact(label: .key("hwLabelGpuCores"), value: text(gpu, "sppci_cores")),
            HardwareFact(label: .key("hwLabelArchitecture"), value: device?.architecture.name),
            HardwareFact(label: .key("hwLabelMetalSupport"), value: metalFamily(text(gpu, "spdisplays_mtlgpufamilysupport"))),
            HardwareFact(label: .key("hwLabelVendor"), value: vendorName(text(gpu, "spdisplays_vendor"))),
        ]
        // Metal 能力只挑对用户有意义的几项。参考项目把 30 多项全列出来,
        // 那份清单是给图形开发者看的,放进硬件规格就是噪声。
        if let device {
            specs += [
                HardwareFact(label: .key("hwLabelUnifiedMemory"), value: device.hasUnifiedMemory ? hwText("hwValueSupported") : hwText("hwValueUnsupported")),
                HardwareFact(label: .key("hwLabelRecommendedWorkingSet"), value: HardwareSysctl.describeBinaryBytes(
                    device.recommendedMaxWorkingSetSize)),
                HardwareFact(label: .key("hwLabelMaxBufferLength"), value: HardwareSysctl.describeBinaryBytes(
                    UInt64(device.maxBufferLength))),
                HardwareFact(label: .key("hwLabelRaytracing"), value: device.supportsRaytracing ? hwText("hwValueSupported") : hwText("hwValueUnsupported")),
                HardwareFact(label: .key("hwLabelMsaa32"), value: device.supports32BitMSAA ? hwText("hwValueSupported") : hwText("hwValueUnsupported")),
                HardwareFact(label: .key("hwLabelBcCompression"), value: device.supportsBCTextureCompression ? hwText("hwValueSupported") : hwText("hwValueUnsupported")),
                HardwareFact(label: .key("hwLabelFunctionPointers"), value: device.supportsFunctionPointers ? hwText("hwValueSupported") : hwText("hwValueUnsupported")),
            ]
        }

        let engines: [HardwareFact] = [
            HardwareFact(label: .key("hwLabelMemoryUpgradeable"), value: HardwareIOKit.productBool("upgradeable-memory").map {
                $0 ? hwText("hwValueSupported") : hwText("hwValueUnsupported")
            }),
            HardwareFact(label: .key("hwLabelDisplayMirror"), value: HardwareIOKit.productBool("display-mirroring").map {
                $0 ? hwText("hwValueSupported") : hwText("hwValueUnsupported")
            }),
        ]

        return HardwareCategory(
            id: "gpu", nameKey: "hwCatGpu", subtitleKey: "hwSubGpu",
            groups: [
                HardwareFactGroup(id: "graphicsMetal", name: .key("hwGroupGraphicsMetal"), facts: specs),
                HardwareFactGroup(id: "gpuWholeMachine", name: .key("hwGroupGpuWholeMachine"), facts: engines),
            ])
    }



    /// `MTLDevice` 的 supports* 属性在旧系统上可能不存在,用 KVC 取值,
    /// 拿不到就返 nil(缺失),不假定为 false。

    /// `spdisplays_mtlgpufamilysupport` 的值形如 `spdisplays_metal4`,按前缀取版本号;
    /// 已经是可读文本时原样透出。
    func metalFamily(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let range = raw.range(of: "metal") else { return raw }
        return "Metal " + raw[range.upperBound...]
    }

    private func vendorName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw.hasSuffix("Apple") { return "Apple" }
        if raw.hasSuffix("Intel") { return "Intel" }
        if raw.hasSuffix("AMD") { return "AMD" }
        if raw.hasSuffix("NVIDIA") { return "NVIDIA" }
        return raw
    }

    // MARK: - 显示器

    /// 显示器规格直接用项目已有的 `DisplaySection.collectDisplays()`
    /// (它已经处理了 EDID 解析、位深链路、色域、HDR 能力、制造日期这些细节),
    /// 不再自己去解 `spdisplays_ndrvs`——实测那条路上的制造日期是 0、像素分辨率是个丑值。
    func displayCategory(_ displays: [[String: Any]]?) -> HardwareCategory {
        let gpu = displays?.first
        let chip = HardwareFactGroup(id: "chipset", name: .key("hwGroupChipset"), facts: [
            HardwareFact(label: .key("hwLabelChipsetModel"), value: text(gpu, "sppci_model")),
            HardwareFact(label: .key("hwLabelVendor"), value: vendorName(text(gpu, "spdisplays_vendor"))),
            HardwareFact(label: .key("hwLabelTotalCores"), value: text(gpu, "sppci_cores")),
            HardwareFact(label: .key("hwLabelMetalSupport"), value: metalFamily(text(gpu, "spdisplays_mtlgpufamilysupport"))),
        ])

        let screens = DisplaySection.collectDisplays().map { display -> HardwareFactGroup in
            var facts: [HardwareFact] = [
                HardwareFact(label: .key("hwLabelName"), value: display.name),
                HardwareFact(label: .key("hwLabelType"), value: display.isBuiltIn ? hwText("hwValueBuiltin") : hwText("hwValueExternal")),
                HardwareFact(label: .key("hwLabelResolution"), value: display.resolution),
                HardwareFact(label: .key("hwLabelRefreshRate"), value: display.refreshRate),
                HardwareFact(label: .key("hwLabelColorDepth"), value: display.colorDepth),
                HardwareFact(label: .key("hwLabelGamut"), value: display.gamut),
                HardwareFact(label: .key("hwLabelSize"), value: display.sizeInches.map { String(format: hwText("hwValueInches"), "\($0)") }),
                HardwareFact(label: .key("hwLabelPpi"), value: display.ppi.map { "\($0) ppi" }),
                HardwareFact(label: .key("hwLabelHidpiScale"), value: display.hidpiScale.map { "\($0)×" }),
                HardwareFact(label: .key("hwLabelAdaptiveSync"), value: display.adaptiveSync),
                HardwareFact(label: .key("hwLabelDynamicRange"), value: hdrText(display)),
                HardwareFact(label: .key("hwLabelVendor"), value: display.manufacturer),
                HardwareFact(label: .key("hwLabelModel"), value: display.model),
                HardwareFact(label: .key("hwLabelSerialNumber"), value: display.serial),
                HardwareFact(label: .key("hwLabelManufactureDate"), value: display.manufactureDate),
            ]
            // 唯独保留「动态范围」的空行:HDR 能力缺失与「不支持」语义不同,值得单独一行显示 —。
            facts.removeAll { $0.value == nil && $0.label.key != "hwLabelDynamicRange" }
            return HardwareFactGroup(
                id: "screen", name: .keyed("hwGroupDisplay", [display.name]), facts: facts)
        }

        return HardwareCategory(
            id: "display", nameKey: "hwCatDisplay", subtitleKey: "hwSubDisplay",
            groups: [chip] + screens)
    }

    private func hdrText(_ display: DisplayInfo) -> String? {
        guard let supported = display.hdrSupported else { return nil }
        guard supported else { return hwText("hwValueUnsupported") }
        return (display.hdrActive ?? false) ? hwText("hwValueHdrOn") : hwText("hwValueSupported")
    }

    // MARK: - 磁盘

    func storageCategory(_ items: [String: [[String: Any]]]) -> HardwareCategory {
        let volumes = items["SPStorageDataType"] ?? []
        let drives = items["SPNVMeDataType"]?.first?["_items"] as? [[String: Any]] ?? []

        // 卷:只列根卷与数据卷这类用户认得的,`iSCPreboot` 之类系统卷不进清单。
        let volumeGroups = volumes.compactMap { volume -> HardwareFactGroup? in
            let name = text(volume, "_name") ?? hwText("hwValueVolume")
            let mount = text(volume, "mount_point")
            // 只列用户认得的那几个挂载点:剔除 iSCPreboot / xART / VM 这类系统卷,
            // 但保留数据卷(/System/Volumes/Data)——用户文件都在它上面。
            let isUserVolume = mount == "/" || mount == "/System/Volumes/Data"
                || (mount?.hasPrefix("/Volumes/") ?? false)
            guard isUserVolume else { return nil }
            return HardwareFactGroup(id: "volume", name: .keyed("hwGroupVolume", [name]), facts: [
                HardwareFact(label: .key("hwLabelBsdName"), value: text(volume, "bsd_name")),
                HardwareFact(label: .key("hwLabelFileSystem"), value: text(volume, "file_system")),
                HardwareFact(label: .key("hwLabelCapacity"), value: HardwareSysctl.describeBytes(
                    (volume["size_in_bytes"] as? NSNumber).map { $0.uint64Value })),
                HardwareFact(label: .key("hwLabelAvailableSpace"), value: HardwareSysctl.describeBytes(
                    (volume["free_space_in_bytes"] as? NSNumber).map { $0.uint64Value })),
                HardwareFact(label: .key("hwLabelMountPoint"), value: mount),
                HardwareFact(label: .key("hwLabelWritable"), value: yesNoText(text(volume, "writable"))),
            ])
        }

        let physical = drives.first
        // 型号/固件/序列号只在 SPNVMeDataType 里,SPStorageDataType.physical_drive 里没有。
        let driveFacts: [HardwareFact] = [
            HardwareFact(label: .key("hwLabelDeviceName"), value: text(physical, "device_model")),
            HardwareFact(label: .key("hwLabelMediaType"), value: mediaType(text(physical, "size") != nil
                ? "ssd" : text(volume0(volumes), "physical_drive.medium_type"))),
            HardwareFact(label: .key("hwLabelProtocol"), value: protocolName(text(volume0(volumes), "physical_drive.protocol"))),
            HardwareFact(label: .key("hwLabelSmartStatus"), value: smartText(text(physical, "smart_status"))),
            HardwareFact(label: .key("hwLabelTrimSupport"), value: yesNoText(text(physical, "spnvme_trim_support"))),
            HardwareFact(label: .key("hwLabelInternal"), value: yesNoText(text(volume0(volumes), "physical_drive.is_internal_disk"))),
            HardwareFact(label: .key("hwLabelFirmwareVersion"), value: text(physical, "device_revision")),
            HardwareFact(label: .key("hwLabelSerialNumber"), value: text(physical, "device_serial")),
            HardwareFact(label: .key("hwLabelCapacity"), value: text(physical, "size")),
        ]

        var groups = volumeGroups
        groups.append(HardwareFactGroup(id: "physicalDrive", name: .key("hwGroupPhysicalDrive"), facts: driveFacts))
        return HardwareCategory(
            id: "storage", nameKey: "hwCatStorage", subtitleKey: "hwSubStorage", groups: groups)
    }

    private func volume0(_ volumes: [[String: Any]]) -> [String: Any]? {
        volumes.first { ($0["mount_point"] as? String) == "/" } ?? volumes.first
    }


    private func yesNoText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lowered = raw.lowercased()
        if lowered == "yes" || raw == "是" { return hwText("hwValueYes") }
        if lowered == "no" || raw == "否" { return hwText("hwValueNo") }
        return raw
    }

    private func smartText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw.lowercased().contains("verif") ? hwText("hwValueSmartVerified") : raw
    }

    private func mediaType(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lowered = raw.lowercased()
        if lowered.contains("ssd") { return hwText("hwValueSsd") }
        if lowered.contains("rotational") || lowered.contains("hdd") { return hwText("hwValueHdd") }
        return raw
    }

    private func protocolName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        // SPI 报告的协议名历来是英文短名,保留原样更准确(Apple Fabric / PCI Express …)。
        return raw
    }

    // MARK: - 电源与电池

    func powerCategory(_ items: [String: [[String: Any]]]) -> HardwareCategory? {
        let sections = items["SPPowerDataType"] ?? []
        func section(_ name: String) -> [String: Any]? {
            sections.first { ($0["_name"] as? String) == name }
        }
        guard let batteryInfo = section("spbattery_information") else { return nil }

        let health = batteryInfo["sppower_battery_health_info"] as? [String: Any]
        let charge = batteryInfo["sppower_battery_charge_info"] as? [String: Any]
        let model = batteryInfo["sppower_battery_model_info"] as? [String: Any]

        let battery = HardwareFactGroup(id: "battery", name: .key("hwGroupBattery"), facts: [
            HardwareFact(label: .key("hwLabelCycleCount"), value: text(health, "sppower_battery_cycle_count")),
            HardwareFact(label: .key("hwLabelHealth"), value: text(health, "sppower_battery_health")),
            HardwareFact(label: .key("hwLabelMaxCapacity"), value: text(health, "sppower_battery_health_maximum_capacity").map {
                $0.hasSuffix("%") ? $0 : "\($0)%"
            }),
            HardwareFact(label: .key("hwLabelBatteryLevel"), value: text(charge, "sppower_battery_state_of_charge").map {
                $0.hasSuffix("%") ? $0 : "\($0)%"
            }),
            HardwareFact(label: .key("hwLabelCharging"), value: yesNoText(text(charge, "sppower_battery_is_charging"))),
            HardwareFact(label: .key("hwLabelFullyCharged"), value: yesNoText(text(charge, "sppower_battery_fully_charged"))),
            HardwareFact(label: .key("hwLabelBatteryModel"), value: text(model, "sppower_battery_device_name")),
            HardwareFact(label: .key("hwLabelFirmwareVersion"), value: text(model, "sppower_battery_firmware_version")),
            HardwareFact(label: .key("hwLabelHardwareRevision"), value: text(model, "sppower_battery_hardware_revision")),
            HardwareFact(label: .key("hwLabelCellRevision"), value: text(model, "sppower_battery_cell_revision")),
            HardwareFact(label: .key("hwLabelSerialNumber"), value: text(model, "sppower_battery_serial_number")),
        ])

        // 适配器与电源设置都来自 `sppower_information` 的两个子字典:
        // `AC Power` / `Battery Power`,键名是英文短语(系统未本地化)。
        let powerInfo = section("sppower_information")
        let ac = powerInfo?["AC Power"] as? [String: Any]
        let dc = powerInfo?["Battery Power"] as? [String: Any]

        let adapter = HardwareFactGroup(id: "adapter", name: .key("hwGroupAdapter"), facts: [
            HardwareFact(label: .key("hwLabelConnected"), value: yesNoText(text(section("sppower_ac_charger_information"),
                                                              "sppower_battery_charger_connected"))),
            HardwareFact(label: .key("hwLabelIsCharging"), value: yesNoText(text(section("sppower_ac_charger_information"),
                                                              "sppower_battery_is_charging"))),
            HardwareFact(label: .key("hwLabelPowerSource"), value: text(ac, "Current Power Source").map {
                $0.uppercased() == "TRUE" ? hwText("hwValueAcPower") : $0
            }),
        ])

        let settings = HardwareFactGroup(id: "powerSettingsAC", name: .key("hwGroupPowerSettingsAC"), facts: [
            HardwareFact(label: .key("hwLabelDisplaySleep"), value: sleepTimer(text(ac, "Display Sleep Timer"))),
            HardwareFact(label: .key("hwLabelSystemSleep"), value: sleepTimer(text(ac, "System Sleep Timer"))),
            HardwareFact(label: .key("hwLabelDiskSleep"), value: sleepTimer(text(ac, "Disk Sleep Timer"))),
            HardwareFact(label: .key("hwLabelLowPowerMode"), value: yesNoText(text(ac, "LowPowerMode"))),
            HardwareFact(label: .key("hwLabelWakeOnLan"), value: yesNoText(text(ac, "Wake On LAN"))),
        ])
        let batterySettings = HardwareFactGroup(id: "powerSettingsBattery", name: .key("hwGroupPowerSettingsBattery"), facts: [
            HardwareFact(label: .key("hwLabelDisplaySleep"), value: sleepTimer(text(dc, "Display Sleep Timer"))),
            HardwareFact(label: .key("hwLabelSystemSleep"), value: sleepTimer(text(dc, "System Sleep Timer"))),
            HardwareFact(label: .key("hwLabelDiskSleep"), value: sleepTimer(text(dc, "Disk Sleep Timer"))),
            HardwareFact(label: .key("hwLabelLowPowerMode"), value: yesNoText(text(dc, "LowPowerMode"))),
            HardwareFact(label: .key("hwLabelWakeOnLan"), value: yesNoText(text(dc, "Wake On LAN"))),
        ])

        return HardwareCategory(
            id: "power", nameKey: "hwCatPower", subtitleKey: "hwSubPower",
            groups: [battery, adapter, settings, batterySettings])
    }

    /// 休眠计时:0 的口径是「从不」,不是 0 分钟(参考项目同此取舍)。
    private func sleepTimer(_ raw: String?) -> String? {
        guard let raw, let minutes = Int(raw) else { return nil }
        return minutes == 0 ? hwText("hwValueNever")
                : String(format: hwText("hwValueMinutes"), "\(minutes)")
    }

    // MARK: - 连接

    func connectivityCategory(_ items: [String: [[String: Any]]]) -> HardwareCategory {
        var groups: [HardwareFactGroup] = []

        // 主网络服务:SPNetworkDataType 会给出多个服务(本机实测 5 个),
        // 按服务顺序取排第一的那个作为「当前连接」。
        let services = (items["SPNetworkDataType"] ?? []).sorted {
            (text($0, "spnetwork_service_order") ?? "") < (text($1, "spnetwork_service_order") ?? "")
        }
        if let primary = services.first {
            let ipv4 = primary["IPv4"] as? [String: Any]
            let ipv6 = primary["IPv6"] as? [String: Any]
            groups.append(HardwareFactGroup(id: "networkInterface", name: .key("hwGroupNetworkInterface"), facts: [
                HardwareFact(label: .key("hwLabelService"), value: text(primary, "_name")),
                HardwareFact(label: .key("hwLabelInterface"), value: text(primary, "interface")),
                HardwareFact(label: .key("hwLabelType"), value: ethernetType(text(primary, "type"))),
                HardwareFact(label: .key("hwLabelHardwareAddress"), value: text(primary, "hardware")),
                HardwareFact(label: .key("hwLabelConfigMethod"), value: text(ipv4, "ConfigMethod")),
                HardwareFact(label: .key("hwLabelIpAddress"), value: (ipv4?["Addresses"] as? [String])?.first),
                HardwareFact(label: .key("hwLabelSubnetMask"), value: (ipv4?["SubnetMasks"] as? [String])?.first),
                HardwareFact(label: .key("hwLabelRouter"), value: text(ipv4, "Router")),
                HardwareFact(label: .key("hwLabelDns"), value: (ipv4?["ServerAddresses"] as? [String])?.joined(separator: " · ")),
                HardwareFact(label: .key("hwLabelIpv6"), value: (ipv6?["Addresses"] as? [String])?.first),
            ]))
        }

        // Wi-Fi:接口名/噪声/速率/信道这三项要在 CoreWLAN 上单独取,配置类信息
        // 走上面的网络服务组。
        if let interface = CWWiFiClient.shared().interface() {
            let channel = interface.wlanChannel()
            groups.append(HardwareFactGroup(id: "wifi", name: .key("hwGroupWifi"), facts: [
                HardwareFact(label: .key("hwLabelInterface"), value: interface.interfaceName),
                HardwareFact(label: .key("hwLabelPower"), value: interface.powerOn() ? "开" : "关"),
                HardwareFact(label: .key("hwLabelNetworkName"), value: interface.ssid()),
                HardwareFact(label: .key("hwLabelPhyMode"), value: phyMode(interface.activePHYMode())),
                HardwareFact(label: .key("hwLabelChannel"), value: channel.map { "\($0.channelNumber)" }),
                HardwareFact(label: .key("hwLabelBand"), value: channel.flatMap { bandName($0.channelBand) }),
                HardwareFact(label: .key("hwLabelChannelWidth"), value: channel.flatMap { channelWidth($0.channelWidth) }),
                HardwareFact(label: .key("hwLabelTransmitRate"), value: transmitRate(interface.transmitRate())),
                HardwareFact(label: .key("hwLabelSignalStrength"), value: rssi(interface.rssiValue())),
                HardwareFact(label: .key("hwLabelNoise"), value: rssi(interface.noiseMeasurement())),
                HardwareFact(label: .key("hwLabelSecurity"), value: securityName(interface.security())),
                HardwareFact(label: .key("hwLabelCountry"), value: interface.countryCode()),
            ]))
        }

        if let bluetooth = items["SPBluetoothDataType"]?.first {
            let controller = bluetooth["controller_properties"] as? [String: Any]
            let connected = bluetooth["device_connected"] as? [[String: Any]] ?? []
            let chipset = text(controller, "controller_chipset")
            let state = text(controller, "controller_state")
            // 沙盒渠道这里是空骨架:控制器读不到、设备数 0。整组不出现,免得渲染出
            // 「已连接 0 台」加一排 “—”;与传感器分类「读不到就整类隐藏」同一规则。
            if chipset != nil || state != nil || !connected.isEmpty {
                var facts: [HardwareFact] = [
                    HardwareFact(label: .key("hwLabelChipset"), value: chipset),
                    HardwareFact(label: .key("hwLabelStatus"), value: state),
                    HardwareFact(label: .key("hwLabelFirmwareVersion"), value: text(controller, "controller_firmwareVersion")),
                    HardwareFact(label: .key("hwLabelConnected"),
                                 value: String(format: hwText("hwValueCountUnits"), "\(connected.count)")),
                ]
                for device in connected {
                    let name = text(device, "device_address") ?? hwText("hwValueUnknownDevice")
                    let kind = text(device, "device_minorType") ?? text(device, "device_majorType")
                    let battery = text(device, "device_batteryLevelMain")
                    facts.append(HardwareFact(
                        label: .text(name),
                        value: [kind, battery.map { String(format: hwText("hwValueDeviceBattery"), $0) }]
                            .compactMap { $0 }.joined(separator: " · ")))
                }
                groups.append(HardwareFactGroup(id: "bluetooth", name: .key("hwGroupBluetooth"), facts: facts))
            }
        }

        // USB 设备挂在**总线项**的 `_items` 里(macOS 26+ 用 SPUSBHostDataType,
        // 旧系统才是 SPUSBDataType);没有设备的总线不单列。
        let buses = items["SPUSBHostDataType"] ?? []
        var usbFacts: [HardwareFact] = []
        for bus in buses {
            let devices = bus["_items"] as? [[String: Any]] ?? []
            for device in devices {
                let name = text(device, "_name") ?? hwText("hwValueUnknownUsbDevice")
                let speed = text(device, "USBDeviceKeyLinkSpeed")
                let vendor = text(device, "USBDeviceKeyVendorName")
                usbFacts.append(HardwareFact(
                    label: .text(name),
                    value: [vendor, speed].compactMap { $0 }.joined(separator: " · ")))
            }
        }
        if !usbFacts.isEmpty {
            groups.append(HardwareFactGroup(id: "usb", name: .keyed("hwGroupUsbCount", ["\(usbFacts.count)"]),
                                      facts: usbFacts))
        }

        // 雷雳端口在 `receptacle_N_tag` 字典里,每个端口一项。
        let busesThunderbolt = items["SPThunderboltDataType"] ?? []
        var portFacts: [HardwareFact] = []
        for bus in busesThunderbolt {
            let vendor = text(bus, "vendor_name_key")
            for key in bus.keys.filter({ $0.hasPrefix("receptacle_") && $0.hasSuffix("_tag") }).sorted() {
                guard let port = bus[key] as? [String: Any] else { continue }
                let id = text(port, "receptacle_id_key") ?? "—"
                let status = text(port, "receptacle_status_key")
                let speed = text(port, "current_speed_key")
                portFacts.append(HardwareFact(
                    label: .keyed("hwLabelPort", [id]),
                    value: [portStatus(status), speed, vendor].compactMap { $0 }.joined(separator: " · ")))
            }
        }
        if !portFacts.isEmpty {
            groups.append(HardwareFactGroup(id: "thunderbolt",
                                      name: .keyed("hwGroupThunderboltCount", ["\(portFacts.count)"]),
                                      facts: portFacts))
        }

        return HardwareCategory(
            id: "connectivity", nameKey: "hwCatConnectivity", subtitleKey: "hwSubConnectivity",
            groups: groups)
    }

    private func ethernetType(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw.lowercased().contains("airport") || raw.lowercased().contains("wi-fi")
            ? hwText("hwValueWireless") : raw
    }

    private func portStatus(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw.contains("no_device") ? hwText("hwValuePortEmpty") : hwText("hwValuePortConnected")
    }

    private func phyMode(_ mode: CWPHYMode) -> String? {
        switch mode {
        case .mode11ax: return "802.11ax"
        case .mode11ac: return "802.11ac"
        case .mode11n: return "802.11n"
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        default: return nil
        }
    }

    private func bandName(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return nil
        }
    }

    private func channelWidth(_ width: CWChannelWidth) -> String? {
        switch width {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        default: return nil
        }
    }

    /// 未关联网络时 `transmitRate()` / `rssiValue()` 返 0,不是有效读数。
    private func transmitRate(_ rate: Double) -> String? {
        guard rate > 0 else { return nil }
        return "\(Int(rate)) Mbps"
    }

    private func rssi(_ value: Int) -> String? {
        guard value < 0 else { return nil }
        return "\(value) dBm"
    }

    private func securityName(_ security: CWSecurity) -> String? {
        switch security {
        case .none: return hwText("hwValueSecurityOpen")
        case .WEP: return "WEP"
        case .wpaPersonal, .wpaPersonalMixed: return hwText("hwValueSecurityWpaPersonal")
        case .wpa2Personal: return hwText("hwValueSecurityWpa2Personal")
        case .personal: return hwText("hwValueSecurityWpa3Personal")
        case .wpaEnterprise, .wpaEnterpriseMixed: return hwText("hwValueSecurityWpaEnterprise")
        case .wpa2Enterprise: return hwText("hwValueSecurityWpa2Enterprise")
        case .enterprise: return hwText("hwValueSecurityWpa3Enterprise")
        default: return nil
        }
    }
}

// MARK: - 传感器（仅直连渠道）

extension HardwareInventoryReader {
    /// 温度域 + 风扇。**沙盒渠道 `SMCReader()` 直接返 nil**,整类不出现——
    /// 温度与风扇在 App Store 版没有公开替代源(热压力走 ProcessInfo.thermalState,
    /// 不属于硬件规格),这一点在数据源文档里已确认过。
    func sensorsCategory() -> HardwareCategory? {
        guard let reader = SMCReader() else { return nil }
        let inventory = reader.temperatureInventory()
        let fans = reader.allFans()
        guard !inventory.isEmpty || !fans.isEmpty else { return nil }

        var groups: [HardwareFactGroup] = inventory.map { domain, readings in
            // 「其他」域在本机有 60+ 个未归类键(新机型的 TPD*/TD*/TRD* 等),
            // 全铺出来只会淹没有语义的域:只给计数与最热。
            if domain == .other {
                return HardwareFactGroup(id: "domain",
                                      name: .keyed("hwGroupDomainCount", [hwText(domain.nameKey), "\(readings.count)"]), facts: [
                    HardwareFact(label: .key("hwLabelReadableKeys"),
                                 value: String(format: hwText("hwValueCountKeys"), "\(readings.count)")),
                    HardwareFact(label: .key("hwLabelHottest"), value: readings.first.map(temperature)),
                ])
            }
            // 其余域逐键列出——这是参考项目详情里的做法,也是「记录得非常详细」的落点。
            var facts = readings.map { HardwareFact(label: .text($0.key), value: temperature($0)) }
            facts.append(HardwareFact(label: .key("hwLabelHottest"), value: readings.first.map(temperature)))
            return HardwareFactGroup(id: "domain",
                                      name: .keyed("hwGroupDomainCount", [hwText(domain.nameKey), "\(readings.count)"]), facts: facts)
        }

        if !fans.isEmpty {
            var facts: [HardwareFact] = fans.map { fan in
                // 转速 0 是**真实读数**(风扇停转),不是读不到——两者必须分开,
                // 别沿用面板 maxFanRPM() 那种「0 与失败同归 nil」的降级口径。
                HardwareFact(label: .keyed("hwLabelFanIndex", ["\(fan.id + 1)"]),
                             value: fan.currentRPM == 0 ? hwText("hwValueFanStopped") : "\(fan.currentRPM) RPM")
            }
            facts.append(HardwareFact(label: .key("hwLabelFanMinRpm"), value: fans.first.map { "\($0.minRPM) RPM" }))
            facts.append(HardwareFact(label: .key("hwLabelFanMaxRpm"), value: fans.first.map { "\($0.maxRPM) RPM" }))
            facts.append(HardwareFact(label: .key("hwLabelFanCount"), value: "\(fans.count)"))
            groups.append(HardwareFactGroup(id: "fan", name: .key("hwGroupFan"), facts: facts))
        }

        return HardwareCategory(
            id: "sensors", nameKey: "hwCatSensors", subtitleKey: "hwSubSensors",
            groups: groups)
    }

    private func temperature(_ reading: SMCReader.TemperatureReading) -> String {
        String(format: "%.1f ℃", reading.celsius)
    }
}
