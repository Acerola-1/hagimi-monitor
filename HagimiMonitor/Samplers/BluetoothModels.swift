import Foundation

/// 蓝牙设备类别,用于面板图标映射。来源优先级:CoD(IOBluetooth)>
/// device_minorType(system_profiler)>GAP Appearance(GATT 自报)>
/// 名称关键词推断;均未知归 other,不猜测设备形态。
nonisolated enum BluetoothDeviceType: Equatable, Sendable {
    case mouse
    case keyboard
    case headphones
    case headset
    case gamepad
    case trackpad
    case speaker
    case phone
    case tablet
    case watch
    case computer
    case other

    init(minorType: String?) {
        switch minorType?.lowercased() {
        case "mouse": self = .mouse
        case "keyboard": self = .keyboard
        case "headphones", "earbuds", "airpods": self = .headphones
        case "headset": self = .headset
        case "gamepad", "joystick", "controller": self = .gamepad
        case "trackpad": self = .trackpad
        case "speaker": self = .speaker
        case "phone", "mobilephone", "smartphone", "cellular": self = .phone
        case "tablet", "pad", "ipad": self = .tablet
        case "watch", "smartwatch", "wristwatch", "applewatch": self = .watch
        case "computer", "laptop", "desktop", "mac", "macbook": self = .computer
        default: self = .other
        }
    }

    /// 蓝牙 CoD(Class of Device)映射,取 IOBluetoothDevice 的
    /// deviceClassMajor/deviceClassMinor 字段:
    /// - Computer(major 0x01): minor 0x07 为平板电脑(Tablet),其余归 computer;
    /// - Phone(major 0x02): 手机类统一归 phone;
    /// - Audio/Video(major 0x04): 扬声器/音箱(0x05 Loudspeaker / 0x08 Car / 0x0A HiFi)
    ///   归 speaker;耳机类统一归 headphones;
    /// - Peripheral(major 0x05): 依据 SDK 常量 kBluetoothDeviceClassMinorPeripheral1*
    ///   (掩码 0x30:Keyboard 0x10 / Pointing 0x20 / Combo 0x30)与
    ///   kBluetoothDeviceClassMinorPeripheral2*(掩码 0x0F:Joystick 0x01 / Gamepad 0x02 / Digitizer 0x05);
    /// - Wearable(major 0x07): 腕表(0x01 Wristwatch)归 watch;
    /// - 其余 major(misc 等)无稳定形态信息,返回 nil。
    static func fromClassOfDevice(major: Int, minor: Int) -> BluetoothDeviceType? {
        switch major {
        case 0x01:
            if minor == 0x07 {
                return .tablet
            }
            return .computer
        case 0x02:
            return .phone
        case 0x04:
            switch minor {
            case 0x05, 0x08, 0x0A: return .speaker
            default: return .headphones
            }
        case 0x05:
            let peripheral1 = minor & 0x30
            if peripheral1 == 0x10 {
                return .keyboard
            } else if peripheral1 == 0x20 || peripheral1 == 0x30 {
                return .mouse
            }
            let peripheral2 = minor & 0x0F
            if peripheral2 == 0x01 || peripheral2 == 0x02 {
                return .gamepad
            } else if peripheral2 == 0x05 {
                return .trackpad
            }
            return nil
        case 0x07:
            if minor == 0x01 {
                return .watch
            }
            return nil
        default:
            return nil
        }
    }

    /// GAP Appearance(GATT 0x2A01,uint16:高 10 位类别、低 6 位子类)映射,
    /// 值表出自 SIG Assigned Numbers(appearance_values.yaml)。仅映射本应用
    /// 有图标语言的形态,其余返回 nil 由调用方沿名称推断兜底。
    static func fromAppearance(_ appearance: UInt16) -> BluetoothDeviceType? {
        switch appearance {
        case 0x0040: return .phone                       // Generic Phone
        case 0x0087: return .tablet                      // Tablet
        case 0x0080...0x008F: return .computer            // Computer 子类，含 Laptop 0x0083
        case 0x00C0...0x00C2: return .watch              // Generic Watch / Sports Watch / Smartwatch
        case 0x03C1: return .keyboard                    // HID:Keyboard
        case 0x03C2: return .mouse                       // HID:Mouse
        case 0x03C3, 0x03C4: return .gamepad             // HID:Joystick/Gamepad
        case 0x03C5, 0x03C9: return .trackpad            // HID:Digitizer Tablet / Touchpad
        case 0x0841...0x0845: return .speaker            // Audio Sink:各类扬声器/Speakerphone
        case 0x0941, 0x0943, 0x0944, 0x0945, 0x0946:
            return .headphones                           // Wearable Audio:Earbud/Headphones/Neck Band/L/R
        case 0x0942: return .headset                     // Wearable Audio:Headset
        default: return nil
        }
    }

    /// 无 CoD/设备类型元数据时,按名称关键词推断图标;推不出保持 other。
    /// 优先级:CoD → profiler 元数据 → GAP Appearance → 名称推断(本方法)。
    /// 名称关键词只作最后兜底,不为无法确认的设备强行猜测类型。
    /// 支持中/英/日三语关键词,覆盖常见品牌型号。
    static func inferred(fromName name: String) -> BluetoothDeviceType {
        let lowered = name.lowercased()
        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { lowered.contains($0) }
        }
        // 耳机词包含 phone，必须先识别具体音频形态再判断通用手机关键词。
        if containsAny(["headphone", "earbud", "buds", "headset", "airpods", "powerbeats", "beats", "耳机", "耳夹", "耳麦", "イヤホン", "ヘッドホン", "ヘッドセット", "wh-", "wf-", "galaxy buds", "freebuds"]) { return .headphones }
        // 手机:英/中/日
        if containsAny(["iphone", "phone", "手机", "スマートフォン"]) { return .phone }
        // 平板:英/中/日
        if containsAny(["ipad", "tablet", "平板", "タブレット"]) { return .tablet }
        // 手表:英/中/日
        if containsAny(["apple watch", "watch", "手表", "手环", "ウオッチ", "バンド"]) { return .watch }
        // 电脑:英/中/日
        if containsAny(["macbook", "imac", "mac mini", "mac studio", "mac pro", "laptop", "desktop", "电脑", "计算机", "パソコン"]) { return .computer }
        // 鼠标:英/中/日
        if containsAny(["mouse", "鼠标", "マウス"]) { return .mouse }
        // 键盘:英/中/日
        if containsAny(["keyboard", "键盘", "キーボード"]) { return .keyboard }
        // 触控板:英/中/日
        if containsAny(["trackpad", "触控板", "タッチパッド"]) { return .trackpad }
        // 手柄:英/中/日(含常见品牌型号关键词)
        if containsAny(["gamepad", "controller", "joystick", "手柄", "コントローラー", "ゲームパッド", "xbox", "dualshock", "dualsense"]) { return .gamepad }
        // 音箱:英/中/日
        if containsAny(["speaker", "音箱", "音响", "スピーカー", "soundlink", "echo", "homepod"]) { return .speaker }
        return .other
    }

    /// SF Symbols 无蓝牙通用符号,按设备形态取图标。
    var symbol: String {
        switch self {
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .headphones, .headset: return "headphones"
        case .gamepad: return "gamecontroller"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .speaker: return "hifispeaker"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .computer: return "laptopcomputer"
        case .other: return "questionmark.circle"
        }
    }
}

