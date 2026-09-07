import Foundation

/// 蓝牙设备类别,用于面板图标映射。来源优先级:CoD(IOBluetooth)>
/// device_minorType(system_profiler)>GAP Appearance(GATT 自报)>
/// 名称关键词推断;均未知归 other,不猜测设备形态。
enum BluetoothDeviceType: Equatable, Sendable {
    case mouse
    case keyboard
    case headphones
    case headset
    case gamepad
    case trackpad
    case speaker
    case other

    init(minorType: String?) {
        switch minorType?.lowercased() {
        case "mouse": self = .mouse
        case "keyboard": self = .keyboard
        case "headphones", "earbuds": self = .headphones
        case "headset": self = .headset
        case "gamepad", "joystick": self = .gamepad
        case "trackpad": self = .trackpad
        case "speaker": self = .speaker
        default: self = .other
        }
    }

    /// 蓝牙 CoD(Class of Device)映射,取 IOBluetoothDevice 的
    /// deviceClassMajor/deviceClassMinor 字段:
    /// - Audio/Video(major 0x04):扬声器/音箱(0x05 Loudspeaker / 0x08 Car / 0x0A HiFi)
    ///   归 speaker;耳机类统一归 headphones;
    /// - Peripheral(major 0x05):依据 SDK 常量 kBluetoothDeviceClassMinorPeripheral1*
    ///   (掩码 0x30:Keyboard 0x10 / Pointing 0x20 / Combo 0x30)与
    ///   kBluetoothDeviceClassMinorPeripheral2*(掩码 0x0F:Joystick 0x01 / Gamepad 0x02);
    /// - 其余 major(misc/computer 等)无稳定形态信息,返回 nil。
    static func fromClassOfDevice(major: Int, minor: Int) -> BluetoothDeviceType? {
        switch major {
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
        case 0x03C1: return .keyboard            // HID:Keyboard
        case 0x03C2: return .mouse               // HID:Mouse
        case 0x03C3, 0x03C4: return .gamepad     // HID:Joystick/Gamepad
        case 0x03C5: return .trackpad            // HID:Digitizer Tablet
        case 0x0841, 0x0842, 0x0843, 0x0844, 0x0845:
            return .speaker                      // Audio Sink:各类扬声器/Speakerphone
        case 0x0941, 0x0943, 0x0944, 0x0945, 0x0946:
            return .headphones                   // Wearable Audio:Earbud/Headphones/Neck Band/L/R
        case 0x0942: return .headset             // Wearable Audio:Headset
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
        // 鼠标:英/中/日
        if containsAny(["mouse", "鼠标", "マウス"]) { return .mouse }
        // 键盘:英/中/日
        if containsAny(["keyboard", "键盘", "キーボード"]) { return .keyboard }
        // 触控板:英/中/日
        if containsAny(["trackpad", "触控板", "タッチパッド"]) { return .trackpad }
        // 手柄:英/中/日(含常见品牌型号关键词)
        if containsAny(["gamepad", "controller", "joystick", "手柄", "コントローラー", "ゲームパッド", "xbox", "dualshock", "dualsense"]) { return .gamepad }
        // 耳机:英/中/日(含常见品牌型号关键词)
        if containsAny(["headphone", "earbud", "buds", "headset", "airpods", "耳机", "耳夹", "耳麦", "イヤホン", "ヘッドホン", "ヘッドセット", "wh-", "wf-", "galaxy buds", "freebuds"]) { return .headphones }
        // 音箱:英/中/日
        if containsAny(["speaker", "音箱", "音响", "スピーカー"]) { return .speaker }
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
        case .other: return "questionmark.circle"
        }
    }
}

/// 单台已连接蓝牙设备。batteryLevel 为 nil 表示设备未上报电量
/// (走厂商私有协议,macOS 蓝牙栈收不到),不伪造读数。
struct BluetoothDeviceInfo: Identifiable, Equatable {
    /// 归一化 MAC(去分隔符小写)或 "ble-UUID"。跨数据源身份关联的锚点。
    let address: String
    let name: String
    let type: BluetoothDeviceType
    /// 0-100;nil = 未上报。
    let batteryLevel: Int?
    /// system_profiler 的 device_services(如 "HID BLE" / "HFP AVRCP A2DP GATT ACL")。
    var services: String? = nil

    var id: String { address }
}

/// system_profiler 探针执行结果:区分「成功空清单」与「执行失败」。
/// 超时 / 启动失败 / 异常 JSON / 沙盒空骨架均为 failure,调用方保留
/// 最近一次成功快照;成功返回空清单时才允许清空 profiler 设备。
enum ProbeOutcome: Equatable {
    case success(controllerOn: Bool?, devices: [BluetoothDeviceInfo])
    case failure
}

/// 身份绑定记录:BLE UUID + 版本 + 最近召回时间。
/// version 预留用于未来冲突检测(同一 MAC 匹配到不同 UUID 时递增);
/// lastSeenAt 用于失效判定:长期未在 BLE 快照中召回则移除绑定,
/// 避免废弃绑定永久残留。临时离线(如设备存放、出差)不触发移除。
struct BindingRecord: Codable, Equatable {
    let uuid: String
    var version: Int
    var lastSeenAt: Date
}

/// device_batteryLevel* 解析:
/// - 单值形态("63%" / "63")直接取该值;
/// - 多分量形态("Left: 67%, Right: 65%, Case: 89%")取最小值代表设备电量;
/// - macOS 26 起 JSON 键为 device_batteryLevelMain,旧版为 device_batteryLevel,
///   多单体耳机另有 Left/Right/Case 分量——调用方把全部变体拼接后交本解析器。
/// 优先取带 % 后缀的数字(排除固件号等无关数字);无法解析返回 nil。
enum BluetoothBatteryParser {
    static func batteryLevel(from raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let tokens = numericTokens(in: raw)
        let percent = tokens.filter { $0.hasPercent }.map(\.value)
        if !percent.isEmpty {
            return percent.filter { (0...100).contains($0) }.min()
        }
        return tokens.map(\.value).filter { (0...100).contains($0) }.min()
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
