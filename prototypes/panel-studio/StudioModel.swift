import SwiftUI
import Combine

enum Style: String, CaseIterable { case graphite = "石墨", balance = "平衡", vivid = "活力" }
enum Load: String, CaseIterable { case idle = "轻载", work = "日常", build = "编译" }
enum Module: String, CaseIterable, Identifiable {
    case cpu = "CPU", gpu = "GPU", memory = "内存", disk = "磁盘", network = "网络", power = "电源", fan = "风扇", display = "显示器", bluetooth = "蓝牙"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .cpu: "cpu"; case .gpu: "square.3.layers.3d"; case .memory: "memorychip"; case .disk: "internaldrive"; case .network: "wave.3.right"; case .power: "bolt.fill"; case .fan: "fan"; case .display: "display"; case .bluetooth: "headphones"
        }
    }
}

extension Color {
    init(rgb: Int) {
        self.init(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

struct Ink {
    let style: Style
    let dark: Bool
    var accent: Color {
        switch style {
        case .graphite: Color(rgb: dark ? 0xA9CEDA : 0x26556B)
        case .balance: Color(rgb: dark ? 0xA1C4FF : 0x3C65A2)
        case .vivid: Color(rgb: dark ? 0xB3ACFF : 0x6948B7)
        }
    }
    var p: Color { style == .vivid ? Color(rgb: dark ? 0xBD9DFF : 0x744AC0) : Color(rgb: dark ? 0x91B9FF : 0x315FA8) }
    var e: Color { Color(rgb: dark ? 0x75D9C1 : 0x177666) }
    var track: Color { Color(rgb: dark ? 0x697983 : 0xADBCC1) }
    var line: Color { Color.primary.opacity(dark ? 0.17 : 0.13) }
    func tint(_ mod: Module) -> Color {
        guard style != .graphite else { return mod == .cpu ? p : accent }
        switch mod {
        case .cpu: return p
        case .gpu: return Color(rgb: dark ? 0xE2A3DA : 0x924184)
        case .memory, .network: return e
        case .disk, .power: return Color(rgb: dark ? 0xF3C583 : 0x96651F)
        default: return accent
        }
    }
}

@MainActor final class Studio: ObservableObject {
    @Published var style: Style = .graphite
    @Published var dark = true
    @Published var width = 340
    @Published var load: Load = .work
    @Published var playing = true
    @Published var second = 60
    @Published var expanded: Set<Module> = []
    @Published var rig: Rig = .desk
    @Published var screenValues = [String:Double]()
    @Published var openScreens: Set<String> = ["dell"]
    @Published var health = false
    @Published var allProcesses = false
    
    private var timer: AnyCancellable?
    init() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, self.playing else { return }
            self.second += 1
        }
    }
    var ink: Ink { Ink(style: style, dark: dark) }

    func core(_ index: Int, at tick: Int) -> Double {
        let base: Double
        switch load {
        case .idle: base = index < 6 ? 3 : 9
        case .work: base = index < 6 ? 43 : 24
        case .build: base = index < 6 ? 94 : 66
        }
        let t = Double(tick), i = Double(index)
        let wave = 10 * sin(t * 0.32 + i * 0.8) + 8 * cos(t * 0.14 + i / 7) + (index < 6 ? 8 : 3) * sin(t * 0.83)
        return min(100, max(0, base + wave * (load == .idle ? 0.45 : 1)))
    }
    func cpu(_ tick: Int) -> Double { (0..<10).reduce(0.0) { $0 + core($1, at: tick) } / 10 }
    func level(_ module: Module, _ tick: Int) -> Double {
        if module == .cpu { return cpu(tick) }
        let base: Double
        switch module {
        case .gpu: base = load == .build ? 53 : 16
        case .network: base = load == .idle ? 8 : 45
        default: base = 30
        }
        return max(1, min(99, base + 9 * sin(Double(tick) * 0.37) + 6 * cos(Double(tick) * 0.7)))
    }
    var cpuValue: Int { Int(cpu(second).rounded()) }
    var temp: Int { 37 + cpuValue / 2 }
    var fans: Int { max(rpm(0,at:second),rpm(1,at:second)) }
    var watts: Int { 8 + cpuValue / 2 }
    var memory: Double { load == .build ? 25.6 : load == .idle ? 8.2 : 17.4 }
    var download: String { String(format: "%.1f", level(.network, second) / 4) }
    func reading(_ mod: Module) -> String {
        switch mod {
        case .cpu: "\(cpuValue)%"
        case .gpu: "\(Int(level(.gpu, second)))%"
        case .memory: String(format: "%.1f GB", memory)
        case .disk: "558 GB 可用"
        case .network: "↓ \(download) MB/s"
        case .power: "\(watts) W"
        case .fan: "\(fans) RPM"
        case .display: "\(screens.count) 台"
        case .bluetooth: "\(devices.count) 台"
        }
    }
    func toggle(_ module: Module) {
        if expanded.contains(module) { expanded.remove(module) } else { expanded.insert(module) }
    }
}