/// 蓝牙设备电池部件(用于 AirPods 左右耳、充电盒等分体式设备)。
nonisolated struct BluetoothBatteryComponent: Equatable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case single
        case left
        case right
        case `case`
    }
    let kind: Kind
    let level: Int
    var isCharging: Bool? = nil
}

/// 电量来源随读数传递，区分私有接口的可疑零值与设备或电源树上报的真实零值。
nonisolated enum BluetoothBatterySource: Equatable, Sendable {
    case ioBluetooth
    case profiler
    case powerSource
    case gatt
    case advertisement
}

/// 单台系统连接或有效广播确认的已配对蓝牙设备。batteryLevel 为 nil 表示未上报电量
/// (走厂商私有协议,macOS 蓝牙栈收不到),不伪造读数。
nonisolated struct BluetoothDeviceInfo: Identifiable, Equatable, Sendable {
    /// 归一化 MAC(去分隔符小写)或 "ble-UUID"。跨数据源身份关联的锚点。
    let address: String
    let name: String
    let type: BluetoothDeviceType
    /// 0-100;nil = 未上报。
    let batteryLevel: Int?
    /// system_profiler 的 device_services(如 "HID BLE" / "HFP AVRCP A2DP GATT ACL")。
    var services: String? = nil
    /// 多部件电量(如左耳/右耳/充电仓)。单体设备为空。
    var components: [BluetoothBatteryComponent] = []
    /// 充电状态(来自 pmset 或系统电源树)。nil = 未知。
    var isCharging: Bool? = nil
    /// 厂商名称(来自系统电源树或外设信息)。
    var vendorName: String? = nil
    /// 型号名称(来自系统电源树或外设信息)。
    var modelName: String? = nil
    var batterySource: BluetoothBatterySource? = nil
    /// 电源树的 UUID 身份；与 MAC 分开，防止 UUID 被误当作地址。
    var accessoryIdentifier: UUID? = nil

    var id: String { address }
}

