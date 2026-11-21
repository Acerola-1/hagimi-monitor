import SwiftUI

enum Rig: String, CaseIterable {
    case desk = "扩展桌面", mobile = "移动办公"
}

struct ScreenUnit: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let pixels: String
    let timing: String
    let port: String
    let adjustableContrast: Bool
    let adjustableVolume: Bool
}

struct Peripheral: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let type: String
    let parts: [BatteryPart]
}

struct BatteryPart: Identifiable {
    var id: String { name }
    let name: String
    let level: Int?
    var charging = false
}

extension Studio {
    var screens: [ScreenUnit] {
        let builtin = ScreenUnit(id:"builtin",name:"内建 Liquid Retina XDR",shortName:"内建",pixels:"3024 × 1964",timing:"120 Hz",port:"内建 · P3",adjustableContrast:false,adjustableVolume:false)
        guard rig == .desk else { return [builtin] }
        return [builtin,
                ScreenUnit(id:"dell",name:"DELL U2723QE",shortName:"DELL",pixels:"3840 × 2160",timing:"60 Hz",port:"USB-C · P3",adjustableContrast:true,adjustableVolume:false),
                ScreenUnit(id:"lg",name:"LG 27UP850",shortName:"LG",pixels:"3840 × 2160",timing:"60 Hz",port:"DisplayPort · P3",adjustableContrast:true,adjustableVolume:true)]
    }
    var devices: [Peripheral] {
        let buds = Peripheral(name:"AirPods Pro",icon:"airpodspro",type:"入耳式耳机",parts:[
            BatteryPart(name:"左耳",level:82),BatteryPart(name:"右耳",level:76),
            BatteryPart(name:"充电盒",level:rig == .desk ? 48 : nil,charging:rig == .desk)])
        guard rig == .desk else { return [buds] }
        return [buds,
                Peripheral(name:"妙控鼠标",icon:"computermouse",type:"鼠标",parts:[BatteryPart(name:"电池",level:18)]),
                Peripheral(name:"Keychron K3",icon:"keyboard",type:"键盘",parts:[BatteryPart(name:"电池",level:92,charging:true)]),
                Peripheral(name:"Xbox Wireless Controller",icon:"gamecontroller",type:"手柄",parts:[BatteryPart(name:"电池",level:nil)])]
    }
    func rpm(_ index: Int, at tick: Int) -> Int {
        if load == .idle { return 0 }
        return 1180 + Int(cpu(tick) * (index == 0 ? 29 : 31)) + index * 83
    }
    func screenBinding(_ screen: ScreenUnit, _ control: String) -> Binding<Double> {
        let key = screen.id + "." + control
        let initial: Double = switch control {
        case "亮度": screen.id == "builtin" ? 64 : screen.id == "lg" ? 36 : 52
        case "对比度": 70
        default: 28
        }
        return Binding(get:{ self.screenValues[key] ?? initial },set:{ self.screenValues[key] = $0 })
    }
}

struct EquipmentDetail: View {
    @ObservedObject var model: Studio
    let module: Module
    private var ink: Ink { model.ink }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            switch module {
            case .fan: fans
            case .display: ForEach(model.screens) { screen in display(screen) }
            case .bluetooth: ForEach(model.devices) { device in peripheral(device) }
            default: EmptyView()
            }
        }
    }
    private var fans: some View {
        HStack(spacing:7) {
            ForEach(0..<2) { i in
                let rpm = model.rpm(i, at:model.second)
                VStack(alignment:.leading,spacing:5) {
                    Label(i == 0 ? "左侧风扇" : "右侧风扇",systemImage:"fanblades.fill").foregroundStyle(ink.tint(.fan))
                    HStack(alignment:.firstTextBaseline,spacing:3) {
                        Text(String(rpm)).font(.system(size:19,weight:.semibold,design:.rounded))
                        Text("RPM").font(.system(size:9))
                    }
                    Trace(samples:(model.second-35...model.second).map{Double(model.rpm(i,at:$0))/55},color:ink.tint(.fan)).frame(height:16)
                    Text(rpm == 0 ? "已停转" : "运行中").foregroundStyle(.secondary)
                }.font(.caption).monospacedDigit().padding(9).frame(maxWidth:.infinity,alignment:.leading).background(tile)
            }
        }
    }
    private func display(_ item:ScreenUnit) -> some View {
        let open = model.openScreens.contains(item.id)
        return VStack(alignment:.leading,spacing:6) {
            Button {
                if open { model.openScreens.remove(item.id) } else { model.openScreens.insert(item.id) }
            } label:{
                HStack {
                    Image(systemName:item.id == "builtin" ? "laptopcomputer":"display").foregroundStyle(ink.accent)
                    VStack(alignment:.leading,spacing:2) {
                        Text(item.name).fontWeight(.semibold)
                        Text(item.pixels+" · "+item.timing).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(model.screenBinding(item,"亮度").wrappedValue))%").monospacedDigit()
                    Image(systemName:open ? "chevron.down":"chevron.right").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                Divider()
                Text(item.port).font(.caption2).foregroundStyle(.secondary)
                slider("亮度",item)
                if item.adjustableContrast { slider("对比度",item) }
                if item.adjustableVolume { slider("音量",item) }
            }
        }.font(.caption).padding(9).background(tile)
    }
    private func slider(_ name:String,_ item:ScreenUnit) -> some View {
        let binding = model.screenBinding(item,name)
        return HStack {
            Text(name).foregroundStyle(.secondary).frame(width:34,alignment:.leading)
            Slider(value:binding,in:0...100,step:1).controlSize(.small).tint(ink.accent).accessibilityLabel(item.name+name)
            Text("\(Int(binding.wrappedValue))%").monospacedDigit().frame(width:33)
        }
    }
    private func peripheral(_ item:Peripheral) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack {
                Image(systemName:item.icon).foregroundStyle(ink.tint(.bluetooth)).frame(width:21)
                VStack(alignment:.leading,spacing:1) {
                    Text(item.name).fontWeight(.semibold)
                    Text(item.type).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if item.parts.count == 1 { battery(item.parts[0]) }
            }
            if item.parts.count > 1 {
                Divider()
                HStack(spacing:12) { ForEach(item.parts) { part in
                    VStack(alignment:.leading,spacing:3) {
                        Text(part.name).font(.caption2).foregroundStyle(.secondary)
                        battery(part)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                } }
            }
        }.font(.caption).padding(9).background(tile)
    }
    private func battery(_ part:BatteryPart) -> some View {
        HStack(spacing:3) {
            if part.charging { Image(systemName:"bolt.fill").font(.caption2).foregroundStyle(ink.e) }
            if let level = part.level {
                Image(systemName:"battery.\(min(4,Int((Double(level)/25).rounded()))*25)percent").foregroundStyle(level <= 20 ? Color.orange : ink.e)
                Text("\(level)%").monospacedDigit()
            } else { Text("未上报").foregroundStyle(.secondary) }
        }.fixedSize()
    }
    private var tile: some View { RoundedRectangle(cornerRadius:7).fill(Color.primary.opacity(0.055)) }
}
