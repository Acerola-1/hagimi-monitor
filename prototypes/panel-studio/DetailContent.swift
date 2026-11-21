import SwiftUI

struct Ranking: View {
    let module: Module
    @ObservedObject var model: Studio
    @State private var open = true
    private var names: [String] {
        switch module {
        case .cpu: [model.load == .build ? "swift-frontend" : "WindowServer","Xcode","Safari","HagimiMonitor","Finder"]
        case .gpu: ["WindowServer","Safari","Preview","Photos","Core Animation"]
        case .memory: ["Xcode","Safari","Simulator","WindowServer","Mail"]
        case .disk: ["Xcode","mdworker","Safari","Finder","backupd"]
        default: ["Safari","nsurlsessiond","Mail","Music","mDNSResponder"]
        }
    }
    private func value(_ i:Int)->String {
        switch module {
        case .cpu: return "\(max(1,model.cpuValue*2/(i+1)))%"
        case .gpu: return "\(Int(model.level(.gpu, model.second))/(i+1))%"
        case .memory: return ["3.4 GB","2.6 GB","1.8 GB","628 MB","382 MB"][i]
        case .disk: return ["24 / 9","8 / 4","2 / 3","1 / 1","1 / 1"][i]+" MB/s"
        default: return ["1.2 / "+String(format:"%.1f",Double(model.download)!*0.6),"0.5 / 0.6","0.2 / 0.3","0.1 / 0.2","0.1 / 0.1"][i]+" MB/s"
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Button { open.toggle() } label:{
                HStack { Text("进程排行"); Spacer()
                    Text(module == .disk ? "读取 / 写入" : module == .network ? "上传 / 下载" : "前 5 项")
                    Image(systemName:open ? "chevron.down":"chevron.right")
                }.font(.caption2).foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                ForEach(Array(names.enumerated()),id:\.offset) { i,name in
                    HStack(spacing:6) {
                        Image(systemName:["app.fill","hammer.fill","safari","square.stack","folder"][i])
                            .foregroundStyle(model.ink.tint(module)).frame(width:14)
                        Text(name); Spacer(); Text(value(i)).monospacedDigit()
                    }.font(.caption)
                }
            }
        }.padding(.top,3)
    }
}
struct DetailContent: View {
    @ObservedObject var model: Studio
    let module: Module
    let inner: CGFloat
    private var tint: Color { model.ink.tint(module) }
    private var fields:[Datum] {
        switch module {
        case .gpu: [Datum("核心数","16"),Datum("频率","1.40 GHz"),Datum("渲染","32%"),Datum("分块","14%"),Datum("显存","4.6 GB"),Datum("温度","\(model.temp-3)°C")]
        case .memory: [Datum("已用",model.reading(.memory)),Datum("总容量","32 GB"),Datum("交换","0.4 GB"),Datum("已压缩","2.8 GB"),Datum("压力","正常"),Datum("带宽","36.5 GB/s")]
        case .disk: [Datum("已用","442 GB"),Datum("可用","558 GB"),Datum("总容量","1 TB"),Datum("SMART","正常")]
        case .network: [Datum("信号","−48 dBm",123),Datum("网关延迟","3 ms",129),Datum("SSID","Studio-6E"),Datum("IPv4","192.168.1.24",148),Datum("IPv6","2001:db8:8a2e::7334",inner)]
        case .power:
            model.health ? [Datum("健康","94%"),Datum("循环","286 次"),Datum("容量","5715 / 6080 mAh",inner),Datum("电芯温度","31°C"),Datum("电芯压差","12 mV")] :
            [Datum("适配器","65 W"),Datum("充电","\(65-model.watts) W"),Datum("CPU","\(model.watts/2) W"),Datum("GPU","3 W"),Datum("输入协议","20 V / 3.25 A",inner)]
        default: []
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if module == .power {
                Picker("电池分页",selection:$model.health) {
                    Text("供电").tag(false);Text("健康").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                if !model.health {
                    HStack { Label("65 W",systemImage:"powerplug.fill"); Image(systemName:"arrow.right"); Text("整机 + 电池"); Spacer(); Text("充电中") }
                        .font(.caption).foregroundStyle(model.ink.e)
                }
            }
            if module == .memory || module == .disk {
                ProgressView(value:module == .disk ? 0.442 : model.memory/32).tint(tint)
            }
            DataGrid(fields:fields,width:inner,ink:model.ink)
            if module == .disk && model.rig == .desk {
                Label("外置卷",systemImage:"externaldrive").font(.caption2).foregroundStyle(.secondary)
                DataGrid(fields:[Datum("工作 SSD","612 GB / 2 TB",inner),Datum("时间机器","1.8 TB / 4 TB",inner)],width:inner,ink:model.ink)
            }
            if [.gpu,.memory,.disk,.network].contains(module) { Ranking(module:module,model:model) }
        }
    }
}
