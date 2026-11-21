import SwiftUI

struct ModuleSummary: View {
    @ObservedObject var model: Studio
    let module: Module
    let open: Bool
    private var ink: Ink { model.ink }
    private var tint: Color { ink.tint(module) }
    private var context: String {
        switch module {
        case .cpu: "10 核 · M2 Pro"
        case .gpu: "16 核 · Metal"
        case .memory: "统一内存 · 32 GB"
        case .disk: "Macintosh HD"
        case .network: "Wi-Fi · 6 GHz"
        case .power: "74% · 充电中"
        case .fan: "双风扇 · 自动"
        case .display: model.rig == .desk ? "内建 + 2 台外接" : "内建屏幕"
        case .bluetooth: "\(model.devices.count) 台已连接"
        }
    }
    var body: some View {
        HStack(spacing:7) {
            Image(systemName:module == .bluetooth ? "antenna.radiowaves.left.and.right" : module.symbol)
                .font(.system(size:14,weight:.medium)).foregroundStyle(tint)
                .frame(width:25,height:25).background(RoundedRectangle(cornerRadius:7).fill(tint.opacity(0.12)))
            VStack(alignment:.leading,spacing:1) {
                Text(module.rawValue).font(.system(size:13,weight:.semibold))
                Text(context).font(.system(size:10)).foregroundStyle(.secondary)
            }.fixedSize()
            Spacer(minLength:0)
            trailing
            Image(systemName:open ? "chevron.down":"chevron.right").font(.system(size:8,weight:.bold)).foregroundStyle(.secondary)
        }.padding(.horizontal,9).padding(.vertical,6).contentShape(Rectangle())
    }
    @ViewBuilder private var trailing: some View {
        switch module {
        case .cpu,.gpu,.fan,.memory:
            Trace(samples:(model.second-30...model.second).map { t in
                switch module {
                case .fan: Double(model.rpm(1,at:t))/55
                case .memory: model.memory/32*100 + sin(Double(t)*0.25)*1.5
                default: model.level(module,t)
                }
            },color:tint).frame(width:model.width == 300 ? 28:42,height:20)
            VStack(alignment:.trailing,spacing:1) {
                Text(model.reading(module)).font(.system(size:13,weight:.semibold)).monospacedDigit()
                if module == .memory { Label("压力正常",systemImage:"circle.fill").font(.system(size:9)).foregroundStyle(ink.e) }
            }
        case .disk: pair("已用","44.2%","可用","558 GB")
        case .network: pair("↑ 上传","2.1 MB/s","↓ 下载",model.download+" MB/s")
        case .power: pair("输入","65 W","整机","\(model.watts) W")
        case .display:
            HStack(spacing:5) {
                ForEach(model.screens) { screen in
                    unit(screen.shortName,"\(Int(model.screenBinding(screen,"亮度").wrappedValue))%")
                }
            }.padding(.horizontal,5).background(groove)
        case .bluetooth:
            HStack(spacing:4) { ForEach(model.devices) { d in Image(systemName:d.icon).font(.caption).foregroundStyle(tint) } }
                .padding(6).background(groove)
        }
    }
    private var groove:some View { RoundedRectangle(cornerRadius:6).fill(tint.opacity(0.085)) }
    private func pair(_ a:String,_ av:String,_ b:String,_ bv:String)->some View {
        HStack(spacing:5) { unit(a,av); Rectangle().fill(ink.line).frame(width:0.5,height:19); unit(b,bv) }
            .padding(.horizontal,5).background(groove)
    }
    private func unit(_ title:String,_ value:String)->some View {
        VStack(alignment:.trailing,spacing:1) {
            Text(title).font(.system(size:9)).foregroundStyle(.secondary)
            Text(value).font(.system(size:11,weight:.semibold)).monospacedDigit()
        }.fixedSize().padding(.vertical,3)
    }
}