/// system_profiler 探针执行结果:区分「成功空清单」与「执行失败」。
/// 超时 / 启动失败 / 异常 JSON / 沙盒空骨架均为 failure,调用方保留
/// 最近一次成功快照;成功返回空清单时才允许清空 profiler 设备。
nonisolated enum ProbeOutcome: Equatable, Sendable {
    case success(controllerOn: Bool?, devices: [BluetoothDeviceInfo])
    case failure
}

/// 身份绑定记录:BLE UUID + 版本 + 最近召回时间。
/// version 预留用于未来冲突检测(同一 MAC 匹配到不同 UUID 时递增);
/// lastSeenAt 用于失效判定:长期未在 BLE 快照中召回则移除绑定,
/// 避免废弃绑定永久残留。临时离线(如设备存放、出差)不触发移除。
nonisolated struct BindingRecord: Codable, Equatable, Sendable {
    let uuid: String
    var version: Int
    var lastSeenAt: Date
}

/// device_batteryLevel* 解析:
/// - 单值形态("63%" / "63")直接取该值;
/// - 多分量形态("Left: 67%, Right: 65%, Case: 89%")取最小值代表设备电量;
/// - macOS 26 起 JSON 键为 device_batteryLevelMain,旧版为 device_batteryLevel,
///   多单体耳机另有 Left/Right/Case 分量，主电量由调用方排除充电仓后聚合。
/// 优先取带 % 后缀的数字(排除固件号等无关数字);无法解析返回 nil。
nonisolated enum BluetoothBatteryParser: Sendable {
    static func batteryLevel(from raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let tokens = numericTokens(in: raw)
        let percent = tokens.filter { $0.hasPercent }.map(\.value)
        if !percent.isEmpty {
            return percent.filter { (0...100).contains($0) }.min()
        }
        return tokens.map(\.value).filter { (0...100).contains($0) }.min()
    }

    /// 从原始文本中解析出左右耳与充电盒等各部件电量。
    static func components(from raw: String?) -> [BluetoothBatteryComponent] {
        guard let raw, !raw.isEmpty else { return [] }
        var result: [BluetoothBatteryComponent] = []
        let parts = raw.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard let level = batteryLevel(from: trimmed) else { continue }
            if lower.contains("left") {
                result.append(BluetoothBatteryComponent(kind: .left, level: level))
            } else if lower.contains("right") {
                result.append(BluetoothBatteryComponent(kind: .right, level: level))
            } else if lower.contains("case") {
                result.append(BluetoothBatteryComponent(kind: .case, level: level))
            }
        }
        return result
    }

    /// 扫描字符串中的数字段,记录其后是否紧跟 %。
    private static func numericTokens(in raw: String) -> [(value: Int, hasPercent: Bool)] {
        var tokens: [(value: Int, hasPercent: Bool)] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
                continue
            }
            if let value = Int(current) {
                tokens.append((value, character == "%"))
            }
            current = ""
        }
        if let value = Int(current) {
            tokens.append((value, false))
        }
        return tokens
    }
}

/// 解析 `pmset -g accps -xml` 输出的外设电源信息(纯函数,便于单测)。
/// 参考 Stats 项目中 pmset 外设电源采集逻辑,覆盖直接与系统连接的 BLE/HID 外设及分体耳机。
nonisolated enum PMSetAccessoryParser: Sendable {
    private struct Entry {
        let identifier: String
        let name: String
        let group: String?
        let part: String?
        let category: String?
        let capacity: Int?
        let charging: Bool?
        let transport: String?
        let components: [BluetoothBatteryComponent]
    }

    static func parse(xmlData: Data) -> [BluetoothDeviceInfo] {
        guard !xmlData.isEmpty, let text = String(data: xmlData, encoding: .utf8) else {
            return []
        }
        let chunks = text.components(separatedBy: "<?xml")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "<?xml" + $0 }

        var entries: [Entry] = []
        for chunk in chunks {
            guard let data = chunk.data(using: .utf8),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
                continue
            }
            // 排除内建主电池(非蓝牙外设)
            if (plist["Type"] as? String) == "InternalBattery" {
                continue
            }
            guard let accessoryId = plist["Accessory Identifier"] as? String, !accessoryId.isEmpty,
                  let name = plist["Name"] as? String,
                  !name.isEmpty else {
                continue
            }
            let parts = (plist["Combined Parts"] as? [[String: Any]] ?? []).compactMap { part -> BluetoothBatteryComponent? in
                guard let id = part["Part Identifier"] as? String,
                      let level = validCapacity(part["Current Capacity"]) else { return nil }
                return BluetoothBatteryComponent(kind: componentKind(id), level: level, isCharging: chargingState(part))
            }
            entries.append(Entry(
                identifier: accessoryId, name: name,
                group: (plist["Group Identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                part: plist["Part Identifier"] as? String,
                category: plist["Accessory Category"] as? String,
                capacity: validCapacity(plist["Current Capacity"]),
                charging: chargingState(plist),
                transport: plist["Transport Type"] as? String,
                components: parts
            ))
        }

        // 同组的耳机和充电盒可拥有不同地址；先聚合部件，设备合并时只发布一个身份。
        var groups: [[Entry]] = []
        var groupIndices: [String: Int] = [:]
        for entry in entries {
            if let group = entry.group, let index = groupIndices[group] {
                groups[index].append(entry)
            } else {
                if let group = entry.group { groupIndices[group] = groups.count }
                groups.append([entry])
            }
        }
        return groups.map(makeDevice)
    }

    private static func makeDevice(_ entries: [Entry]) -> BluetoothDeviceInfo {
        let primary = entries.first { $0.part?.lowercased() == "combined" }
            ?? entries.first { !isCase($0) }
            ?? entries[0]
        var parts: [BluetoothBatteryComponent.Kind: BluetoothBatteryComponent] = [:]
        for entry in entries {
            for component in entry.components { parts[component.kind] = component }
        }
        // 独立的 Case 记录比 Combined Parts 中的盒缓存更直接，不受报告顺序影响。
        for entry in entries {
            guard let level = entry.capacity else { continue }
            if isCase(entry) {
                parts[.case] = BluetoothBatteryComponent(kind: .case, level: level, isCharging: entry.charging)
            } else if let part = entry.part, part.lowercased() != "combined" {
                let kind = componentKind(part)
                parts[kind] = BluetoothBatteryComponent(kind: kind, level: level, isCharging: entry.charging)
            }
        }
        let components = [BluetoothBatteryComponent.Kind.left, .right, .case, .single].compactMap { parts[$0] }
        let level = components.filter { $0.kind != .case }.map(\.level).min()
            ?? (isCase(primary) ? nil : primary.capacity)
        let accessoryUUID = UUID(uuidString: primary.group ?? primary.identifier)
        let normalizedAddress = accessoryUUID.map { "ble-" + $0.uuidString }
            ?? primary.identifier.lowercased().filter(\.isHexDigit)
        return BluetoothDeviceInfo(
            address: normalizedAddress.isEmpty ? primary.identifier : normalizedAddress,
            name: primary.name,
            type: deviceType(category: primary.category, name: primary.name),
            batteryLevel: level,
            services: primary.transport,
            components: components,
            isCharging: primary.charging,
            batterySource: level == nil ? nil : .powerSource,
            accessoryIdentifier: accessoryUUID
        )
    }

    private static func validCapacity(_ value: Any?) -> Int? {
        guard let level = value as? Int, (0...100).contains(level) else { return nil }
        return level
    }

    private static func chargingState(_ properties: [String: Any]) -> Bool? {
        if let charging = properties["Is Charging"] as? Bool { return charging }
        switch properties["Power Source State"] as? String {
        case "AC Power": return true
        case "Battery Power": return false
        default: return nil
        }
    }

    private static func componentKind(_ identifier: String) -> BluetoothBatteryComponent.Kind {
        let lower = identifier.lowercased()
        if lower.contains("left") { return .left }
        if lower.contains("right") { return .right }
        if lower.contains("case") { return .case }
        return .single
    }

    private static func isCase(_ entry: Entry) -> Bool {
        entry.part?.lowercased() == "case" || entry.category?.lowercased().contains("case") == true
    }

    private static func deviceType(category: String?, name: String) -> BluetoothDeviceType {
        if let category = category?.lowercased() {
            if category.contains("keyboard") { return .keyboard }
            if category.contains("trackpad") { return .trackpad }
            if category.contains("mouse") || category.contains("pointing") { return .mouse }
            if category.contains("case") || category.contains("audio") || category.contains("headphone") { return .headphones }
            if category.contains("gamepad") || category.contains("joystick") { return .gamepad }
        }
        return BluetoothDeviceType.inferred(fromName: name)
    }
}
